# First-device test checklist

The automated tests validate the typing engine and writing request boundaries; a simulator launch verifies the companion app starts. They do not establish keyboard accuracy or signing compatibility on your iPhone.

- Install with the sideloader you already use; retain both app and extension. Enable the keyboard and switch to it in Practice, Notes and Messages.
- Type with Full Access off and airplane mode on. Try every letter, number and symbol page, shift/caps lock, delete/held delete, return and globe switching.
- Type `teh ` and `hellp ` in English lowercase. Check correction, tap the original suggestion to undo, then repeat and press delete to undo. Move the cursor elsewhere first and confirm old correction undo is no longer offered.
- Try Yoruba `ẹ`, `ọ`, `ṣ`, grave/acute tones using long presses; check insertion, cursor movement and deletion of composed characters. Try Pidgin words such as `dey`, `wetin`, `abeg` and verify no automatic English replacement.
- Swipe `hello`, `world`, `good`, `thank` and `keyboard`. Test selecting an alternative and moving the cursor before selecting one. Report incorrect words and missed gestures without including private message text.
- Drag the space bar, rotate the phone, try left/right layouts and all heights/themes. Test an iPad if available. Enable VoiceOver and confirm individual key names, next-keyboard control and suggestions remain usable.
- Pin selected text with Full Access off. With Full Access on, copy a sticker/GIF and paste it into Messages or another app that accepts that format.
- Clipboard: tap 📋 → Turn on clipboard history. Copy text in Safari, switch to Notes and open the keyboard: the "📋" chip should appear in the suggestion bar and the text at the top of 📋. Copy three items while the keyboard stays open (e.g. from a Messages thread) and confirm all three appear. Paste, pin, copy and delete cards; clear recent and confirm pins stay. Copy a password from Passwords or a password manager and confirm it is not recorded. Note whether iOS shows any "Allow Paste" prompt when the keyboard reads the clipboard.
- Confirm a password field uses Apple's keyboard. Confirm URL/email/number fields do not learn words or apply sentence suggestions/autocorrect.
- Open the voice editor, deny permissions, then retry with permissions allowed. Start/stop twice, leave the screen while recording and background the app; recording must stop. Check the next recording isn't stopped by callbacks from the previous one.
- Connect a test writing service. Check an invalid URL/token, network outage, missing Full Access, changed text selection and a successful rewrite. Only replace selected text after reviewing the returned result.
- With learning off, type new words and confirm they aren't retained. With learning on, try a harmless new word, then clear learned words. Clear clipboard and pinned text in each sandbox when using the default sideload build.

- Languages: hold the language key, add French, German, Russian and Arabic. Check each layout, long-press accents, suggestions, autocorrect undo and swipe. Turn multilingual typing on, type an English sentence with a Spanish word, and confirm the Spanish word isn't changed. Check Turkish capitals (i → İ) and that Arabic has no shift key.
- Feel: key pop-up preview on letters, numbers and symbols; key clicks with the phone's Keyboard Clicks setting on and off; hold comma and period for more punctuation. Try every theme including Auto in light and dark mode, accent colours and key outlines. On a Home-button iPhone confirm the 🌐 key shows; on Face ID iPhones it shouldn't.
- Emoji: browse every category, use search in English and another language, set a skin tone by holding 👋, and confirm Recents. Copy a sticker and paste it in Messages. In Messages, open the app drawer and confirm the WianTribe sticker pack appears.
- GIFs (with a service that has a GIPHY key): trending loads, search finds results, tapping copies a GIF that pastes in Messages. Without a service, the panel explains what's needed.
- Editing panel: arrows (hold to repeat), word and line jumps, copy/cut/paste and delete word in Notes.
- Handwriting: write several words in your language; check alternatives replace the word. Watch for the keyboard closing unexpectedly (a memory limit), and report the device model if it does.
- Translate & write on iOS 26: download a language in the app, then translate selected text and typed text in the keyboard, and try grammar and tone on a device with Apple Intelligence. Repeat with airplane mode on.
- App languages: switch the iPhone to Spanish, French, Portuguese, German and Arabic and check the app's text fits and reads naturally (Arabic right to left).

No real-device tests have been performed by the repository's CI. The initial 667-word dictionary and geometric swipe decoder need broader testing and tuning before a public release.
