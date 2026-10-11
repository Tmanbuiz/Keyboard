# Install WianTribe Keyboard on your iPhone

## Using your existing sideloading tool

1. Open this repository's **Actions** tab and the latest successful **Build iPhone keyboard** run.
2. Download **WianTribeKeyboard-sideload** under Artifacts and extract the ZIP.
3. Import **WianTribeKeyboard-unsigned.ipa** into your existing sideloading tool. This file is unsigned; importing/re-signing is required before iOS can install it.
4. Keep the bundled **WianTribeKeyboardExtension.appex**. The tool must re-sign both the app and the extension with compatible profiles. If it offers to remove extensions, keep the keyboard extension.
5. Install, then open **WianTribe Keyboard** once.
6. Go to **iPhone Settings → General → Keyboard → Keyboards → Add New Keyboard → WianTribe Keyboard**.
7. Open a message or the app's Practice page. Hold **🌐** and choose **WianTribe Keyboard**.

Basic typing, suggestions, swipe input and emoji work without **Allow Full Access**. To save clipboard text, copy stickers/GIFs or use a connected writing service, open the keyboard entry in Settings and enable **Allow Full Access**.

The default sideload build stores settings separately in the app and extension. **Tap ⚙︎ on the keyboard itself** to change its theme, height, language or typing behaviour. For phrases, copy from the app, then tap **▣ → Save clipboard text** in the keyboard.

## Using Xcode on a Mac

1. Open `WianTribeKeyboard.xcodeproj` with Xcode 16 or later.
2. Select your Apple signing team for **WianTribeKeyboard** and **WianTribeKeyboardExtension** under Signing & Capabilities. If an App ID is unavailable, change both bundle IDs, keeping the extension ID prefixed with the app ID followed by a dot.
3. Connect your iPhone, enable Developer Mode if requested and select the iPhone as the run destination.
4. Run the **WianTribeKeyboard** scheme, then follow the keyboard enable steps above.

A free Personal Team's development provisioning expires after seven days and requires another build/install. Your existing sideloader's signing and refresh rules apply when using that tool. Paid membership does not automatically sign the CI-generated IPA.

## Voice and writing tools

Open the app's **Tools → Voice editor**, tap **Start recording**, allow microphone/speech permissions, stop, review and copy the transcript. Return to your message yourself and paste. Speech language availability depends on Apple's support on your device.

Grammar, professional/casual rewriting and translation need an HTTPS writing service. No service is configured by default. The project includes `Backend/worker.mjs` and setup instructions in `Backend/README.md`. Save the URL and private access token in **Tools → Writing assistant**. For use inside the keyboard, tap **Copy connection for keyboard**, then **✦ → Import writing connection from clipboard**. The local clipboard transfer expires after two minutes and requires Full Access in the keyboard. Never share that connection JSON; it contains your access token.

## If the keyboard doesn't appear

- Confirm the installer kept and signed the embedded keyboard extension.
- Open the containing app once, then revisit Add New Keyboard.
- Password fields use Apple's keyboard. Some apps disable all third-party keyboards; try the Practice page or Notes.
- If iOS falls back to Apple's keyboard repeatedly, record the app, device/iOS version and typing steps for a bug report. Keep message contents private.
