# Upload to TestFlight without a Mac

The **Upload to TestFlight** workflow builds the App Store version (with the shared App Group), signs it with your Apple Developer account and uploads it to App Store Connect. You then install it on your iPhone with Apple's **TestFlight** app: no sideloading, no 7-day expiry.

## One-time setup

### 1. Register the IDs (developer.apple.com → Account → Certificates, Identifiers & Profiles → Identifiers)

1. **+ → App Groups** → description "WianTribe", identifier `group.com.wiantribe.keyboard`.
2. **+ → App IDs → App**, explicit Bundle IDs, one at a time:
   - `com.wiantribe.keyboard` (WianTribe Keyboard): tick **App Groups**
   - `com.wiantribe.keyboard.extension` (WianTribe Keyboard Extension): tick **App Groups**
   - `com.wiantribe.keyboard.share` (WianTribe Share): tick **App Groups**
   - `com.wiantribe.keyboard.stickers` (WianTribe Stickers)
3. Open each of the first three again → App Groups → **Configure** → select `group.com.wiantribe.keyboard` → Save.

### 2. Create the app (appstoreconnect.apple.com → Apps → + → New App)

Platform iOS · Name "WianTribe Keyboard" (add a word if it's taken) · Primary language English · Bundle ID `com.wiantribe.keyboard` · SKU `wiantribe-keyboard` · Full access.

### 3. Create an API key (App Store Connect → Users and Access → Integrations → App Store Connect API)

**Generate API Key** → name "GitHub" → role **Admin** (needed so the build can create its signing certificate) → Generate. Note the **Issuer ID** at the top and the key's **Key ID**, and **download the .p8 file**. Apple lets you download it only once; keep it somewhere safe and never share it.

### 4. Find your Team ID

developer.apple.com → Account → **Membership details** → Team ID (10 characters).

### 5. Add four GitHub secrets (github.com/Tmanbuiz/Keyboard → Settings → Secrets and variables → Actions → New repository secret)

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | your Team ID |
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | the whole contents of the .p8 file, including the BEGIN/END lines (open it in Notepad and copy everything) |

Secrets are encrypted, hidden in logs, and not visible to visitors even though the repository is public.

## Each time you want a new build

1. github.com/Tmanbuiz/Keyboard → **Actions** → **Upload to TestFlight** → **Run workflow**.
2. After about 15 minutes it finishes; Apple then processes the build for 10–30 minutes.
3. App Store Connect → your app → **TestFlight**: answer the export compliance question if asked (the app uses only standard encryption: choose "None of the algorithms mentioned"), then add yourself under **Internal Testing**.
4. Install **TestFlight** from the App Store on your iPhone, open the invite, and install WianTribe Keyboard. Delete any sideloaded copy first.

If a run fails, the error appears at the top of the run page. The most common causes are a missing App ID or App Group from step 1, or an API key without the Admin role.
