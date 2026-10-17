import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { hashToken } from './public-worker.mjs';
import { verifyAppleToken } from './apple-auth.mjs';

const adminToken = 'test-admin-only-0123456789abcdef0123456789';
function database() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('./migrations/0001_invited_users.sql', import.meta.url), 'utf8'));
  const db = {
    prepare(sql) {
      let bindings = [];
      return { bind(...args) { bindings = args; return this; },
        async first() { return sqlite.prepare(sql).get(...bindings) ?? null; },
        async all() { return { results: sqlite.prepare(sql).all(...bindings) }; },
        execute() { return { meta: { changes: Number(sqlite.prepare(sql).run(...bindings).changes) } }; },
        async run() { return this.execute(); }
      };
    },
    async batch(statements) {
      sqlite.exec('BEGIN');
      try { const results = statements.map(s => s.execute()); sqlite.exec('COMMIT'); return results; }
      catch (error) { sqlite.exec('ROLLBACK'); throw error; }
    },
    withSession(mode) { assert.equal(mode, 'first-primary'); return db; },
    close() { sqlite.close(); }
  };
  return db;
}
function setup(t, overrides = {}) {
  const db = database(); t.after(() => db.close());
  return { DB: db, AUTH_LIMITER: { limit: async () => ({ success: true }) }, WRITING_LIMITER: { limit: async () => ({ success: true }) }, PROVIDER_API_KEY: 'test-groq-not-live',
    MODEL: 'test-model', ADMIN_TOKEN: adminToken, GLOBAL_DAILY_LIMIT: '500', ...overrides };
}
function request(path, token, body, method = body === undefined ? 'GET' : 'POST') {
  return new Request('https://keyboard.example' + path, { method,
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
}
async function invite(env, label = 'Tester', dailyLimit = 20) {
  const result = await worker.fetch(request('/admin/users', adminToken, { label, dailyLimit }), env);
  assert.equal(result.status, 201); return result.json();
}
const payload = { text: 'Hello', action: 'grammar', language: 'en' };
const inference = async (url, options) => {
  assert.equal(String(url), 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(options.redirect, 'manual');
  return Response.json({ choices: [{ message: { content: 'Hello.' } }] });
};
test('public backend fails closed without database, limiter, key or valid quota', async t => {
  for (const overrides of [{ DB: null }, { WRITING_LIMITER: null }, { PROVIDER_API_KEY: '' }, { GLOBAL_DAILY_LIMIT: '-1' }]) {
    const env = setup(t, overrides);
    assert.equal((await worker.fetch(request('/health', ''), env)).status, 503);
  }
});
test('only owner can issue users and raw tokens are never stored or listed', async t => {
  const env = setup(t);
  assert.equal((await worker.fetch(request('/admin/users', 'wrong', { label: 'x' }), env)).status, 401);
  const issued = await invite(env);
  assert.match(issued.connection.token, /^[a-f0-9]{64}$/);
  assert.equal(issued.connection.endpoint, 'https://keyboard.example/write');
  const row = await env.DB.prepare('SELECT * FROM clients').first();
  assert.equal(row.token_hash, await hashToken(issued.connection.token));
  const listing = await (await worker.fetch(request('/admin/users', adminToken), env)).text();
  assert.equal(listing.includes(issued.connection.token), false);
  assert.equal(listing.includes(row.token_hash), false);
});
test('uninvited callers and admin credentials cannot invoke inference', async t => {
  const env = setup(t); let calls = 0;
  for (const token of ['a'.repeat(64), adminToken, 'wrong']) {
    const response = await worker.fetch(request('/write', token, payload), env, {}, () => { calls++; });
    assert.equal(response.status, 401);
  }
  assert.equal(calls, 0);
});
test('each user has an independent quota enforced by the actual SQLite statement', async t => {
  const env = setup(t), a = await invite(env, 'A', 1), b = await invite(env, 'B', 1);
  for (const user of [a, b]) {
    const response = await worker.fetch(request('/write', user.connection.token, payload), env, {}, inference);
    assert.equal(response.status, 200); assert.deepEqual(await response.json(), { text: 'Hello.' });
    assert.equal((await worker.fetch(request('/write', user.connection.token, payload), env, {}, inference)).status, 429);
  }
});
test('global quota cannot be bypassed by another user or parallel requests', async t => {
  const env = setup(t, { GLOBAL_DAILY_LIMIT: '1' }), a = await invite(env, 'A'), b = await invite(env, 'B');
  const results = await Promise.all([a, b, a, b].map(u => worker.fetch(request('/write', u.connection.token, payload), env, {}, inference)));
  assert.equal(results.filter(r => r.status === 200).length, 1);
  assert.equal(results.filter(r => r.status === 429).length, 3);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM usage_events').first()).n, 1);
});
test('revoked users immediately lose access and cannot issue users', async t => {
  const env = setup(t), user = await invite(env);
  assert.equal((await worker.fetch(request('/admin/users', user.connection.token, { label: 'Bad' }), env)).status, 401);
  assert.equal((await worker.fetch(request(`/admin/users/${user.id}/revoke`, adminToken, {}), env)).status, 200);
  assert.equal((await worker.fetch(request('/write', user.connection.token, payload), env, {}, inference)).status, 401);
});
test('provider failures consume an attempt but never leak submitted text or keys', async t => {
  const env = setup(t), user = await invite(env);
  const response = await worker.fetch(request('/write', user.connection.token, payload), env, {}, async () => { throw Error(env.PROVIDER_API_KEY); });
  assert.equal(response.status, 502);
  const body = await response.text(); assert.equal(body.includes(env.PROVIDER_API_KEY), false); assert.equal(body.includes('Hello'), false);
  const usage = await (await worker.fetch(request('/me', user.connection.token), env)).json();
  assert.equal(usage.used, 1);
});
test('database and edge-limiter failures never call the model', async t => {
  const env = setup(t), user = await invite(env); let called = false;
  env.WRITING_LIMITER.limit = async () => ({ success: false });
  assert.equal((await worker.fetch(request('/write', user.connection.token, payload), env, {}, () => { called = true; })).status, 429);
  env.DB = { withSession: () => { throw Error('database details'); } };
  const response = await worker.fetch(request('/write', user.connection.token, payload), env, {}, () => { called = true; });
  assert.equal(response.status, 503); assert.equal(called, false); assert.equal((await response.text()).includes('database details'), false);
});
test('invalid admin inputs, unknown routes and methods do not create users', async t => {
  const env = setup(t);
  for (const dailyLimit of [0, 1001, '10', 1.5]) assert.equal((await worker.fetch(request('/admin/users', adminToken, { label: 'A', dailyLimit }), env)).status, 400);
  assert.equal((await worker.fetch(request('/anything', ''), env)).status, 404);
  assert.equal((await worker.fetch(request('/write', '', undefined), env)).status, 405);
});
test('scheduled cleanup removes old metadata and leaves current-day reservations', async t => {
  const env = setup(t), user = await invite(env); let cleanup;
  await env.DB.prepare('INSERT INTO usage_events VALUES (?, ?, ?, ?)').bind('old', user.id, '2000-01-01', 1).run();
  await worker.fetch(request('/write', user.connection.token, payload), env, {}, inference);
  await worker.scheduled({}, env, { waitUntil: task => { cleanup = task; } }); await cleanup;
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM usage_events').first()).n, 1);
});

test('anonymous traffic is limited before any database access', async t => {
  const env = setup(t, { AUTH_LIMITER: { limit: async () => ({ success: false }) } });
  env.DB = { withSession: () => { throw Error('must not query'); } };
  assert.equal((await worker.fetch(request('/write', 'a'.repeat(64), payload), env)).status, 429);
});

// Verify real RSA signatures and actual SQLite transactions; no Apple or provider network calls.
const signing = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', signing.publicKey), kid: 'test-apple-key', alg: 'RS256', use: 'sig' };
const appleFetch = async (url, options) => String(url) === 'https://appleid.apple.com/auth/keys' ? Response.json({ keys: [jwk] }) : inference(url, options);
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
async function identity(nonce, overrides = {}, header = {}) {
  const now = Math.floor(Date.now() / 1000);
  const value = encode({ alg: 'RS256', kid: jwk.kid, ...header }) + '.' + encode({ iss: 'https://appleid.apple.com', aud: 'com.wiantribe.keyboard', sub: 'private-apple-subject', iat: now, exp: now + 300, nonce, ...overrides });
  return value + '.' + Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signing.privateKey, new TextEncoder().encode(value))).toString('base64url');
}
function appleSetup(t, overrides = {}) { return setup(t, { APPLE_SIGNIN_ENABLED: 'true', APPLE_CLIENT_ID: 'com.wiantribe.keyboard', APPLE_DAILY_LIMIT: '2', ...overrides }); }
async function challenge(env) {
  const response = await worker.fetch(request('/auth/challenge', '', {}), env, {}, appleFetch);
  assert.equal(response.status, 200); return response.json();
}
async function signIn(env) {
  const c = await challenge(env);
  const response = await worker.fetch(request('/auth/apple', '', { challengeID: c.id, identityToken: await identity(c.nonce) }), env, {}, appleFetch);
  assert.equal(response.status, 200); return response.json();
}
test('Apple identity verification rejects invalid signatures, claims and signing algorithms', async () => {
  const good = await identity('nonce');
  assert.equal((await verifyAppleToken(good, 'com.wiantribe.keyboard', appleFetch)).sub, 'private-apple-subject');
  for (const claims of [{ iss: 'attacker' }, { aud: 'another.app' }, { exp: 1 }, { iat: 9999999999 }, { sub: '' }, { nonce: null }]) {
    await assert.rejects(verifyAppleToken(await identity('nonce', claims), 'com.wiantribe.keyboard', appleFetch));
  }
  await assert.rejects(verifyAppleToken(await identity('nonce', {}, { alg: 'none' }), 'com.wiantribe.keyboard', appleFetch));
  const parts = good.split('.'); parts[1] = encode({ sub: 'forged' });
  await assert.rejects(verifyAppleToken(parts.join('.'), 'com.wiantribe.keyboard', appleFetch));
  await assert.rejects(verifyAppleToken(await identity('nonce', {}, { kid: 'unknown' }), 'com.wiantribe.keyboard', appleFetch));
});
test('Apple sign-in upgrades schema, stores only hashes and shares quota across sessions', async t => {
  const env = appleSetup(t), a = await signIn(env), b = await signIn(env);
  assert.match(a.token, /^[a-f0-9]{64}$/); assert.notEqual(a.token, b.token);
  assert.ok(a.expiresAtSeconds > Date.now() / 1000);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM clients').first()).n, 1);
  const session = await env.DB.prepare('SELECT token_hash FROM account_sessions LIMIT 1').first();
  assert.notEqual(session.token_hash, a.token);
  const account = await env.DB.prepare('SELECT subject_hash FROM apple_accounts').first();
  assert.match(account.subject_hash, /^[a-f0-9]{64}$/);
  for (const token of [a.token, b.token]) assert.equal((await worker.fetch(request('/write', token, payload), env, {}, appleFetch)).status, 200);
  assert.equal((await worker.fetch(request('/write', b.token, payload), env, {}, appleFetch)).status, 429);
  assert.equal((await (await worker.fetch(request('/me', a.token), env)).json()).used, 2);
  const legacy = await invite(env);
  assert.equal((await worker.fetch(request('/me', legacy.connection.token), env)).status, 200);
});
test('Apple challenges reject nonce mismatch, expiration and concurrent replay', async t => {
  const env = appleSetup(t), c = await challenge(env);
  const send = async jwt => worker.fetch(request('/auth/apple', '', { challengeID: c.id, identityToken: jwt }), env, {}, appleFetch);
  assert.equal((await send(await identity('wrong-nonce'))).status, 401);
  const jwt = await identity(c.nonce);
  const replies = await Promise.all([send(jwt), send(jwt)]);
  assert.deepEqual(replies.map(r => r.status).sort(), [200, 401]);
  const expired = await challenge(env);
  await env.DB.prepare('UPDATE auth_challenges SET expires_at = 1 WHERE id = ?').bind(expired.id).run();
  assert.equal((await worker.fetch(request('/auth/apple', '', { challengeID: expired.id, identityToken: await identity(expired.nonce) }), env, {}, appleFetch)).status, 401);
});
test('Apple sign-out revokes one session; account deletion revokes all and cannot reset quota', async t => {
  const env = appleSetup(t, { APPLE_DAILY_LIMIT: '1' }), a = await signIn(env), b = await signIn(env);
  assert.equal((await worker.fetch(request('/auth/logout', a.token, {}), env)).status, 200);
  assert.equal((await worker.fetch(request('/me', a.token), env)).status, 401);
  assert.equal((await worker.fetch(request('/write', b.token, payload), env, {}, appleFetch)).status, 200);
  assert.equal((await worker.fetch(request('/account/delete', b.token, {}), env)).status, 200);
  assert.equal((await worker.fetch(request('/me', b.token), env)).status, 401);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM apple_accounts').first()).n, 0);
  const c = await signIn(env);
  assert.equal((await worker.fetch(request('/write', c.token, payload), env, {}, appleFetch)).status, 429);
});
test('Apple session limit, expiration and admin revocation are enforced', async t => {
  const env = appleSetup(t), first = await signIn(env);
  let latest;
  for (let i = 0; i < 5; i++) latest = await signIn(env);
  assert.equal((await worker.fetch(request('/me', first.token), env)).status, 401);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM account_sessions').first()).n, 5);
  await env.DB.prepare('UPDATE account_sessions SET expires_at = 1 WHERE token_hash = ?').bind(await hashToken(latest.token)).run();
  assert.equal((await worker.fetch(request('/me', latest.token), env)).status, 401);
  const active = await signIn(env), client = await env.DB.prepare('SELECT id FROM clients').first();
  assert.equal((await worker.fetch(request(`/admin/users/${client.id}/revoke`, adminToken, {}), env)).status, 200);
  assert.equal((await worker.fetch(request('/me', active.token), env)).status, 401);
  const c = await challenge(env);
  assert.equal((await worker.fetch(request('/auth/apple', '', { challengeID: c.id, identityToken: await identity(c.nonce) }), env, {}, appleFetch)).status, 403);
});
test('account deletion revokes the Apple grant when Apple credentials are configured', async t => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  const env = appleSetup(t, { APPLE_TEAM_ID: 'TEAM123456', APPLE_KEY_ID: 'KEY1234567', APPLE_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----` });
  const seen = [];
  const fetcher = async (url, options) => {
    if (String(url).startsWith('https://appleid.apple.com/auth/token') || String(url).startsWith('https://appleid.apple.com/auth/revoke')) {
      const body = new URLSearchParams(String(options.body)); seen.push([String(url), body.get('token') || body.get('code'), body.get('client_secret').split('.').length]);
      return Response.json({ refresh_token: 'refresh-1' });
    }
    return appleFetch(url, options);
  };
  const account = await signIn(env);
  const reply = await worker.fetch(request('/account/delete', account.token, { authorizationCode: 'code-1' }), env, {}, fetcher);
  assert.equal(reply.status, 200);
  assert.deepEqual(await reply.json(), { deleted: true, appleRevoked: true });
  assert.deepEqual(seen, [['https://appleid.apple.com/auth/token', 'code-1', 3], ['https://appleid.apple.com/auth/revoke', 'refresh-1', 3]]);
});
