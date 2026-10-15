> Current TestFlight users sign in with Apple directly in the app. See [built-in sign-in setup](../docs/APPLE-SIGNIN.md). Invitation commands below remain available for owner-managed legacy clients.

# Cloudflare + Groq: invited-user rollout

This is an **invite-only user API**, compatible with the keyboard's existing HTTPS connection format. It does not provide open registration, payments or automatic account sign-in. Each invited user gets a distinct revocable connection. No Groq key or owner admin token is included in the app or sent to users.

## What is already prepared

- `public-worker.mjs` wraps the existing writing/GIF service with per-user authentication, D1 quota reservation and an owner-only user-management API.
- Tokens are generated from 32 random bytes. Only their SHA-256 hashes are stored.
- Default allowance: 20 attempts per user/day, adjustable from 1 to 1,000 at invitation time. Global default: 500 attempts/day across every user. Both writing and GIF requests count.
- One atomic SQLite statement enforces user and global limits together. Database errors fail closed. Quotas reset at midnight UTC.
- Authenticated attempts count even if text validation or the provider subsequently fails. The app's connection check also counts.
- Edge rate limits provide additional per-user and per-IP protection. They are eventually consistent; the D1 daily quota is the durable control for model calls.
- Input is limited by the existing writing contract to 3,000 Unicode code points and model output to 2,048 tokens. Quotas cap attempts, **not a fixed dollar amount**. Cloudflare requests/database operations and Groq usage may still cost money.
- Usage records contain only a random client ID, day, timestamp and event ID. No submitted text or model output is stored by this code. Usage records expire after 30 days; labels and token hashes stay until the owner removes the account from D1. Provider data policies still apply.

## 1. Create the database in Cloudflare

Open **Storage & databases → D1 → Create database**. Name it `wiantribe-keyboard-users` and copy its database ID. It is an identifier, not a password.

## 2. Choose a deployment path

### GitHub Actions (prepared workflow)

In this repository's **Settings → Secrets and variables → Actions**, add:

| GitHub secret | Value |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | A scoped deployment token with Workers Scripts Edit and D1 Edit for that account |

Do not use your Global API Key. Your **Groq key is not needed in GitHub**.

Open **Actions → Deploy Cloudflare user API → Run workflow → main**. Paste the D1 database ID into the input. The workflow runs tests, applies the migration and deploys `wiantribe-keyboard-api`. This workflow does not run automatically on source pushes.

### Cloudflare's existing GitHub integration

Create a **Worker**, not a Pages site, from `Tmanbuiz/Keyboard`.

1. Replace `REPLACE_WITH_D1_DATABASE_ID` in `Backend/wrangler.public.jsonc` with your D1 database ID and commit it.
2. Set the root directory to `Backend`.
3. Use the deploy command `npx wrangler@4.36.0 deploy --config wrangler.public.jsonc`.
4. Before inviting anyone, apply `Backend/migrations/0001_invited_users.sql` through D1's SQL console, or run `npx wrangler@4.36.0 d1 migrations apply DB --remote --config wrangler.public.jsonc` from `Backend` with an authenticated CLI.
5. Use the public config explicitly. The original `wrangler.jsonc` still deploys the separate private-testing service.

## 3. Add the two runtime secrets in Cloudflare

Open **Workers & Pages → wiantribe-keyboard-api → Settings → Variables and Secrets**. Add these as **Secrets**:

| Cloudflare runtime secret | Value |
| --- | --- |
| `PROVIDER_API_KEY` | Your Groq API key |
| `ADMIN_TOKEN` | A separate random owner-only secret of at least 32 characters |

Generate the admin secret locally with `node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))"`. Keep it in your password manager. Never give it to app users. Save/deploy the Worker after adding secrets.

Optional: add `GIPHY_API_KEY` as a Secret to enable GIF search. Otherwise writing works but GIF requests return a clear unavailable response.

`MODEL` defaults to `llama-3.3-70b-versatile`. Check that your Groq account can use it; change the Cloudflare variable to another supported chat-completions model if needed. `GLOBAL_DAILY_LIMIT` defaults to `500`. Review provider usage/billing settings before inviting users.

## 4. Check readiness

Open `https://YOUR-WORKER.workers.dev/health`. It must return `{"status":"ready","access":"invite-only"}`. This verifies required configuration and the database schema, **not live Groq inference**.

## 5. Create your first individual connection

On a machine with Node 24, open the repository directory. Enter the same owner admin secret without putting it into shell history:

```bash
read -rs -p "Owner admin secret: " ADMIN_TOKEN
export ADMIN_TOKEN
node Backend/manage-users.mjs https://YOUR-WORKER.workers.dev invite "Tolu" 20
unset ADMIN_TOKEN
```

The utility saves `user-connection-USER_ID.json` with owner-only file permissions and does not print the user's token. Keep that file private. It contains only that user's endpoint and token, never your Groq key.

Use `list` in place of `invite "Tolu" 20` to list up to 200 recent users; use `revoke USER_ID` to stop a connection. The same admin environment variable is required. Revocation prevents subsequent requests; it cannot cancel a request already sent to Groq.

## 6. Connect the iPhone and test

1. Copy the entire contents of your generated connection JSON.
2. In the WianTribe app, open **Tools → Writing assistant** and use its Paste button to import the connection.
3. Tap **Test saved connection**. This makes a real Groq request and consumes one allowance attempt.
4. Tap **Copy connection for keyboard**.
5. In the keyboard, open **AI tools → Import service connection from clipboard** with Full Access enabled.
6. Select **My own AI service only** if you want all writing and translation routed through Groq.
7. Test grammar and translation before sharing individual connections with invited testers. Each tester gets their own generated file. Do not share one user's token among everyone.

The app UI changes require a new TestFlight upload. The backend alone cannot update an already installed build. Existing builds can still connect by entering the endpoint/token fields manually and importing the copied connection in the keyboard.

## Before an unrestricted public launch

This first rollout intentionally requires owner-issued invitations. Self-service registration, automatic sign-in, abuse verification, account deletion UI and any paid plan need their own implementation before advertising open registration. App Store privacy disclosures and the privacy policy must describe the deployed Cloudflare/Groq processing and usage metadata.

Official references: [Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [D1 migrations](https://developers.cloudflare.com/d1/reference/migrations/), [D1 sessions](https://developers.cloudflare.com/d1/worker-api/d1-database/), [Groq models](https://console.groq.com/docs/models).
