import { notifyChild } from './push.mjs';

const controls = new Set([
  'lock', 'vibrate', 'sound', 'flashlight', 'message', 'alarm', 'silent',
  'ringer_normal', 'dnd_on', 'dnd_off', 'battery_status',
]);
const lifetime = 600_000;
const encode = new TextEncoder();

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const error = (status, message) => { throw new RequestError(status, message); };
const stmt = (env, sql, ...args) => env.DB.prepare(sql).bind(...args);
const hex = bytes => Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('');

async function identity(env, operation, body) {
  const url = new URL('https://identitytoolkit.googleapis.com/v1/accounts:' + operation);
  url.searchParams.set('key', env.FIREBASE_API_KEY);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const result = await res.json();
  if (!res.ok) {
    const code = result?.error?.message;
    if (code === 'EMAIL_EXISTS') error(409, 'This number is already registered. Try signing in.');
    if (code === 'TOO_MANY_ATTEMPTS_TRY_LATER') error(429, 'Too many attempts. Try again later.');
    if (res.status >= 500 || code === 'OPERATION_NOT_ALLOWED') {
      error(503, 'Account service is temporarily unavailable.');
    }
    error(401, 'Login failed or the session expired.');
  }
  return result;
}

async function throttle(env, key, limit, duration) {
  const now = Date.now();
  const row = await stmt(env, `
    INSERT INTO rate_limits (key, count, expires_at) VALUES (?, 1, ?)
    ON CONFLICT(key) DO UPDATE SET
      count = CASE WHEN rate_limits.expires_at <= ? THEN 1 ELSE rate_limits.count + 1 END,
      expires_at = CASE WHEN rate_limits.expires_at <= ? THEN excluded.expires_at ELSE rate_limits.expires_at END
    WHERE rate_limits.expires_at <= ? OR rate_limits.count < ?
    RETURNING count
  `, key, now + duration, now, now, now, limit).first();
  if (row == null) error(429, 'Too many attempts. Try again later.');
}

async function authenticate(env, name, input, request) {
  const mobile = typeof input.mobile === 'string' ? input.mobile.trim().replace(/[\s()-]/g, '') : '';
  const password = input.password;
  if (!/^\+[1-9]\d{7,14}$/.test(mobile) || typeof password !== 'string' ||
      password.length < 8 || password.length > 128) {
    error(400, 'Use an international mobile number and a password of 8–128 characters.');
  }
  const key = await crypto.subtle.importKey('raw', encode.encode(env.LOGIN_ALIAS_SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const alias = hex(await crypto.subtle.sign('HMAC', key, encode.encode(mobile)));
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const fingerprint = hex(await crypto.subtle.sign('HMAC', key, encode.encode(ip)));
  await throttle(env, 'auth-ip:' + fingerprint, 24, 900_000);
  await throttle(env, 'auth-account:' + alias, 8, 900_000);
  // The app displays a mobile number. Firebase manages the password for this internal identifier.
  const email = alias + '@rdx-safeguard.invalid';
  const result = await identity(env, name === 'signup' ? 'signUp' : 'signInWithPassword',
    { email, password, returnSecureToken: true });
  await stmt(env, 'INSERT OR IGNORE INTO parents (id, created_at) VALUES (?, ?)',
    result.localId, Date.now()).run();
  return { loginAlias: email };
}

async function caller(env, request) {
  const token = request.headers.get('authorization');
  if (token == null || !/^Bearer [A-Za-z0-9._-]{20,4096}$/.test(token)) {
    error(401, 'Sign in first.');
  }
  const { users } = await identity(env, 'lookup', { idToken: token.slice(7) });
  const account = users?.[0];
  if (!account?.localId || account.disabled) error(401, 'This session is unavailable.');
  const uid = account.localId;
  if (await stmt(env, 'SELECT id FROM parents WHERE id = ?', uid).first()) {
    return { uid, role: 'parent' };
  }
  if (account.email || account.providerUserInfo?.length) error(403, 'A linked account is required.');
  return { uid, role: 'child' };
}

function allow(user, role) {
  if (user.role !== role) error(403, 'This operation is unavailable for this account.');
}

async function issue(env, uid) {
  const now = Date.now();
  await stmt(env, 'INSERT OR IGNORE INTO devices(id) VALUES (?)', uid).run();
  const connected = await stmt(env, 'SELECT parent_id FROM devices WHERE id = ?', uid).first();
  if (connected.parent_id) return {};
  await throttle(env, 'issue:' + uid, 12, lifetime);
  for (let attempt = 0; attempt < 12; attempt++) {
    const number = crypto.getRandomValues(new Uint32Array(1))[0];
    if (number >= 4_294_800_000) continue;
    const code = String(100000 + number % 900000);
    const changes = await env.DB.batch([
      stmt(env, 'DELETE FROM pair_codes WHERE code = ? AND expires_at <= ?', code, now),
      stmt(env, `
        INSERT INTO pair_codes(code, device_id, expires_at)
        SELECT ?, id, ? FROM devices WHERE id = ? AND parent_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM pair_codes WHERE code = ? AND device_id <> ?)
        ON CONFLICT(device_id) DO UPDATE SET code = excluded.code, expires_at = excluded.expires_at
        RETURNING code
      `, code, now + lifetime, uid, code, uid),
    ]);
    if (changes[1].results.length) return { code };
  }
  error(503, 'Could not create a pairing code. Try again.');
}

async function pair(env, uid, code) {
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) error(400, 'Enter all six digits.');
  await throttle(env, 'pair:' + uid, 8, lifetime);
  const pairingId = crypto.randomUUID();
  const now = Date.now();
  const changes = await env.DB.batch([
    stmt(env, `
      UPDATE devices SET parent_id = ?, pairing_id = ?, paired_at = ?
      WHERE parent_id IS NULL
        AND id = (SELECT device_id FROM pair_codes WHERE code = ? AND expires_at > ?)
        AND NOT EXISTS (SELECT 1 FROM devices WHERE parent_id = ?)
      RETURNING id
    `, uid, pairingId, now, code, now, uid),
    stmt(env, `DELETE FROM pair_codes WHERE device_id IN
      (SELECT id FROM devices WHERE pairing_id = ?)`, pairingId),
  ]);
  const deviceId = changes[0].results[0]?.id;
  if (!deviceId) error(404, 'The code expired, was already used, or this account is paired.');
  return { childDeviceId: deviceId };
}

async function execute(env, operation, user, data, context) {
  const { uid } = user;
  switch (operation) {
    case 'issuePairCode':
      allow(user, 'child');
      return issue(env, uid);
    case 'pairChild':
      allow(user, 'parent');
      return pair(env, uid, data.code);
    case 'parentProfile': {
      allow(user, 'parent');
      const device = await stmt(env, 'SELECT id FROM devices WHERE parent_id = ?', uid).first();
      const { results } = await stmt(env, `
        SELECT command, CASE WHEN status = 'pending' AND expires_at <= ? THEN 'expired'
          ELSE status END AS status, result
        FROM commands WHERE parent_id = ? ORDER BY created_at DESC LIMIT 10
      `, Date.now(), uid).all();
      return { childDeviceId: device?.id ?? null, commands: results };
    }
    case 'deviceInbox': {
      allow(user, 'child');
      const device = await stmt(env, 'SELECT parent_id, pairing_id FROM devices WHERE id = ?', uid).first();
      if (!device?.parent_id) return { connected: false, commands: [] };
      const { results } = await stmt(env, `
        SELECT id, command, message FROM commands
        WHERE device_id = ? AND pairing_id = ? AND status = 'pending' AND expires_at > ?
        ORDER BY created_at DESC LIMIT 20
      `, uid, device.pairing_id, Date.now()).all();
      return { connected: true, commands: results };
    }
    case 'registerPushToken': {
      allow(user, 'child');
      if (typeof data.token !== 'string' || data.token.length < 10 || data.token.length > 4096) {
        error(400, 'Invalid notification token.');
      }
      await stmt(env, 'UPDATE devices SET push_token = ? WHERE id = ?', data.token, uid).run();
      return {};
    }
    case 'queueCommand': {
      allow(user, 'parent');
      const command = data.command;
      const message = typeof data.message === 'string' ? data.message.trim() : '';
      if (!controls.has(command) || (command === 'message' && (!message || message.length > 160))) {
        error(400, 'Invalid request.');
      }
      await throttle(env, 'queue:' + uid, 20, 60_000);
      const id = crypto.randomUUID();
      const now = Date.now();
      const queued = await stmt(env, `
        INSERT INTO commands (id, parent_id, device_id, pairing_id, command, message, created_at, expires_at)
        SELECT ?, parent_id, id, pairing_id, ?, ?, ?, ? FROM devices WHERE parent_id = ?
        RETURNING device_id
      `, id, command, command === 'message' ? message : null, now, now + lifetime, uid).first();
      if (!queued) error(409, 'Pair a Child device first.');
      context.waitUntil((async () => {
        const related = await stmt(env, 'SELECT push_token FROM devices WHERE id = ? AND parent_id = ?',
          queued.device_id, uid).first();
        if (related?.push_token) await notifyChild(env, related.push_token, id);
      })().catch(() => console.error('Push delivery failed.')));
      return { commandId: id };
    }
    case 'updateCommand': {
      allow(user, 'child');
      const { commandId, status, result } = data;
      if (typeof commandId !== 'string' || !/^[a-f0-9-]{36}$/.test(commandId) ||
          !['running', 'completed', 'declined', 'failed'].includes(status) ||
          (result != null && (typeof result !== 'string' || result.length > 300))) {
        error(400, 'Invalid request status.');
      }
      const next = await stmt(env, `
        UPDATE commands SET status = ?, result = ?
        WHERE id = ? AND device_id = ?
          AND pairing_id = (SELECT pairing_id FROM devices WHERE id = ?)
          AND ((status = 'pending' AND ? IN ('running', 'declined') AND expires_at > ?)
            OR (status = 'running' AND ? IN ('completed', 'failed')))
        RETURNING id
      `, status, result ?? null, commandId, uid, uid, status, Date.now(), status).first();
      if (!next) error(409, 'The request expired, was disconnected, or was already handled.');
      return {};
    }
    case 'unlinkDevice':
      if (user.role === 'parent') {
        await stmt(env, 'UPDATE devices SET parent_id = NULL, pairing_id = NULL, paired_at = NULL WHERE parent_id = ?', uid).run();
      } else {
        await stmt(env, 'UPDATE devices SET parent_id = NULL, pairing_id = NULL, paired_at = NULL WHERE id = ?', uid).run();
      }
      return {};
    default:
      error(404, 'Unknown operation.');
  }
}

export default {
  async fetch(request, env, context) {
    try {
      const { pathname } = new URL(request.url);
      if (request.method === 'GET' && pathname === '/health') {
        await env.DB.prepare('SELECT 1 FROM parents LIMIT 1').all();
        return Response.json({ status: 'ok' }, { headers: { 'cache-control': 'no-store' } });
      }
      if (request.method !== 'POST' || !/^\/api\/[a-zA-Z]+$/.test(pathname)) error(404, 'Unknown operation.');
      const length = Number(request.headers.get('content-length'));
      if (length > 8192) error(413, 'Request is too large.');
      const raw = await request.text();
      if (raw.length > 8192) error(413, 'Request is too large.');
      let data;
      try { data = JSON.parse(raw); } catch { error(400, 'Invalid request.'); }
      if (!data || typeof data !== 'object' || Array.isArray(data)) error(400, 'Invalid request.');
      const operation = pathname.split('/').pop();
      const result = operation === 'signup' || operation === 'login'
        ? await authenticate(env, operation, data, request)
        : await execute(env, operation, await caller(env, request), data, context);
      return Response.json(result, { headers: { 'cache-control': 'no-store' } });
    } catch (failure) {
      if (!(failure instanceof RequestError)) console.error('An API operation failed.');
      return Response.json({ error: failure instanceof RequestError ? failure.message : 'Service unavailable.' },
        { status: failure instanceof RequestError ? failure.status : 503, headers: { 'cache-control': 'no-store' } });
    }
  },
  async scheduled(_event, env) {
    const now = Date.now();
    await env.DB.batch([
      stmt(env, 'DELETE FROM rate_limits WHERE expires_at <= ?', now),
      stmt(env, 'DELETE FROM pair_codes WHERE expires_at <= ?', now),
      stmt(env, 'DELETE FROM commands WHERE created_at <= ?', now - 30 * 86_400_000),
    ]);
  },
};
