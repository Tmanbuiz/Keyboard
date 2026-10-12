#!/usr/bin/env python3
"""Give the isolated simulator app separate Keychain identities for UI checks."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Info.plist").read_bytes())
if "iPhoneSimulator" not in info.get("CFBundleSupportedPlatforms", []):
    raise SystemExit("Simulator signing cannot be used on a device build")

team = "WIANTRIBE0"  # A CI-only simulator identity, not an Apple signing account.
bundles = sorted(app.rglob("*.appex"), key=lambda path: len(path.parts), reverse=True) + [app]
with tempfile.TemporaryDirectory(prefix="wiantribe-simulator-signing-") as folder:
    for index, bundle in enumerate(bundles):
        bundle_info = plistlib.loads((bundle / "Info.plist").read_bytes())
        identity = team + "." + bundle_info["CFBundleIdentifier"]
        entitlements = {
            "application-identifier": identity,
            "com.apple.developer.team-identifier": team,
            "keychain-access-groups": [identity],
            "get-task-allow": True,
        }
        path = pathlib.Path(folder) / f"{index}.plist"
        path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                        "--entitlements", str(path), str(bundle)], check=True)
        subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Simulator app and extensions signed with separate test Keychains.", flush=True)
