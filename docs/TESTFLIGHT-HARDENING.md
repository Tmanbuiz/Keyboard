# TestFlight hardening and tester checklist

This change protects AI edits and clipboard deletion, introduces private typing, clipboard search/folders, editable AI results, a connection check, and a feedback report the tester chooses where to share.

## Behaviour

- Insert refuses an active selection. Replace checks that the original text still matches.
- Edit in the keyboard changes the end of the draft using its own keys; Done accepts and X cancels. The companion app offers a full TextEditor.
- Settings inside the keyboard offers Undo last AI replacement. It refuses if the replacement is not directly before the cursor or a selection is active. Undo is limited to the current keyboard session and available text context.
- Service disconnect publishes a revocation time in shared storage. The app and keyboard reject credentials saved before it. Sideload builds without an App Group must still disconnect separately.
- Credentials remain in each process's Keychain; copying/importing is still required. Saving updates an existing Keychain entry without deleting it first.
- Private typing pauses clipboard capture and word learning. Explicit AI requests and pinned phrases remain available. It does not clear existing data.
- Clipboard entries over 5,000 characters are rejected intact rather than shortened. Folder names are optional; the app offers folder filtering and both surfaces offer text search.
- Deleted clipboard IDs suppress stale cached copies. Clearing personal data also invalidates cached learning when shared storage is present.
- Test saved connection sends a fixed sentence and may consume provider quota. It does not verify the configured model identity.
- TestFlight upload now runs the Swift and backend suites before signing/uploading.

## Device verification before a wider release

1. In Notes, select text, run AI, then Insert: the selection must remain unchanged. Replace must update only the original selection.
2. Change the original text during a request: Replace must refuse a mismatch.
3. Edit a result, cancel once, then edit and accept. Confirm only the accepted result is used. Test Undo with an unchanged cursor and again after moving it.
4. Save/import a service connection. Check it works, disconnect in the app, and confirm the keyboard refuses its previous connection. Reconnect and verify again.
5. Copy a pinned and unpinned item, delete each in the app, disable Full Access, reopen the keyboard, and confirm neither returns. Copy the same text again and confirm it can be saved as a new item.
6. Test 5,000 and 5,001 character clipboard entries. Check that rejected content is never truncated or added.
7. Enable private typing in both Full Access states. Confirm capture/learning pauses and resumes when disabled. Verify Share and Shortcut feedback.
8. Test folder filtering, pinned filtering and searches with Yoruba diacritics, emoji and empty results.
9. Share tester feedback and inspect the report before sending. Ensure it contains only device/build information and the tester's description.
10. Repeat portrait/landscape, large text, VoiceOver, iPad, no network, and Full Access disabled. Watch for extension memory termination during AI/large media use.

Automated backend tests use fake model responses. They cannot prove live Groq availability or output quality. Device tests are still required for UIKit proxy/selection behaviour and keyboard memory limits.

## Emoji browser update

- Emoji 17.0 data from pinned `emojibase-data@17.0.0`, preserving Unicode order, names and multilingual search keywords. Its MIT license is included in Licenses.
- 1,914 base emoji, plus skin-tone and multi-person variants. Platform gates select Emoji 15.0 on iOS 17.0, 15.1 from 17.4, 16.0 from 18.4 and 17.0 from 26.4.
- Compact category rail, Smileys opening category, separate Emoji/GIF/Stickers tabs and a larger scrolling grid with adaptive columns and English accessibility names.
- Search submission shows a full results grid. Choosing any category clears the query. Empty Recents stays empty until an emoji is used.
- Hold a supported emoji for a scrollable skin-tone grid, including mixed-tone combinations. Single-person choices update the default tone; mixed-tone choices do not change that global setting.
- Test scrolling to the last flag, switching all categories, empty recents, search with no matches, mixed skin tones and rotation on iPhone/iPad. Emoji designs use the device's Apple emoji font.
