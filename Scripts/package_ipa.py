#!/usr/bin/env python3
import hashlib
import pathlib
import plistlib
import shutil
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
app = root / "build/device/Build/Products/Release-iphoneos/WianTribeKeyboard.app"
extension = app / "PlugIns/WianTribeKeyboardExtension.appex"
if not extension.is_dir(): raise SystemExit("Keyboard extension was not embedded")
app_info = plistlib.loads((app / "Info.plist").read_bytes())
extension_info = plistlib.loads((extension / "Info.plist").read_bytes())
assert extension_info["CFBundleIdentifier"].startswith(app_info["CFBundleIdentifier"] + ".")
assert extension_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert extension_info["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"] is True
stickers = app / "PlugIns/WianTribeStickers.appex"
if not stickers.is_dir(): raise SystemExit("iMessage sticker pack was not embedded")
assert plistlib.loads((stickers / "Info.plist").read_bytes())["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.message-payload-provider"
for container in [app, extension]:
    assert (container / "PrivacyInfo.xcprivacy").exists()
    assert (container / container.name.rsplit(".", 1)[0]).exists()
output = root / "build/output"
output.mkdir(parents=True, exist_ok=True)
ipa = output / "WianTribeKeyboard-unsigned.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob("*")):
        if file.is_file(): archive.write(file, "Payload/" + str(file.relative_to(app.parent)))
(output / "SHA256SUMS.txt").write_text(hashlib.sha256(ipa.read_bytes()).hexdigest() + "  " + ipa.name + "\n")
shutil.copyfile(root / "docs/INSTALL.md", output / "INSTALL.md")
print("Packaged app + keyboard extension + iMessage stickers. This IPA is unsigned and must be re-signed before installation.")
