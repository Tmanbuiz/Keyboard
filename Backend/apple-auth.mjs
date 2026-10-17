// Native Sign in with Apple. No email, name, Apple password or identity token is persisted.
const APPLE_KEYS = 'https://appleid.apple.com/auth/keys';
const schema = [
  'CREATE TABLE IF NOT EXISTS apple_accounts (subject_hash TEXT PRIMARY KEY, client_id TEXT NOT NULL UNIQUE)',
  'CREATE TABLE IF NOT EXISTS account_sessions (token_hash TEXT PRIMARY KEY, client_id TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS sessions_by_client ON account_sessions(client_id)',
  'CREATE TABLE IF NOT EXISTS auth_challenges (id TEXT PRIMARY KEY, nonce_hash TEXT NOT NULL, expires_at INTEGER NOT NULL)'
];
const initialized = new WeakMap();
export async function initializeAuth(database) {
  if (!initialized.has(database)) initialized.set(database, database.batch(schema.map(sql => database.prepare(sql))).catch(error => { initialized.delete(database); throw error; }));
  await initialized.get(database);
}
export async function digest(text) {
  const data = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(data)].map(v => v.toString(16).padStart(2, '0')).join('');
}
function randomToken() { return [...crypto.getRandomValues(new Uint8Array(32))].map(v => v.toString(16).padStart(2, '0')).join(''); }
function json(body, status = 200) { return Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } }); }
function unbase64(text) {
  if (!/^[A-Za-z0-9_-]+$/.test(text)) throw Error('Invalid token');
  const encoded = text.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(encoded + '='.repeat((4 - encoded.length % 4) % 4)), c => c.charCodeAt(0));
}
let cachedKeys = [], fetchedAt = 0;
async function publicKey(kid, fetcher) {
  const now = Date.now();
  if (!cachedKeys.length || now - fetchedAt > 3600000 || (!cachedKeys.some(k => k.kid === kid) && now - fetchedAt > 60000)) {
    const response = await fetcher(APPLE_KEYS, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw Error('Apple verification unavailable');
    const text = await response.text();
    if (text.length > 50000) throw Error('Invalid Apple keys');
    const keys = JSON.parse(text).keys;
    if (!Array.isArray(keys) || keys.length > 20) throw Error('Invalid Apple keys');
    cachedKeys = keys; fetchedAt = now;
  }
  const key = cachedKeys.find(k => k.kid === kid && k.kty === 'RSA' && (!k.use || k.use === 'sig') && (!k.alg || k.alg === 'RS256'));
  if (!key) throw Error('Unknown Apple signing key');
  return crypto.subtle.importKey('jwk', key, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}
export async function verifyAppleToken(token, audience, fetcher = fetch) {
  if (typeof token !== 'string' || token.length > 16000 || !audience) throw Error('Invalid token');
  const parts = token.split('.'); if (parts.length !== 3) throw Error('Invalid token');
  const header = JSON.parse(new TextDecoder().decode(unbase64(parts[0])));
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' || header.kid.length > 128) throw Error('Invalid token');
  const key = await publicKey(header.kid, fetcher);
  if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, unbase64(parts[2]), new TextEncoder().encode(parts[0] + '.' + parts[1]))) throw Error('Invalid signature');
  const claims = JSON.parse(new TextDecoder().decode(unbase64(parts[1]))), now = Math.floor(Date.now() / 1000);
  const fail = reason => { throw Object.assign(Error(reason), { reason }); };
  if (claims.iss !== 'https://appleid.apple.com') fail('issuer');
  if (claims.aud !== audience) fail('audience');
  if (!Number.isSafeInteger(claims.exp) || claims.exp <= now) fail('expired');
  if (!Number.isSafeInteger(claims.iat) || claims.iat > now + 60 || claims.exp <= claims.iat) fail('issued-at');
  if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 256) fail('subject');
  if (typeof claims.nonce !== 'string' || claims.nonce.length > 128) fail('nonce-missing');
  return claims;
}
async function readJSON(request) {
  if (!request.headers.get('Content-Type')?.startsWith('application/json') || !request.body) throw Error('JSON required');
  const reader = request.body.getReader(), decoder = new TextDecoder(); let text = '', size = 0;
  try {
    while (true) { const { value, done } = await reader.read(); if (done) break; size += value.byteLength;
      if (size > 24000) { await reader.cancel(); throw Error('Too large'); } text += decoder.decode(value, { stream: true }); }
    return JSON.parse(text + decoder.decode());
  } finally { reader.releaseLock(); }
}
export async function appleAuth(request, env, database, fetcher = fetch) {
  if (env.APPLE_SIGNIN_ENABLED !== 'true' || !env.APPLE_CLIENT_ID) return json({ error: 'Sign in is not enabled yet. Please try again after the service update.' }, 503);
  await initializeAuth(env.DB);
  const path = new URL(request.url).pathname;
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);
  if (path === '/auth/challenge') {
    const nonce = randomToken(), id = crypto.randomUUID(), now = Date.now();
    // Cleanup and a global outstanding-challenge cap bound unverified sign-in storage.
    await database.prepare('DELETE FROM auth_challenges WHERE expires_at < ?').bind(now).run();
    const result = await database.prepare('INSERT INTO auth_challenges SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM auth_challenges) < 10000')
      .bind(id, await digest(nonce), now + 300000).run();
    return result.meta.changes === 1 ? json({ id, nonce }) : json({ error: 'Sign in is busy. Try again shortly.' }, 429);
  }
  if (path !== '/auth/apple') return json({ error: 'Not found' }, 404);
  let input;
  try { input = await readJSON(request); } catch { return json({ error: 'Invalid sign-in request' }, 400); }
  if (typeof input?.challengeID !== 'string' || !/^[a-f0-9-]{36}$/.test(input.challengeID)) return json({ error: 'Invalid sign-in request' }, 400);
  let claims;
  try { claims = await verifyAppleToken(input.identityToken, env.APPLE_CLIENT_ID, fetcher); }
  catch (error) { return json({ error: 'Apple sign-in could not be verified. Please try again.', reason: String(error?.reason || error?.message || 'unknown').slice(0, 60) }, 401); }
  // DELETE ... RETURNING consumes a valid challenge exactly once, even with concurrent replays.
  // Apple returns the nonce as sent; some SDKs return its SHA-256 instead. Accept either form of the same single-use challenge.
  const challenge = await database.prepare('DELETE FROM auth_challenges WHERE id = ? AND (nonce_hash = ? OR nonce_hash = ?) AND expires_at > ? RETURNING id')
    .bind(input.challengeID, await digest(claims.nonce), claims.nonce, Date.now()).first();
  if (!challenge) return json({ error: 'Sign-in request expired or was already used. Please try again.' }, 401);
  const subject = await digest(env.APPLE_CLIENT_ID + ':' + claims.sub), id = 'apple_' + subject;
  const legacyPlaceholder = await digest(randomToken());
  const allowance = Number(env.APPLE_DAILY_LIMIT || '20');
  if (!Number.isSafeInteger(allowance) || allowance < 1 || allowance > 1000) return json({ error: 'Service not configured' }, 503);
  await database.batch([
    database.prepare('INSERT OR IGNORE INTO clients (id, label, token_hash, daily_limit, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, 'Apple account', legacyPlaceholder, allowance, Date.now()),
    database.prepare('INSERT OR IGNORE INTO apple_accounts (subject_hash, client_id) VALUES (?, ?)').bind(subject, id)
  ]);
  const account = await database.prepare('SELECT id, active FROM clients WHERE id = ?').bind(id).first();
  if (!account || account.active !== 1) return json({ error: 'This account has been disabled. Contact WianTribe support.' }, 403);
  const token = randomToken(), expires = Date.now() + 30 * 86400000;
  await database.batch([
    database.prepare('DELETE FROM account_sessions WHERE expires_at <= ?').bind(Date.now()),
    database.prepare('INSERT INTO account_sessions (token_hash, client_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
      .bind(await digest(token), id, expires, Date.now()),
    database.prepare('DELETE FROM account_sessions WHERE client_id = ? AND token_hash NOT IN (SELECT token_hash FROM account_sessions WHERE client_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 5)').bind(id, id)
  ]);
  return json({ token, expiresAtSeconds: Math.floor(expires / 1000), dailyLimit: allowance });
}
export async function accountClient(database, token) {
  // Old invitation connections remain valid on the existing endpoint.
  const hash = await digest(token);
  return await database.prepare(`SELECT clients.id, clients.daily_limit FROM account_sessions
      JOIN clients ON clients.id = account_sessions.client_id
      WHERE account_sessions.token_hash = ? AND account_sessions.expires_at > ? AND clients.active = 1`)
    .bind(hash, Date.now()).first();
}
function b64url(bytes) { return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
// Apple requires apps with Sign in with Apple to revoke the user's tokens when the account is deleted.
// Needs APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY (the .p8 contents) as Worker secrets; without them deletion still works but returns appleRevoked:false.
export async function revokeAppleGrant(env, authorizationCode, fetcher = fetch) {
  if (!env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY || !env.APPLE_CLIENT_ID || typeof authorizationCode !== 'string' || !authorizationCode || authorizationCode.length > 2000) return false;
  try {
    const pem = env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n').replace(/-----[A-Z ]+-----|\s/g, '');
    const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    const now = Math.floor(Date.now() / 1000), encode = value => b64url(new TextEncoder().encode(JSON.stringify(value)));
    const unsigned = encode({ alg: 'ES256', kid: env.APPLE_KEY_ID, typ: 'JWT' }) + '.' + encode({ iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: env.APPLE_CLIENT_ID });
    const clientSecret = unsigned + '.' + b64url(new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned))));
    const post = (path, fields) => fetcher('https://appleid.apple.com/auth/' + path, { method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(10000),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ client_id: env.APPLE_CLIENT_ID, client_secret: clientSecret, ...fields }) });
    const exchange = await post('token', { grant_type: 'authorization_code', code: authorizationCode });
    if (!exchange.ok) return false;
    const tokens = await exchange.json();
    const [token, hint] = tokens.refresh_token ? [tokens.refresh_token, 'refresh_token'] : [tokens.access_token, 'access_token'];
    if (!token) return false;
    return (await post('revoke', { token, token_type_hint: hint })).ok;
  } catch { return false; }
}
export async function accountAction(request, env, database, client, token, fetcher = fetch) {
  const path = new URL(request.url).pathname;
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);
  if (path === '/auth/logout') {
    await database.prepare('DELETE FROM account_sessions WHERE token_hash = ?').bind(await digest(token)).run();
    return json({ signedOut: true });
  }
  if (path === '/account/delete') {
    const ownAccount = await database.prepare('SELECT subject_hash FROM apple_accounts WHERE client_id = ?').bind(client.id).first();
    if (!ownAccount) return json({ error: 'This connection is managed by invitation. Contact WianTribe to remove it.' }, 400);
    let authorizationCode; try { authorizationCode = (await readJSON(request))?.authorizationCode; } catch { authorizationCode = undefined; }
    const appleRevoked = await revokeAppleGrant(env, authorizationCode, fetcher);
    await database.batch([
      database.prepare('DELETE FROM account_sessions WHERE client_id = ?').bind(client.id),
      database.prepare('DELETE FROM apple_accounts WHERE client_id = ?').bind(client.id),
      database.prepare('DELETE FROM clients WHERE id = ?').bind(client.id)
    ]);
    // Daily usage stays under an app-specific pseudonymous bucket for up to 30 days, preventing quota-reset abuse.
    // No Apple refresh/access token is collected. The app links Apple's own access-revocation instructions.
    return json({ deleted: true, appleRevoked });
  }
  return json({ error: 'Not found' }, 404);
}
