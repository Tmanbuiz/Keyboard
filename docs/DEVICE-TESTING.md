# First-device test checklist

The automated tests validate the typing engine and writing request boundaries; a simulator launch verifies the companion app starts. They do not establish keyboard accuracy or signing compatibility on your iPhone.

- Install with the sideloader you already use; retain both app and extension. Enable the keyboard and switch to it in Practice, Notes and Messages.
- Type with Full Access off and airplane mode on. Try every letter, number and symbol page, shift/caps lock, delete/held delete, return and globe switching.
- Type `teh ` and `hellp ` in English lowercase. Check correction, tap the original suggestion to undo, then repeat and press delete to undo. Move the cursor elsewhere first and confirm old correction undo is no longer offered.
- Try Yoruba `ẹ`, `ọ`, `ṣ`, grave/acute tones using long presses; check insertion, cursor movement and deletion of composed characters. Try Pidgin words such as `dey`, `wetin`, `abeg` and verify no automatic English replacement.
- Swipe `hello`, `world`, `good`, `thank` and `keyboard`. Test selecting an alternative and moving the cursor before selecting one. Report incorrect words and missed gestures without including private message text.
- Drag the space bar, rotate the phone, try left/right layouts and all heights/themes. Test an iPad if available. Enable VoiceOver and confirm individual key names, next-keyboard control and suggestions remain usable.
- Save selected text with Full Access off. With Full Access on, explicitly save clipboard text, pin/delete a phrase and copy a sticker/GIF. Paste media into Messages or another app that accepts that format.
- Confirm a password field uses Apple's keyboard. Confirm URL/email/number fields do not learn words or apply sentence suggestions/autocorrect.
- Open the voice editor, deny permissions, then retry with permissions allowed. Start/stop twice, leave the screen while recording and background the app; recording must stop. Check the next recording isn't stopped by callbacks from the previous one.
- Connect a test writing service. Check an invalid URL/token, network outage, missing Full Access, changed text selection and a successful rewrite. Only replace selected text after reviewing the returned result.
- With learning off, type new words and confirm they aren't retained. With learning on, try a harmless new word, then clear learned words. Clear saved phrases in each sandbox when using the default sideload build.

No real-device tests have been performed by the repository's CI. The initial 667-word dictionary and geometric swipe decoder need broader testing and tuning before a public release.
