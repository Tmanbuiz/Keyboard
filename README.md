# WianTribe Keyboard for iPhone

A native iOS keyboard extension and companion app, inspired by useful Android keyboard features. This is an independent WianTribe project; it does not use Samsung code, branding or assets.

## Version 0.2

**Typing**
- 28 languages: English, Spanish, French, Portuguese, German, Italian, Dutch, Swedish, Norwegian, Danish, Finnish, Polish, Czech, Romanian, Hungarian, Turkish, Indonesian, Malay, Filipino, Russian, Ukrainian, Arabic, Hebrew, Yorùbá, Naija Pidgin, plus Swahili, Igbo and Hausa layouts. QWERTY, AZERTY, QWERTZ, Nordic, Turkish, Cyrillic, Arabic and Hebrew layouts with long-press accents.
- Dictionaries of up to 30,000 words per language, offline completion, Apple spelling suggestions, autocorrect with one-tap undo, and swipe typing in every language with a dictionary.
- Multilingual typing: mix same-alphabet languages in one message without switching. Defaults follow the phone's preferred languages.
- Opt-in on-device learning of your words and which word usually follows which.
- Key pop-up preview, key click sounds, haptics, hold-for-more punctuation, space-bar cursor, five heights, one-handed layouts, iPad sizing and larger key labels with Dynamic Type.

**Look**
- Eight themes including Auto (follows light/dark), seven accent colours and optional key outlines.

**Panels** (toolbar above the keys)
- ☺︎ Emoji, GIFs and stickers: the full Unicode 15.0 emoji set with categories, recents, skin tones and search in 16 languages; GIF search powered by GIPHY through your own service; 16 original stickers. An iMessage sticker pack ships with the app.
- 📋 Android-style clipboard: opt-in history of the last 40 texts copied while the keyboard is open, a "just copied" chip, pin/copy/delete, expiry after 1, 7 or 30 days. Password-manager copies are skipped.
- ⌶ Text editing: arrows, word and line jumps, copy, cut, paste and delete word, with hold-to-repeat.
- ✍︎ Handwriting: write with a finger; Apple's on-device Vision reads it, with alternatives to swap.
- ✦ Translate and write: translation with Apple's on-device Translate models and grammar/tone rewriting with Apple Intelligence on iOS 26, falling back to your own service.
- ⚙︎ Settings and the language picker (hold the language key).

**Companion app** in English, Spanish, French, Portuguese, German and Arabic: setup, practice, settings, languages, clipboard, translation language downloads, a writing assistant and a voice editor for every language Apple's speech recognition supports.

Known limits: iOS doesn't let keyboards use the microphone, watch the clipboard in the background, insert images directly or work in password fields. Chinese, Japanese, Korean and Indic scripts need dedicated input methods that aren't built yet. Dictionaries for Swahili, Igbo and Hausa aren't available yet, so those are layout-only. App translations should be reviewed by native speakers before release. See [App Store preparation](docs/APP-STORE.md) and the [privacy policy](docs/PRIVACY.md).

Acknowledgements: word frequencies from [wordfreq](https://github.com/rspeer/wordfreq) by Robyn Speer (data CC BY-SA 4.0); emoji data from [emojibase](https://emojibase.dev) (MIT); GIFs powered by GIPHY.

## Build and sideload

Requires iOS/iPadOS 17 or later. Open `WianTribeKeyboard.xcodeproj` in Xcode on a Mac, select your signing team for both targets and run on your iPhone. No third-party iOS packages are required.

GitHub Actions builds the app, keyboard and sticker pack, runs the typing/backend tests, launches the companion app in a simulator and uploads **WianTribeKeyboard-sideload**. Builds on `main` also publish a GitHub Release with **WianTribeKeyboard-…ipa** (app, keyboard and stickers) and **…-keyboard-only.ipa**, both ad-hoc signed and verified, plus checksums and installation instructions. A sideloading tool must re-sign them; keep and sign the extensions.

See [installation instructions](docs/INSTALL.md) and the [device test checklist](docs/DEVICE-TESTING.md).

```sh
swift test --jobs 2
node --test Backend/worker.test.mjs
bash Scripts/build_ipa.sh  # Mac/Xcode only
```

`Scripts/generate_project.py` reproduces the checked-in Xcode project using Python's standard library. `Scripts/build_languages.py` (needs `pip install wordfreq`), `Scripts/build_emoji.py` (needs `npm install emojibase-data`), `Scripts/generate_stickers.py` (needs Pillow) and `Scripts/build_strings.py` regenerate the committed language, emoji, sticker and translation data. `Scripts/generate_assets.py` recreates the original geometric icon/media and needs Pillow; the generated assets are already committed, so normal builds do not need Pillow.

## Sideloading and shared settings

The default build has no App Group entitlement, making signing simpler for Personal Teams and sideloaders. App and keyboard preferences/phrases are stored separately; **use ⚙︎ inside the keyboard to configure the keyboard**. Text copied in the app appears in the keyboard clipboard the next time the keyboard opens; the clipboard can also transfer an optional writing connection.

For a paid-team build with shared storage, register `group.com.wiantribe.keyboard` for both targets, then run `python3 Scripts/generate_project.py --shared-container` and sign both targets with profiles containing that group. The keyboard can read shared settings without Full Access; writing to shared storage requires Full Access. It always falls back to its private sandbox when the group is absent.

## Privacy and platform restrictions

Typing, swipe decoding, suggestions, emoji search, handwriting and (on iOS 26) translation and rewriting run locally. Full Access is optional for basic typing and is checked before clipboard, media, GIF and online actions. Local learning and clipboard history are off by default. iOS gives keyboards no background clipboard access, so history only records the latest copy each time the keyboard is shown, plus anything copied while it stays open. Writing requests send only explicitly selected/entered text over HTTPS, use an ephemeral URL session, reject redirects and keep the access token in Keychain. The backend template contains no request logging or stored text history.

Voice recording is confined to the companion app; it uses Apple's Speech framework and requests microphone/speech permissions only when starting a recording. On-device recognition is preferred when supported; otherwise Apple's service may process the audio. No microphone access is attempted in the extension.

Secure text fields and some phone-number fields use Apple's keyboard. Host apps can refuse third-party keyboards. The extension cannot launch the voice app or force image insertion. See Apple's [custom keyboard documentation](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface) and [open access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard).

Before an App Store release: finish real-device QA, configure production signing, decide whether to offer a writing service, verify that provider's privacy/data retention settings and publish a matching privacy policy and App Store privacy declaration. Nothing in this repository submits an app to App Store Connect or TestFlight.
