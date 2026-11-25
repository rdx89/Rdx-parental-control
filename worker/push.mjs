const encode = new TextEncoder();
const base64Url = value => btoa(String.fromCharCode(...value))
  .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
let cached;

async function accessToken(account) {
  const now = Math.floor(Date.now() / 1000);
  if (cached?.email === account.client_email && cached.until > now + 60) return cached.token;
  const header = base64Url(encode.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64Url(encode.encode(JSON.stringify({
    iss: account.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    iat: now,
    exp: now + 3600,
  })));
  const input = header + '.' + claims;
  const pem = account.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const pkcs8 = Uint8Array.from(atob(pem), char => char.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', pkcs8,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encode.encode(input));
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: input + '.' + base64Url(new Uint8Array(signature)),
  }) });
  if (!response.ok) throw new Error('FCM authentication failed.');
  const auth = await response.json();
  cached = { email: account.client_email, until: now + auth.expires_in, token: auth.access_token };
  return cached.token;
}

export async function notifyChild(env, registrationToken, commandId) {
  if (!env.FCM_ACCOUNT) return;
  const account = JSON.parse(env.FCM_ACCOUNT);
  const token = await accessToken(account);
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: {
      token: registrationToken,
      notification: {
        title: 'RDX SafeGuard request',
        body: 'Open RDX SafeGuard to review the request.',
      },
      android: { priority: 'high', ttl: '600s', notification: { tag: commandId } },
    } }),
  });
  if (!response.ok) throw new Error('FCM request failed.');
}
