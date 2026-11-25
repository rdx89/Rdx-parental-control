'use strict';

const { createHash, randomBytes, randomInt, randomUUID, scrypt, timingSafeEqual } =
  require('node:crypto');
const { promisify } = require('node:util');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

initializeApp();
const db = getFirestore();
const auth = getAuth();
const deriveKey = promisify(scrypt);
const pairLifetime = 10 * 60 * 1000;

function requireRole(request, role) {
  if (request.auth?.token.role !== role) {
    throw new HttpsError('permission-denied', 'This action is unavailable for this account.');
  }
  return request.auth.uid;
}

function credentials(data) {
  const mobile = String(data?.mobile ?? '').trim().replace(/[\s()-]/g, '');
  const password = data?.password;
  if (!/^\+[1-9]\d{7,14}$/.test(mobile) ||
      typeof password !== 'string' || password.length < 8 || password.length > 128) {
    throw new HttpsError('invalid-argument', 'Use an international mobile number and a password of 8–128 characters.');
  }
  return { mobile, password };
}

const mobileKey = mobile => createHash('sha256').update(mobile).digest('hex');

async function limitAttempts(key, maximum, periodMs) {
  const ref = db.collection('attemptLimits').doc(key);
  await db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    const now = Date.now();
    const previous = snapshot.data();
    const inWindow = previous?.expiresAt.toMillis() > now;
    const count = inWindow ? previous.count : 0;
    if (count >= maximum) {
      throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
    }
    transaction.set(ref, {
      count: count + 1,
      expiresAt: inWindow ? previous.expiresAt : Timestamp.fromMillis(now + periodMs),
    });
  });
}

exports.signup = onCall(async request => {
  const { mobile, password } = credentials(request.data);
  const key = mobileKey(mobile);
  await limitAttempts('signup-' + mobileKey(request.rawRequest.ip || 'unknown'), 12, 3600000);
  const uid = randomUUID();
  const familyId = randomUUID();
  const salt = randomBytes(16).toString('hex');
  const hash = (await deriveKey(password, salt, 64)).toString('hex');
  const login = db.collection('mobileLogins').doc(key);
  await db.runTransaction(async transaction => {
    if ((await transaction.get(login)).exists) {
      throw new HttpsError('already-exists', 'This mobile number is already registered.');
    }
    transaction.create(login, { uid });
    transaction.create(db.collection('users').doc(uid), {
      mobile,
      passwordHash: salt + ':' + hash,
      familyId,
    });
    transaction.create(db.collection('families').doc(familyId), { parentUid: uid });
  });
  return { token: await auth.createCustomToken(uid, { role: 'parent' }), familyId };
});

exports.login = onCall(async request => {
  const { mobile, password } = credentials(request.data);
  const key = mobileKey(mobile);
  await limitAttempts('login-' + key, 8, 15 * 60 * 1000);
  await limitAttempts('login-ip-' + mobileKey(request.rawRequest.ip || 'unknown'), 30, 15 * 60 * 1000);
  const login = await db.collection('mobileLogins').doc(key).get();
  const account = (login.exists
    ? await db.collection('users').doc(login.get('uid')).get()
    : null)?.data();
  const [salt, hash] = (account?.passwordHash ?? '00000000000000000000000000000000:' + '00'.repeat(64)).split(':');
  const actual = await deriveKey(password, salt, 64);
  if (!timingSafeEqual(actual, Buffer.from(hash, 'hex')) || !account) {
    throw new HttpsError('unauthenticated', 'Mobile number or password is incorrect.');
  }
  return {
    token: await auth.createCustomToken(login.get('uid'), { role: 'parent' }),
    familyId: account.familyId,
  };
});

exports.issuePairCode = onCall(async request => {
  const identity = request.auth;
  if (!identity || identity.token.firebase?.sign_in_provider !== 'anonymous') {
    throw new HttpsError('permission-denied', 'A child device session is required.');
  }
  const uid = identity.uid;
  await limitAttempts('pair-issue-' + uid, 8, 10 * 60 * 1000);
  const device = db.collection('devices').doc(uid);
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const code = String(randomInt(100000, 1000000));
    const codeRef = db.collection('pairCodes').doc(code);
    const result = await db.runTransaction(async transaction => {
      const [deviceSnapshot, codeSnapshot] = await transaction.getAll(device, codeRef);
      if (deviceSnapshot.get('familyId')) {
        return { familyId: deviceSnapshot.get('familyId') };
      }
      const now = Date.now();
      if (codeSnapshot.exists && codeSnapshot.get('expiresAt').toMillis() > now) {
        return null;
      }
      const oldCode = deviceSnapshot.get('pairCode');
      const oldRef = oldCode && oldCode !== code ? db.collection('pairCodes').doc(oldCode) : null;
      const old = oldRef ? await transaction.get(oldRef) : null;
      if (old?.get('childDeviceId') === uid && old.get('status') === 'active') {
        transaction.update(oldRef, { status: 'used' });
      }
      transaction.set(codeRef, {
        childDeviceId: uid, status: 'active', familyId: null,
        createdAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + pairLifetime),
      });
      transaction.set(device, {
        pairCode: code, familyId: null, connectedAt: null,
      }, { merge: true });
      return { code, expiresAt: now + pairLifetime };
    });
    if (result) {
      return result;
    }
  }
  throw new HttpsError('unavailable', 'A code could not be issued. Try again.');
});

exports.pairChild = onCall(async request => {
  const uid = requireRole(request, 'parent');
  const code = request.data?.code;
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Enter the six digits shown on the child device.');
  }
  await limitAttempts('pair-link-' + uid, 8, 10 * 60 * 1000);
  const profile = db.collection('users').doc(uid);
  const codeRef = db.collection('pairCodes').doc(code);
  return db.runTransaction(async transaction => {
    const [parent, pair] = await transaction.getAll(profile, codeRef);
    if (!parent.exists || pair.get('status') !== 'active' ||
        pair.get('expiresAt').toMillis() <= Date.now()) {
      throw new HttpsError('not-found', 'This pairing code is invalid or expired.');
    }
    const familyId = parent.get('familyId');
    const childDeviceId = pair.get('childDeviceId');
    const device = db.collection('devices').doc(childDeviceId);
    const family = db.collection('families').doc(familyId);
    const [child, familySnapshot] = await transaction.getAll(device, family);
    if (familySnapshot.get('childDeviceId')) {
      throw new HttpsError('failed-precondition', 'This family already has a paired device.');
    }
    if (!child.exists || child.get('familyId') || child.get('pairCode') !== code) {
      throw new HttpsError('failed-precondition', 'The device cannot be paired with this code.');
    }
    transaction.update(codeRef, { status: 'used', familyId });
    transaction.update(family, { childDeviceId });
    transaction.update(device, { familyId, connectedAt: Timestamp.now() });
    return { familyId, childDeviceId };
  });
});

exports.parentProfile = onCall(async request => {
  const uid = requireRole(request, 'parent');
  const profile = await db.collection('users').doc(uid).get();
  if (!profile.exists) {
    throw new HttpsError('not-found', 'Parent profile not found.');
  }
  const familyId = profile.get('familyId');
  const family = await db.collection('families').doc(familyId).get();
  return { familyId, childDeviceId: family.get('childDeviceId') ?? null };
});

const supportedCommands = new Set(['lock', 'vibrate', 'sound', 'flashlight', 'message', 'alarm', 'silent', 'ringer_normal', 'dnd_on', 'dnd_off']);

function requireChild(request) {
  if (request.auth?.token.firebase?.sign_in_provider !== 'anonymous') {
    throw new HttpsError('permission-denied', 'A child device session is required.');
  }
  return request.auth.uid;
}

exports.registerPushToken = onCall(async request => {
  const uid = requireChild(request);
  const token = request.data?.token;
  if (typeof token !== 'string' || !token.length || token.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid device registration token.');
  }
  await db.collection('pushTokens').doc(uid).set({ token });
  return {};
});

exports.queueCommand = onCall(async request => {
  const uid = requireRole(request, 'parent');
  const { command, message } = request.data ?? {};
  if (!supportedCommands.has(command) ||
      (command === 'message' &&
       (typeof message !== 'string' || !message.trim().length || message.length > 160))) {
    throw new HttpsError('invalid-argument', 'Invalid command.');
  }
  await limitAttempts('command-' + uid, 20, 60 * 1000);
  const parent = await db.collection('users').doc(uid).get();
  const familyRef = db.collection('families').doc(parent.get('familyId'));
  const family = await familyRef.get();
  const childDeviceId = family.get('childDeviceId');
  if (!childDeviceId || family.get('parentUid') !== uid) {
    throw new HttpsError('failed-precondition', 'Pair a child device first.');
  }
  const timestamp = Timestamp.now();
  const queued = await familyRef.collection('commands').add({
    childDeviceId,
    command,
    message: command === 'message' ? message.trim() : null,
    status: 'pending',
    result: null,
    timestamp,
    expiresAt: Timestamp.fromMillis(timestamp.toMillis() + 10 * 60 * 1000),
  });
  return { commandId: queued.id };
});

exports.notifyChild = onDocumentCreated('families/{familyId}/commands/{commandId}', async event => {
  const command = event.data?.data();
  if (!command || command.expiresAt.toMillis() <= Date.now()) return;
  const registration = await db.collection('pushTokens').doc(command.childDeviceId).get();
  if (!registration.exists) return;
  try {
    await getMessaging().send({
      token: registration.get('token'),
      notification: {
        title: 'SafeGuard request',
        body: 'Open SafeGuard to review a request from your paired parent.',
      },
      android: {
        priority: 'high',
        ttl: Math.max(0, command.expiresAt.toMillis() - Date.now()),
        notification: { tag: event.params.commandId },
      },
    });
  } catch (error) {
    if (error.code !== 'messaging/registration-token-not-registered') throw error;
  }
});

exports.updateCommand = onCall(async request => {
  const uid = requireChild(request);
  const { familyId, commandId, status, result } = request.data ?? {};
  if (typeof familyId !== 'string' || !/^[a-f0-9-]{36}$/.test(familyId) ||
      typeof commandId !== 'string' || !/^[A-Za-z0-9]{20}$/.test(commandId) ||
      !['running', 'completed', 'declined', 'failed'].includes(status) ||
      (result != null && (typeof result !== 'string' || result.length > 300))) {
    throw new HttpsError('invalid-argument', 'Invalid command update.');
  }
  const command = db.collection('families').doc(familyId).collection('commands').doc(commandId);
  const device = db.collection('devices').doc(uid);
  return db.runTransaction(async transaction => {
    const [entry, child] = await transaction.getAll(command, device);
    if (child.get('familyId') !== familyId || entry.get('childDeviceId') !== uid) {
      throw new HttpsError('permission-denied', 'Command unavailable for this device.');
    }
    const current = entry.get('status');
    const canStart = current === 'pending' && ['running', 'declined'].includes(status) &&
      entry.get('expiresAt').toMillis() > Date.now();
    const canFinish = current === 'running' && ['completed', 'failed'].includes(status);
    if (!canStart && !canFinish) {
      throw new HttpsError('failed-precondition', 'This request is no longer actionable.');
    }
    transaction.update(command, { status, result: result ?? null });
    return {};
  });
});
