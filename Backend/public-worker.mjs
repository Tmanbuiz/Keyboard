import privateService from './worker.mjs';
import { initializeAuth, appleAuth, accountClient, accountAction } from './apple-auth.mjs';

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    'Strict-Transport-Security': 'max-age=31536000'
  } });
}
function bearer(request) {
  const value = request.headers.get('Authorization') || '';
  return /^Bearer [a-f0-9]{64}$/.test(value) ? value.slice(7) : null;
}
export async function hashToken(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
}
async function equalSecret(left, right) {
  const [a, b] = await Promise.all([hashToken(left), hashToken(right)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
function dailyCap(env) {
  const value = Number(env.GLOBAL_DAILY_LIMIT || '500');
  return Number.isSafeInteger(value) && value >= 1 && value <= 100000 ? value : null;
}
async function readJSON(request, maximum = 4096) {
  if (!request.headers.get('Content-Type')?.startsWith('application/json') || !request.body) throw new Error('Invalid JSON');
  const reader = request.body.getReader(); let size = 0, text = '';
  const decoder = new TextDecoder();
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > maximum) { await reader.cancel(); throw new Error('Too large'); }
      text += decoder.decode(value, { stream: true });
    }
    return JSON.parse(text + decoder.decode());
  } finally { reader.releaseLock(); }
}
async function admin(request, env, database, path) {
  const token = request.headers.get('Authorization') || '';
  if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 32 || token.length > 512 ||
      !token.startsWith('Bearer ') || !await equalSecret(token.slice(7), env.ADMIN_TOKEN)) return json({ error: 'Unauthorized' }, 401);
  const { success } = await env.WRITING_LIMITER.limit({ key: 'admin' });
  if (!success) return json({ error: 'Try again later' }, 429);
  if (path === '/admin/users' && request.method === 'GET') {
    const result = await database.prepare('SELECT id, label, active, daily_limit, created_at FROM clients ORDER BY created_at DESC LIMIT 200').all();
    return json({ users: result.results });
  }
  if (path === '/admin/users' && request.method === 'POST') {
    let input;
    try { input = await readJSON(request); } catch { return json({ error: 'Invalid JSON' }, 400); }
    const limit = input?.dailyLimit ?? 20;
    if (typeof input?.label !== 'string' || !input.label.trim() || input.label.length > 100 ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 1000) return json({ error: 'Use a label and dailyLimit between 1 and 1000' }, 400);
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const token = Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
    const id = crypto.randomUUID();
    await database.prepare('INSERT INTO clients (id, label, token_hash, daily_limit, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, input.label.trim(), await hashToken(token), limit, Date.now()).run();
    const endpoint = new URL('/write', request.url).toString();
    return json({ id, dailyLimit: limit, connection: { endpoint, token } }, 201);
  }
  const match = /^\/admin\/users\/([a-zA-Z0-9_-]{1,80})\/revoke$/.exec(path);
  if (match && request.method === 'POST') {
    const result = await database.prepare('UPDATE clients SET active = 0 WHERE id = ?').bind(match[1]).run();
    return result.meta.changes ? json({ revoked: true }) : json({ error: 'Not found' }, 404);
  }
  return json({ error: 'Not found' }, 404);
}
async function serve(request, env, context, fetcher) {
  const url = new URL(request.url), path = url.pathname;
  if (url.protocol !== 'https:') return json({ error: 'HTTPS required' }, 400);
  if (!env.AUTH_LIMITER) return json({ error: 'Service not configured' }, 503);
  const address = request.headers.get('CF-Connecting-IP') || 'unknown';
  const gate = await env.AUTH_LIMITER.limit({ key: 'ip:' + await hashToken(address) });
  if (!gate.success) return json({ error: 'Too many requests. Try again later.' }, 429);
  if (path === '/health' && request.method === 'GET') {
    // Never report healthy until required configuration and database schema are usable.
    if (!env.DB || !env.WRITING_LIMITER || !env.PROVIDER_API_KEY || !env.MODEL || !dailyCap(env) || !env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 32)
      return json({ status: 'not-configured' }, 503);
    await env.DB.prepare('SELECT id FROM clients LIMIT 1').first();
    if (env.APPLE_SIGNIN_ENABLED === 'true') {
      const allowance = Number(env.APPLE_DAILY_LIMIT || '20');
      if (!env.APPLE_CLIENT_ID || !Number.isSafeInteger(allowance) || allowance < 1 || allowance > 1000) return json({ status: 'not-configured' }, 503);
      await initializeAuth(env.DB);
    }
    return json({ status: 'ready', access: env.APPLE_SIGNIN_ENABLED === 'true' ? 'apple-sign-in' : 'invite-only' });
  }
  if (!env.DB || !env.WRITING_LIMITER || !dailyCap(env)) return json({ error: 'Service not configured' }, 503);
  const database = env.DB.withSession('first-primary');
  if (path === '/auth/challenge' || path === '/auth/apple') return appleAuth(request, env, database, fetcher);
  if (env.APPLE_SIGNIN_ENABLED === 'true') await initializeAuth(env.DB);
  if (path.startsWith('/admin/')) return admin(request, env, database, path);
  if (path !== '/write' && path !== '/gifs' && path !== '/me' && path !== '/auth/logout' && path !== '/account/delete') return json({ error: 'Not found' }, 404);
  if (request.method !== (['/write', '/auth/logout', '/account/delete'].includes(path) ? 'POST' : 'GET')) return json({ error: 'Method not allowed' }, 405);
  const token = bearer(request);
  if (!token) return json({ error: 'Unauthorized' }, 401);
  // One-way token hashes are stored; raw credentials never enter the database.
  let client = env.APPLE_SIGNIN_ENABLED === 'true' ? await accountClient(database, token) : null;
  if (!client) client = await database.prepare('SELECT id, daily_limit FROM clients WHERE token_hash = ? AND active = 1')
    .bind(await hashToken(token)).first();
  if (!client) return json({ error: 'Unauthorized' }, 401);
  const { success } = await env.WRITING_LIMITER.limit({ key: `client:${client.id}` });
  if (!success) return json({ error: 'Too many requests. Try again later.' }, 429);
  if (path === '/auth/logout' || path === '/account/delete') return accountAction(request, env, database, client, token);
  const day = new Date().toISOString().slice(0, 10);
  if (path === '/me') {
    const usage = await database.prepare('SELECT COUNT(*) AS used FROM usage_events WHERE client_id = ? AND day = ?').bind(client.id, day).first();
    return json({ dailyLimit: client.daily_limit, used: usage.used, resetsAt: new Date(Date.parse(day + "T00:00:00Z") + 86400000).toISOString() });
  }
  if (path === '/write' && (!env.PROVIDER_API_KEY || !env.MODEL)) return json({ error: 'Service not configured' }, 503);
  if (path === '/gifs' && !env.GIPHY_API_KEY) return json({ error: 'GIF search not configured' }, 503);
  // A single SQLite write serializes both per-user and global quota checks. No read/check/write race.
  // Attempts count even if validation or the provider subsequently fails; failures cannot be used to bypass limits.
  const reservation = await database.prepare(`INSERT INTO usage_events (id, client_id, day, created_at)
    SELECT ?, id, ?, ? FROM clients
    WHERE id = ? AND active = 1
      AND (SELECT COUNT(*) FROM usage_events WHERE client_id = clients.id AND day = ?) < daily_limit
      AND (SELECT COUNT(*) FROM usage_events WHERE day = ?) < ?`)
    .bind(crypto.randomUUID(), day, Date.now(), client.id, day, day, dailyCap(env)).run();
  if (reservation.meta.changes !== 1) return json({ error: 'Daily allowance reached. Try again after midnight UTC.', code: 'daily_limit' }, 429);
  // Reuse the existing validated text/language contract, with no public shared token and a fixed upstream host.
  const serviceEnvironment = { ...env, API_TOKEN: token, PROVIDER_URL: GROQ_URL,
    WRITING_LIMITER: { limit: async () => ({ success: true }) } };
  const guardedFetch = (input, options = {}) => fetcher(input, {
    ...options, redirect: 'error', signal: AbortSignal.timeout(25000)
  });
  return privateService.fetch(request, serviceEnvironment, context, guardedFetch);
}
export default {
  async fetch(request, env, context, fetcher = fetch) {
    try { return await serve(request, env, context, fetcher); }
    catch { return json({ error: 'Service temporarily unavailable' }, 503); }
  },
  async scheduled(_event, env, context) {
    // Keep only 30 days of usage metadata. No submitted text or AI results are stored.
    context.waitUntil((async () => {
      await env.DB.prepare('DELETE FROM usage_events WHERE created_at < ?').bind(Date.now() - 30 * 86400000).run();
      if (env.APPLE_SIGNIN_ENABLED === 'true') {
        await initializeAuth(env.DB);
        await env.DB.batch([
          env.DB.prepare('DELETE FROM auth_challenges WHERE expires_at < ?').bind(Date.now()),
          env.DB.prepare('DELETE FROM account_sessions WHERE expires_at < ?').bind(Date.now())
        ]);
      }
    })());
  }
};
