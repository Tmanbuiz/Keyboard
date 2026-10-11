# WianTribe Personal clipboard build

This sideload variant adapts the monitoring mechanism in
[lonkelle/Clipper](https://github.com/lonkelle/Clipper), originally created by
Riley Testut under the Unlicense. It adds copy-change alerts to WianTribe's
existing keyboard and companion app.

## When you copy

1. Background location keeps the enabled companion process active.
2. Clipper's private Pasteboard-framework listener detects clipboard changes.
3. WianTribe presents **Clipboard changed** without including the copied text.
4. Touch and hold that notification. Its reader saves the **current** text or
   web link, then dismisses. A normal tap opens the app and attempts the same save.
5. The saved item appears in the keyboard's clipboard panel through a common
   App Group. A coordinated local file preserves simultaneous captures.

The notification reports a change; it does not snapshot each copy. Copying A,
then B before expanding the alert leaves B on the clipboard, so only B can be
saved. Each copy you want to keep needs the notification interaction. This
adapter uses WianTribe's text history; upstream Clipper also supports images.
Copies marked sensitive by their source are skipped.

## Install and enable

Use **WianTribeKeyboard-personal-clipboard.ipa** for the smallest bundle set:
the companion app, keyboard and required notification reader. The larger
**WianTribeKeyboard-personal.ipa** includes the Share extension and stickers.

Re-sign and retain the keyboard and notification-reader extensions. All three
processes need a working common App Group. The IPA retains the group entitlement
and Clipper's ALTAppGroups metadata for sideloaders that can remap it consistently.
Some signing tools/profiles cannot preserve this capability. Compiling a build
does not create a provisioned App Group.

The app uses bundle identifier **com.wiantribe.keyboard.personal** and appears as
**WianTribe Personal**. Its group before remapping is
**group.com.wiantribe.keyboard.personal**.

1. Enable WianTribe Personal in Settings → General → Keyboard → Keyboards.
2. Enable Allow Full Access for its clipboard controls.
3. Open the app → Tools → Clipboard → **Monitor copy changes**.
4. Allow notifications and set Location to **Always**. Set Paste from Other Apps
   to **Allow** if iOS blocks a save.
5. Return and tap **Check and resume monitoring**.
6. Copy harmless text in Safari, touch and hold the copy alert, then check 📋.

If shared storage is unavailable, fix signing first. The monitor does not report
successful sharing with an inaccessible keyboard. Basic typing and foreground
clipboard tools remain available.

## Runtime and privacy

This is an experimental personal build. Private APIs can change between iOS
versions. The listener checks the framework and selector, then reports unsupported
versions instead of crashing. A simulator cannot verify this mechanism; a real
iPhone must be tested.

iOS can still suspend or terminate the app, including after a force quit. A
renewed local notification asks you to reopen it when its heartbeat stops.
Continued monitoring depends on the process remaining active; it cannot be
promised through termination, reboot, permission changes or signing expiry.

Monitoring starts only when enabled and can be stopped from the same control.
Background location can affect battery use. Coordinates are not saved, logged
or transmitted. Copy-alert notifications contain no copied text. Saved history
stays locally and follows the keyboard's caps, expiry and pinning rules.

## Build

    bash Scripts/build_ipa.sh --personal-background-clipboard

The personal/background-clipboard branch selects this mode in CI. To generate
the project for local signing:

    python3 Scripts/generate_project.py --personal-background-clipboard

Sign the app, keyboard, reader and Share extension with compatible group-enabled
profiles. The private listener is compiled only into the companion app.
The standard generator invocation has no background-location mode or private
pasteboard listener.

## Upstream

- Repository: https://github.com/lonkelle/Clipper
- Source mechanisms: Clip/Pasteboard/PasteboardMonitor.swift,
  Clip/Pasteboard/LocationManager.swift, Clip/ApplicationMonitor.swift,
  ClipboardReader/NotificationViewController.swift
- License: ThirdParty/Clipper/UNLICENSE

This adapter preserves Clipper's detection → expanded notification → save flow
and adds start/stop, compatibility checks and coordinated text storage.
