#!/usr/bin/env python3
"""Recreate the original geometric app icon and four original media assets."""
import json
import math
import pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
assets = ROOT / "Sources/App/Assets.xcassets"
icon_dir = assets / "AppIcon.appiconset"
accent_dir = assets / "AccentColor.colorset"
media = ROOT / "Sources/Keyboard/Media"
for directory in [assets, icon_dir, accent_dir, media]: directory.mkdir(parents=True, exist_ok=True)
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
font_paths = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]
font_path = next((p for p in font_paths if pathlib.Path(p).exists()), None)
def font(size): return ImageFont.truetype(font_path, size) if font_path else ImageFont.load_default()
def sticker(label, color, wobble=0):
    image = Image.new("RGBA", (360, 240), (0, 0, 0, 0)); d = ImageDraw.Draw(image)
    d.rounded_rectangle((12, 22 + wobble, 348, 216 + wobble), radius=50, fill=color, outline=(255, 255, 255), width=6)
    bounds = d.textbbox((0, 0), label, font=font(36))
    d.text(((360 - (bounds[2] - bounds[0])) / 2, 83 + wobble), label, font=font(36), fill=(7, 36, 41))
    d.ellipse((95, 149 + wobble, 112, 166 + wobble), fill=(7, 36, 41)); d.ellipse((245, 149 + wobble, 262, 166 + wobble), fill=(7, 36, 41))
    d.arc((145, 144 + wobble, 213, 187 + wobble), 0, 180, fill=(7, 36, 41), width=5)
    return image
sticker("HELLO!", (104, 239, 199)).save(media / "hello.png")
sticker("THANK YOU", (249, 205, 119)).save(media / "thanks.png")
for name, label, color in [("celebrate", "HOORAY!", (104, 239, 199)), ("love", "LOVE YOU", (255, 166, 192))]:
    frames = []
    for index in range(16):
        image = Image.new("RGB", (360, 240), (14, 43, 51))
        foreground = sticker(label, color, int(math.sin(index / 16 * 2 * math.pi) * 7))
        image.paste(foreground, (0, 0), foreground)
        frames.append(image)
    frames[0].save(media / (name + ".gif"), save_all=True, append_images=frames[1:], duration=70, loop=0, optimize=True)
print("Generated original app icon, stickers and animated GIFs")
