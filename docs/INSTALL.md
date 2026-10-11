# Install WianTribe Keyboard on your iPhone

## Using your existing sideloading tool

1. Open this repository's **Actions** tab and the latest successful **Build iPhone keyboard** run.
2. Download **WianTribeKeyboard-sideload** under Artifacts and extract the ZIP.
3. Import **WianTribeKeyboard-unsigned.ipa** into your existing sideloading tool. This file is unsigned; importing/re-signing is required before iOS can install it.
4. Keep the bundled **WianTribeKeyboardExtension.appex** and **WianTribeStickers.appex**. The tool must re-sign the app and both extensions with compatible profiles. If it offers to remove extensions, keep them.
5. Install, then open **WianTribe Keyboard** once.
6. Go to **iPhone Settings → General → Keyboard → Keyboards → Add New Keyboard → WianTribe Keyboard**.
7. Open a message or the app's Practice page. Hold **🌐** and choose **WianTribe Keyboard**.

Basic typing, suggestions, swipe, emoji, handwriting and on-device translation work without **Allow Full Access**. To use clipboard history, GIFs, copying stickers or your own online service, open the keyboard entry in Settings and enable **Allow Full Access**.

The default sideload build stores settings separately in the app and extension. **Tap ⚙︎ on the keyboard itself** to change its theme, height or typing behaviour, and **hold the language key** (top left) to choose your languages. For clipboard history, tap **📋 → Turn on clipboard history** in the keyboard. Text you copy anywhere then appears in 📋 the next time the keyboard opens.

## Using Xcode on a Mac

1. Open `WianTribeKeyboard.xcodeproj` with Xcode 16 or later.
2. Select your Apple signing team for **WianTribeKeyboard**, **WianTribeKeyboardExtension** and **WianTribeStickers** under Signing & Capabilities. If an App ID is unavailable, change the bundle IDs, keeping each extension ID prefixed with the app ID followed by a dot.
3. Connect your iPhone, enable Developer Mode if requested and select the iPhone as the run destination.
4. Run the **WianTribeKeyboard** scheme, then follow the keyboard enable steps above.

A free Personal Team's development provisioning expires after seven days and requires another build/install. Your existing sideloader's signing and refresh rules apply when using that tool. Paid membership does not automatically sign the CI-generated IPA.

## Translation, writing tools, GIFs and voice

On iOS 26, translation and rewriting run on the iPhone. Download translation languages once in the app under **Tools → Translation languages**; rewriting uses Apple Intelligence where it's available and supports your language.

Open the app's **Tools → Voice editor**, tap **Start recording**, allow microphone/speech permissions, stop, review and copy the transcript. Return to your message yourself and paste. Speech language availability depends on Apple's support on your device.

For older iPhones, languages Apple doesn't cover, and GIF search, you can connect your own HTTPS service. No service is configured by default. The project includes `Backend/worker.mjs` and setup instructions in `Backend/README.md`. Save the URL and private access token in **Tools → Writing assistant**. For use inside the keyboard, tap **Copy connection for keyboard**, then **✦ → Import service connection from clipboard**. For GIFs, add a GIPHY key to the service (see `Backend/README.md`). The local clipboard transfer expires after two minutes and requires Full Access in the keyboard. Never share that connection JSON; it contains your access token.

## If the keyboard doesn't appear

- Confirm the installer kept and signed the embedded keyboard extension.
- Open the containing app once, then revisit Add New Keyboard.
- Password fields use Apple's keyboard. Some apps disable all third-party keyboards; try the Practice page or Notes.
- If iOS falls back to Apple's keyboard repeatedly, record the app, device/iOS version and typing steps for a bug report. Keep message contents private.
