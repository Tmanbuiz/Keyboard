#!/usr/bin/env python3
"""Recreate the original geometric app icon."""
import json
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
assets = ROOT / "Sources/App/Assets.xcassets"
icon_dir = assets / "AppIcon.appiconset"
accent_dir = assets / "AccentColor.colorset"
for directory in [assets, icon_dir, accent_dir]: directory.mkdir(parents=True, exist_ok=True)
icon = Image.new("RGB", (1024, 1024))
draw = ImageDraw.Draw(icon)
for y in range(1024):
    f = y / 1023
    draw.line((0, y, 1024, y), fill=(int(10 + f * 8), int(35 + f * 26), int(44 + f * 22)))
draw.rounded_rectangle((156, 271, 868, 765), radius=73, fill=(9, 30, 38), outline=(77, 218, 181), width=12)
for row, count in enumerate([8, 7, 6]):
    total = count * 67 + (count - 1) * 15
    x0 = (1024 - total) / 2
    for column in range(count):
        x = x0 + column * 82; y = 335 + row * 94
        color = (104, 239, 199) if row == 0 and column == 2 else (43, 98, 103)
        draw.rounded_rectangle((x, y, x + 67, y + 66), radius=13, fill=color)
draw.rounded_rectangle((329, 632, 695, 690), radius=15, fill=(104, 239, 199))
draw.line((333, 240, 406, 167, 480, 240), fill=(104, 239, 199), width=18)
draw.line((558, 240, 631, 167, 704, 240), fill=(104, 239, 199), width=18)
icon.save(icon_dir / "AppIcon.png")
metadata = {"info": {"author": "xcode", "version": 1}}
(assets / "Contents.json").write_text(json.dumps(metadata, indent=2) + "\n")
(icon_dir / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], **metadata}, indent=2) + "\n")
(accent_dir / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.408", "green": "0.937", "blue": "0.780", "alpha": "1.000"}}}], **metadata}, indent=2) + "\n")
print("Generated original app icon")
