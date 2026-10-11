# WianTribe Keyboard for iPhone

A native iOS keyboard extension and companion app, inspired by useful Android keyboard features. This is an independent WianTribe project; it does not use Samsung code, branding or assets.

## Version 0.1

- QWERTY keyboard, optional number row, numbers/symbol pages, caps lock, repeat delete and double-space period.
- English, Yoruba accents/tones and Nigerian Pidgin presets, with an original 667-entry starter dictionary.
- Offline completion, supplementary Apple spelling suggestions and conservative English autocorrect with immediate undo.
- An initial offline glide/swipe decoder, alternatives and space-bar cursor movement.
- Four themes, three keyboard heights and left/right one-handed layouts.
- Emoji, two original stickers and two original animated GIFs. Media is copied; the user pastes it in a compatible host app.
- Android-style clipboard (📋): opt-in history of the last 40 texts copied while the keyboard is open, a "just copied" suggestion chip, tap to paste anywhere, pin/copy/delete, and expiry after 1, 7 or 30 days. Pinned items never expire. Password-manager copies are skipped. Opt-in local word-count learning. No keystroke history.
- Companion app with setup instructions, a typing practice field, settings and a voice transcription editor.
- Optional grammar, tone and translation client in the app and keyboard. A private Cloudflare Workers backend template is included; no service or API credentials are provisioned by default.

This is a first testing build, not Samsung feature parity. Swipe accuracy uses a small dictionary and needs real-device tuning. English corrections are deliberately limited; Yoruba and Pidgin are not silently autocorrected. Handwriting input, a large searchable GIF catalogue, full multilingual prediction and production-grade translation require further work.

## Build and sideload

Requires iOS/iPadOS 17 or later. Open `WianTribeKeyboard.xcodeproj` in Xcode on a Mac, select your signing team for both targets and run on your iPhone. No third-party iOS packages are required.

GitHub Actions builds both targets, runs the typing/backend tests, launches the companion app in a simulator and uploads **WianTribeKeyboard-sideload**. That artifact contains **WianTribeKeyboard-unsigned.ipa**, its checksum, installation instructions and a simulator screenshot. The IPA must be re-signed by a sideloading tool before installation. Both the app and keyboard extension must be kept and signed.

See [installation instructions](docs/INSTALL.md) and the [device test checklist](docs/DEVICE-TESTING.md).

```sh
swift test --jobs 2
node --test Backend/worker.test.mjs
bash Scripts/build_ipa.sh  # Mac/Xcode only
```

`Scripts/generate_project.py` reproduces the checked-in Xcode project using Python's standard library. `Scripts/generate_assets.py` recreates the original geometric icon/media and needs Pillow; the generated assets are already committed, so normal builds do not need Pillow.

## Sideloading and shared settings

The default build has no App Group entitlement, making signing simpler for Personal Teams and sideloaders. App and keyboard preferences/phrases are stored separately; **use ⚙︎ inside the keyboard to configure the keyboard**. Text copied in the app appears in the keyboard clipboard the next time the keyboard opens; the clipboard can also transfer an optional writing connection.

For a paid-team build with shared storage, register `group.com.wiantribe.keyboard` for both targets, then run `python3 Scripts/generate_project.py --shared-container` and sign both targets with profiles containing that group. The keyboard can read shared settings without Full Access; writing to shared storage requires Full Access. It always falls back to its private sandbox when the group is absent.

## Privacy and platform restrictions

Typing, swipe decoding and suggestions run locally. Full Access is optional for basic typing and is checked before clipboard, media and online actions. Local learning and clipboard history are off by default. iOS gives keyboards no background clipboard access, so history only records the latest copy each time the keyboard is shown, plus anything copied while it stays open. Writing requests send only explicitly selected/entered text over HTTPS, use an ephemeral URL session, reject redirects and keep the access token in Keychain. The backend template contains no request logging or stored text history.

Voice recording is confined to the companion app; it uses Apple's Speech framework and requests microphone/speech permissions only when starting a recording. On-device recognition is preferred when supported; otherwise Apple's service may process the audio. No microphone access is attempted in the extension.

Secure text fields and some phone-number fields use Apple's keyboard. Host apps can refuse third-party keyboards. The extension cannot launch the voice app or force image insertion. See Apple's [custom keyboard documentation](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface) and [open access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard).

Before an App Store release: finish real-device QA, configure production signing, decide whether to offer a writing service, verify that provider's privacy/data retention settings and publish a matching privacy policy and App Store privacy declaration. Nothing in this repository submits an app to App Store Connect or TestFlight.
