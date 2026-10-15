# Built-in AI sign-in and TestFlight

Users open WianTribe → Tools → AI account → Continue with Apple, then enable Allow Full Access for the keyboard. No imported connection or provider/admin key is needed. Sessions are stored in the shared App Group Keychain, scoped to this device and accessible only while unlocked. Existing invitation credentials remain supported.

## Owner deployment

The root Wrangler configuration deploys the `keyboard` Worker to the existing account and D1 database. Keep the existing `PROVIDER_API_KEY` and `ADMIN_TOKEN` secrets. Apple sign-in uses public Apple signing keys, not an Apple private key. `APPLE_CLIENT_ID` must equal the signed app bundle identifier (`com.wiantribe.keyboard`). New tables are initialized idempotently; migration 0002 also documents the schema. The original clients schema must already exist.

Enable **Sign in with Apple** for the main app identifier in Apple Developer → Certificates, Identifiers & Profiles → Identifiers. The app needs this capability plus its existing App Group. Only the companion app gets the Apple sign-in entitlement; all entitled app/keyboard components share the App Group. The TestFlight workflow generates those entitlements and lets Xcode refresh provisioning profiles.

After the feature branch checks pass, merge to main so Cloudflare’s connected build deploys the backend. Confirm `/health` returns `ready` and `apple-sign-in`. Run **Upload to TestFlight** manually or move `testflight/release` to the verified release commit. Upload success does not mean Apple has finished processing or enabled the build for external testers.

## Limits and retention

Default allowance: 20 requests per account per UTC day, 500 across all accounts; attempts count. Sessions last 30 days with at most five active sessions per account. Logout revokes one session. Deleting the account revokes every session; a stable pseudonymous usage bucket prevents deletion from resetting the daily quota. The bucket expires after 30 days. Submitted writing and results are not stored by the Worker. Provider terms still apply.

App Store Connect privacy answers must reflect account identifiers and usage counts, linked to the account and used for app functionality. The generated privacy manifest declares these categories; it does not update App Store Connect answers automatically.

## Device acceptance checks

Install the processed TestFlight build, sign in, open the keyboard in another app, and use grammar/translation without copying credentials. Check Full Access off/on, quota display, expiry/sign-in again, sign-out, deleting the account, Apple credential revocation, and a second device. Verify the Cloudflare provider key is configured with a successful real writing request.

## Apple grant revocation limitation

Account deletion removes the WianTribe account and backend sessions. This implementation does not collect an Apple authorization code or refresh token, so it cannot automatically revoke Apple's own authorization grant. The app explains how to remove that grant in Apple Account settings. Before a public App Store release, complete Apple's server token-exchange/revocation lifecycle and applicable account-deletion requirements; do not present manual grant removal as automatic revocation.
