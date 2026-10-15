import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { hashToken } from './public-worker.mjs';

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
        async run() { return { meta: { changes: Number(sqlite.prepare(sql).run(...bindings).changes) } }; }
      };
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
  assert.equal(options.redirect, 'error');
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
