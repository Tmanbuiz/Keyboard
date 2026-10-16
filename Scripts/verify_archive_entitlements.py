#!/usr/bin/env python3
"""Fail before distribution if archiving loses Apple sign-in or shared-container access."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]) / "Products/Applications/WianTribeKeyboard.app"
checks = [
    (app, "com.wiantribe.keyboard", True, True),
    (app / "PlugIns/WianTribeKeyboardExtension.appex", "com.wiantribe.keyboard.extension", True, False),
    (app / "PlugIns/WianTribeShare.appex", "com.wiantribe.keyboard.share", True, False),
    (app / "PlugIns/WianTribeStickers.appex", "com.wiantribe.keyboard.stickers", False, False),
]
for bundle, identifier, shared, apple in checks:
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != identifier:
        raise SystemExit(f"Unexpected bundle identifier: {bundle.name}")
    result = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(bundle)], capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
    if shared and "group.com.wiantribe.keyboard" not in entitlements.get("com.apple.security.application-groups", []):
        raise SystemExit(f"App Group missing from archived {bundle.name}")
    if apple and "Default" not in entitlements.get("com.apple.developer.applesignin", []):
        raise SystemExit("Sign in with Apple missing from archived companion app")
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
print("Archived app identifiers, signatures, App Groups and Apple sign-in verified")
