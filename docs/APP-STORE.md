# App Store preparation

What's ready in this repository, and what only you can do.

## Only you can do these

1. **Join the Apple Developer Program** ($99 USD/year) as an individual or as WianTribe Inc. (organisation enrolment needs a D-U-N-S number).
2. **Register bundle IDs** `com.wiantribe.keyboard`, `com.wiantribe.keyboard.extension`, `com.wiantribe.keyboard.share` and `com.wiantribe.keyboard.stickers`. Add the App Group `group.com.wiantribe.keyboard` to the app, keyboard and share IDs, then run `python3 Scripts/generate_project.py --shared-container` before archiving. The App Group is required for the App Store build: it is how items saved by the Share menu, the Shortcut and the app reach the keyboard.
3. **Test on real iPhones** using [DEVICE-TESTING.md](DEVICE-TESTING.md), ideally one older model and one with Apple Intelligence, plus an iPad.
4. **Publish the privacy policy** ([PRIVACY.md](PRIVACY.md)) at a public URL, for example wiantribe.com/keyboard/privacy, after filling in the date and support email.
5. **Have native speakers review** the app translations (Spanish, French, Portuguese, German, Arabic) in `Scripts/data/app-translations.json`, then run `python3 Scripts/build_strings.py`.
6. **Create the app in App Store Connect**, upload a build from Xcode (Product → Archive), add screenshots and submit.
7. **Decide pricing.** Free with optional paid themes or languages needs StoreKit work that isn't built yet.

## App Store privacy answers ("App Privacy")

- **Data collection:** "No, we do not collect data from this app." WianTribe receives nothing. Text sent to a service the user connects goes to their own server, not to WianTribe.
- **Tracking:** No.
- The included `PrivacyInfo.xcprivacy` declares no collected data and the UserDefaults reason codes.

## Review notes (paste into App Review Information)

> WianTribe Keyboard is a custom keyboard. To try it: open the app, follow Home → "Add WianTribe Keyboard", then switch to it with the globe key in the Practice tab.
>
> Full Access is optional. Without it, typing, suggestions, swipe, emoji, handwriting and on-device translation all work. Full Access is used only for clipboard history (off by default), copying stickers/GIFs, haptics and an optional user-supplied HTTPS service. The keyboard does not use the microphone; voice transcription happens only in the containing app.
>
> Clipboard: there is no background monitoring. The keyboard reads the clipboard only while it is on screen and the user has turned on clipboard history (off by default); items can also be saved explicitly through the "Save to WianTribe" share extension, the "Save Clipboard to WianTribe" App Intent (Shortcuts, Siri, Back Tap, Action button) or the system Paste button in the app. Everything stays on device in the App Group.
>
> GIF search and server-based writing tools require the user's own service and are not configured in this build; the GIF tab explains this. No account or login is needed.

Relevant guidelines: 4.4.1 (keyboard extensions), 5.1.1 (privacy). The keyboard provides a globe key when iOS requires one, works without network access and without Full Access, and offers number and decimal input through iOS's own pads.

## Listing text

**Name:** WianTribe Keyboard
**Subtitle (30 max):** Type in 28 languages, privately

**Promotional text (170 max):**
Mix languages in one message, search every emoji, keep a clipboard of what you copy, and translate on your iPhone. Your typing never leaves your device.

**Description:**
WianTribe Keyboard brings the best of Android keyboards to iPhone, built around privacy.

TYPE THE WAY YOU TALK
• 28 languages with their own layouts, from English, Spanish and French to Arabic, Russian, Turkish, Yorùbá and Naija Pidgin
• Multilingual typing: mix languages in one message without switching
• Smart suggestions, autocorrect with one-tap undo, and swipe typing
• Learns your words on your device, only if you want it to

MORE THAN A KEYBOARD
• Clipboard history: see what you copied and paste it anywhere
• Save any copy with a double-tap on the back of your iPhone, or Share → Save to WianTribe
• Every emoji, with search in 16 languages and skin tones
• Original stickers, including an iMessage sticker pack
• Text editing panel with arrows, word jumps, copy, cut and paste
• Handwriting: write with your finger
• Translate and rewrite on your iPhone with Apple's on-device models (iOS 26)

MAKE IT YOURS
• Eight themes including automatic light and dark, accent colours, key outlines
• Five heights, one-handed mode, key sounds, key pop-ups and haptics

PRIVATE BY DESIGN
• No analytics, no ads, no tracking, no account
• Typing, suggestions and swipe happen on your iPhone
• Full Access is optional: only clipboard, GIFs, stickers and haptics need it

**Keywords (100 max):** keyboard,multilingual,swipe,emoji,clipboard,translate,themes,stickers,handwriting,yoruba,pidgin

**What's New (0.2.0):** First public release.

**Category:** Utilities (secondary: Productivity). **Age rating:** 4+ answers throughout, except "Unrestricted web access: No". GIF search is rated PG-13 at the source and is off unless the user connects a service.

## Screenshots to capture (6.9" and 6.5" iPhone, 13" iPad)

1. Typing with suggestions in the Auto dark theme
2. Language picker showing several languages
3. Emoji panel with search
4. Clipboard history
5. Translate result in the ✦ panel
6. Themes and accent colours
7. Handwriting panel
8. iMessage stickers in Messages
