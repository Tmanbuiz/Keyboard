# Built-in AI sign-in and TestFlight

Users open WianTribe → Tools → AI account → Continue with Apple, then enable Allow Full Access for the keyboard. No imported connection or provider/admin key is needed. Sessions are stored in the shared App Group Keychain, scoped to this device and accessible only while unlocked. Existing invitation credentials remain supported.

## Owner deployment

The root Wrangler configuration deploys the `keyboard` Worker to the existing account and D1 database. Keep the existing `PROVIDER_API_KEY` and `ADMIN_TOKEN` secrets. Signing in checks Apple's public signing keys. Deleting an account also needs a Sign in with Apple private key, stored as three Worker secrets: `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the whole `.p8` file). `APPLE_CLIENT_ID` must equal the signed app bundle identifier (`com.wiantribe.keyboard`). New tables are initialized idempotently; migration 0002 also documents the schema. The original clients schema must already exist.

Enable **Sign in with Apple** for the main app identifier in Apple Developer → Certificates, Identifiers & Profiles → Identifiers. The app needs this capability plus its existing App Group. Only the companion app gets the Apple sign-in entitlement; all entitled app/keyboard components share the App Group. The TestFlight workflow generates those entitlements and lets Xcode refresh provisioning profiles.

After the feature branch checks pass, merge to main so Cloudflare’s connected build deploys the backend. Confirm `/health` returns `ready` and `apple-sign-in`. Run **Upload to TestFlight** manually or move `testflight/release` to the verified release commit. Upload success does not mean Apple has finished processing or enabled the build for external testers.

## Limits and retention

Default allowance: 20 requests per account per UTC day, 500 across all accounts; attempts count. Sessions last 30 days with at most five active sessions per account. Logout revokes one session. Deleting the account revokes every session; a stable pseudonymous usage bucket prevents deletion from resetting the daily quota. The bucket expires after 30 days. Submitted writing and results are not stored by the Worker. Provider terms still apply.

App Store Connect privacy answers must reflect account identifiers and usage counts, linked to the account and used for app functionality. The generated privacy manifest declares these categories; it does not update App Store Connect answers automatically.

## Device acceptance checks

Install the processed TestFlight build, sign in, open the keyboard in another app, and use grammar/translation without copying credentials. Check Full Access off/on, quota display, expiry/sign-in again, sign-out, deleting the account, Apple credential revocation, and a second device. Verify the Cloudflare provider key is configured with a successful real writing request.

## Removing WianTribe from Sign in with Apple on deletion

Delete AI account opens Apple's sign-in sheet so the person confirms it's them. The app sends Apple's one-time authorization code with the deletion request. The Worker exchanges it with Apple using the private key above, revokes the grant (so WianTribe leaves the person's Sign in with Apple list), then deletes the account and every session. The code and the tokens it returns are used once and never stored. The reply says `appleRevoked: true` when Apple confirmed the removal; the app tells the person either way.

If Apple can't confirm (no connection, for example), the app offers "Delete without Apple's confirmation". The account is still deleted, and the app tells the person to remove WianTribe themselves with Manage Sign in with Apple.

Status: the three secrets are set in Cloudflare. In November 2026, deleting a test account on an iPhone removed WianTribe from that Apple Account's Sign in with Apple list.

**The Apple key.** Created in Apple Developer → Certificates, Identifiers & Profiles → Keys, with Sign in with Apple enabled for the app's primary App ID. `APPLE_KEY_ID` is the key's 10-character ID and `APPLE_TEAM_ID` is the team ID shown at the top right of the developer site. Apple lets you download the `.p8` file only once: keep it in a password manager, never in this repository or a chat. If it is lost or exposed, revoke the key in Apple Developer, create a new one and update the three secrets in Cloudflare (in the dashboard, or with `npx wrangler secret put <NAME>`).
