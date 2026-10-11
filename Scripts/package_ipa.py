#!/usr/bin/env python3
"""Package two sideloading IPAs from the Release build (macOS only).

- WianTribeKeyboard.ipa: app + keyboard + iMessage sticker pack + Share extension.
- WianTribeKeyboard-keyboard-only.ipa: app + keyboard, for free Apple IDs that are short of App IDs.

Every bundle is ad-hoc signed from the inside out and verified, so sideloading tools start from a
valid, consistent signature when they re-sign. An unsigned or half-signed extension can be rejected
by iOS at launch ("CODESIGNING / Invalid Page"), which makes iOS fall back to Apple's keyboard.
"""
import hashlib
import pathlib
import plistlib
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
built = root / "build/device/Build/Products/Release-iphoneos/WianTribeKeyboard.app"
output = root / "build/output"
staging = root / "build/staging"


def run(*args):
    subprocess.run(args, check=True)


def check(app, with_stickers):
    extension = app / "PlugIns/WianTribeKeyboardExtension.appex"
    if not extension.is_dir(): raise SystemExit("Keyboard extension was not embedded")
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    extension_info = plistlib.loads((extension / "Info.plist").read_bytes())
    assert extension_info["CFBundleIdentifier"].startswith(app_info["CFBundleIdentifier"] + ".")
    assert extension_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
    assert extension_info["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"] is True
    stickers = app / "PlugIns/WianTribeStickers.appex"
    share = app / "PlugIns/WianTribeShare.appex"
    assert stickers.is_dir() == with_stickers and share.is_dir() == with_stickers, "unexpected extension set"
    if with_stickers:
        assert plistlib.loads((stickers / "Info.plist").read_bytes())["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.message-payload-provider"
        assert plistlib.loads((share / "Info.plist").read_bytes())["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.share-services"
    for container in [app, extension]:
        assert (container / "PrivacyInfo.xcprivacy").exists()
        assert (container / container.name.rsplit(".", 1)[0]).exists()


def sign(app):
    # Inside out: extensions first, then the app that contains them.
    for bundle in sorted((app / "PlugIns").glob("*.appex")):
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(bundle))
    run("codesign", "--force", "--sign", "-", "--timestamp=none", str(app))
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))


def package(name, with_stickers):
    folder = staging / name
    if folder.exists(): shutil.rmtree(folder)
    payload = folder / "Payload"
    payload.mkdir(parents=True)
    app = payload / built.name
    shutil.copytree(built, app, symlinks=True)
    if not with_stickers:
        shutil.rmtree(app / "PlugIns/WianTribeStickers.appex")
        shutil.rmtree(app / "PlugIns/WianTribeShare.appex")
    check(app, with_stickers)
    sign(app)
    ipa = output / f"{name}.ipa"
    if ipa.exists(): ipa.unlink()
    # zip keeps file modes and symlinks, which some installers check.
    subprocess.run(["zip", "-qry", "-X", str(ipa), "Payload"], cwd=folder, check=True)
    return ipa


output.mkdir(parents=True, exist_ok=True)
ipas = [package("WianTribeKeyboard", True), package("WianTribeKeyboard-keyboard-only", False)]
(output / "SHA256SUMS.txt").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in ipas))
shutil.copyfile(root / "docs/INSTALL.md", output / "INSTALL.md")
print("Packaged and ad-hoc signed: " + ", ".join(p.name for p in ipas) + ". Re-sign with your sideloading tool before installing.")
