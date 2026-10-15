// Owner-only utility. ADMIN_TOKEN is read from the environment, never from command-line arguments.
import { writeFile } from 'node:fs/promises';
const [base, action, value, daily] = process.argv.slice(2);
if (!base || !['invite', 'list', 'revoke'].includes(action)) {
  console.error('Usage: node Backend/manage-users.mjs https://your-worker.workers.dev invite "Label" [dailyLimit]\n       ... list\n       ... revoke USER_ID'); process.exit(1);
}
const endpoint = new URL(base);
if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password) throw Error('Use your HTTPS Worker URL');
const secret = process.env.ADMIN_TOKEN;
if (!secret || secret.length < 32) throw Error('Set the owner ADMIN_TOKEN environment variable first');
let path = '/admin/users', method = 'GET', body;
if (action === 'invite') { method = 'POST'; body = JSON.stringify({ label: value, dailyLimit: Number(daily || 20) }); }
if (action === 'revoke') {
  if (!/^[a-zA-Z0-9-]{36}$/.test(value || '')) throw Error('Provide a user ID returned by list');
  path += '/' + value + '/revoke'; method = 'POST';
}
const response = await fetch(new URL(path, endpoint), { method, redirect: 'error', signal: AbortSignal.timeout(30000),
  headers: { Authorization: 'Bearer ' + secret, 'Content-Type': 'application/json' }, ...(body ? { body } : {}) });
if (!response.ok) throw Error('API returned HTTP ' + response.status);
const result = await response.json();
if (action === 'invite') {
  const file = 'user-connection-' + result.id + '.json';
  await writeFile(file, JSON.stringify(result.connection, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
  console.log('Created user ' + result.id + ' with ' + result.dailyLimit + ' daily attempts. Connection saved privately to ' + file);
} else console.log(JSON.stringify(result, null, 2));
