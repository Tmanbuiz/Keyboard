#!/usr/bin/env python3
"""Draw WianTribe's original text stickers (needs Pillow and the Poppins Bold font).

Writes keyboard copies to Sources/Keyboard/Media/sticker-*.png and the iMessage sticker pack
sticker catalog to Sources/Stickers/Stickers.xcstickers. Outputs are committed.
"""
import json
import math
import pathlib
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Sources/Keyboard/Media"
CATALOG = ROOT / "Sources/Stickers/Stickers.xcstickers"
FONT = next((p for p in ["/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", "/Library/Fonts/Poppins-Bold.ttf",
                         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"] if pathlib.Path(p).exists()), None)
SIZE = 408  # Apple's recommended size for a regular sticker at @3x

STICKERS = [
    ("hello-there", "Hello!", (255, 186, 73), (255, 120, 64), "sparkle"),
    ("thank-you", "Thank\nyou!", (98, 214, 172), (36, 150, 140), "heart"),
    ("on-my-way", "On my\nway!", (95, 160, 255), (60, 90, 220), "dash"),
    ("lol", "LOL", (255, 214, 64), (250, 150, 30), "burst"),
    ("congrats", "Congrats!", (255, 120, 170), (210, 60, 140), "confetti"),
    ("good-morning", "Good\nmorning", (255, 200, 90), (255, 140, 60), "sun"),
    ("good-night", "Good\nnight", (90, 100, 200), (40, 40, 120), "moon"),
    ("love-you", "Love\nyou", (255, 95, 120), (200, 40, 80), "heart"),
    ("miss-you", "Miss\nyou", (180, 150, 255), (120, 80, 220), "heart"),
    ("happy-birthday", "Happy\nbirthday!", (255, 150, 90), (230, 70, 110), "confetti"),
    ("sorry", "Sorry!", (160, 200, 230), (90, 130, 190), "drop"),
    ("see-you-soon", "See you\nsoon", (120, 220, 200), (40, 160, 170), "sparkle"),
    ("yes", "YES!", (110, 220, 110), (40, 160, 70), "burst"),
    ("no-way", "No way!", (255, 140, 110), (220, 70, 60), "burst"),
    ("amen", "Amen", (250, 225, 150), (210, 160, 60), "sparkle"),
    ("well-done", "Well\ndone!", (110, 200, 255), (40, 120, 220), "star"),
]


def star(draw, cx, cy, r, fill, points=5):
    pts = []
    for i in range(points * 2):
        angle = math.pi / points * i - math.pi / 2
        radius = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    draw.polygon(pts, fill=fill)


def heart(draw, cx, cy, r, fill):
    draw.ellipse((cx - r, cy - r * 0.8, cx, cy + r * 0.2), fill=fill)
    draw.ellipse((cx, cy - r * 0.8, cx + r, cy + r * 0.2), fill=fill)
    draw.polygon([(cx - r * 0.97, cy - r * 0.15), (cx + r * 0.97, cy - r * 0.15), (cx, cy + r * 1.05)], fill=fill)


def decorate(draw, kind, light, dark):
    white = (255, 255, 255, 235)
    if kind == "heart":
        heart(draw, 330, 92, 34, (255, 80, 110)); heart(draw, 78, 330, 22, white)
    elif kind in ("sparkle", "star"):
        star(draw, 336, 84, 30, (255, 240, 140)); star(draw, 70, 320, 18, white, 4); star(draw, 352, 312, 14, white, 4)
    elif kind == "sun":
        draw.ellipse((300, 50, 370, 120), fill=(255, 230, 80))
        for i in range(10):
            a = math.tau * i / 10
            draw.line((335 + math.cos(a) * 44, 85 + math.sin(a) * 44, 335 + math.cos(a) * 58, 85 + math.sin(a) * 58), fill=(255, 230, 80), width=7)
    elif kind == "moon":
        behind = tuple(int(light[i] + (dark[i] - light[i]) * 0.25) for i in range(3))
        draw.ellipse((276, 84, 336, 144), fill=(255, 240, 170)); draw.ellipse((296, 74, 350, 128), fill=behind)
        star(draw, 80, 90, 12, white, 4); star(draw, 340, 330, 10, white, 4)
    elif kind == "confetti":
        colors = [(255, 230, 90), (120, 220, 255), (255, 255, 255), (150, 255, 160)]
        for i in range(14):
            x = 62 + (i * 97) % 280; y = 72 + (i * 53) % 50 if i % 2 else 286 + (i * 31) % 40
            draw.rounded_rectangle((x, y, x + 16, y + 8), radius=3, fill=colors[i % 4])
    elif kind == "dash":
        for i, y in enumerate((150, 200, 250)):
            draw.rounded_rectangle((20, y, 70 - i * 10, y + 10), radius=5, fill=white)
    elif kind == "burst":
        star(draw, 340, 80, 36, (255, 255, 255, 220), 8)
    elif kind == "drop":
        draw.ellipse((318, 92, 346, 124), fill=(150, 210, 255)); draw.polygon([(320, 104), (344, 104), (332, 74)], fill=(150, 210, 255))


def sticker(text, light, dark, kind):
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    box = (34, 54, SIZE - 34, SIZE - 64)
    # Soft shadow, then a thick white outline like a die-cut sticker.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0] + 4, box[1] + 10, box[2] + 4, box[3] + 10), radius=70, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(9)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((box[0] - 10, box[1] - 10, box[2] + 10, box[3] + 10), radius=80, fill=(255, 255, 255))
    draw.polygon([(110, box[3] + 4), (170, box[3] + 4), (96, box[3] + 52)], fill=(255, 255, 255))
    gradient = Image.new("RGBA", (SIZE, SIZE))
    gd = ImageDraw.Draw(gradient)
    for y in range(SIZE):
        f = y / SIZE
        gd.line((0, y, SIZE, y), fill=tuple(int(light[i] + (dark[i] - light[i]) * f) for i in range(3)) + (255,))
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(box, radius=70, fill=255)
    md.polygon([(118, box[3] - 6), (160, box[3] - 6), (106, box[3] + 38)], fill=255)
    canvas.paste(gradient, (0, 0), mask)
    draw = ImageDraw.Draw(canvas)
    decorate(draw, kind, light, dark)
    lines = text.split("\n")
    size = 92 if len(lines) == 1 and len(text) <= 6 else (70 if len(lines) == 1 else 64)
    font = ImageFont.truetype(FONT, size) if FONT else ImageFont.load_default()
    while max(draw.textlength(line, font=font) for line in lines) > box[2] - box[0] - 40 and size > 30:
        size -= 4; font = ImageFont.truetype(FONT, size) if FONT else font
    line_height = size * 1.08
    top = (box[1] + box[3]) / 2 - line_height * len(lines) / 2
    for i, line in enumerate(lines):
        width = draw.textlength(line, font=font)
        x = (SIZE - width) / 2; y = top + i * line_height - size * 0.12
        draw.text((x + 3, y + 4), line, font=font, fill=(0, 0, 0, 70))
        draw.text((x, y), line, font=font, fill=(255, 255, 255), stroke_width=2, stroke_fill=tuple(dark))
    return canvas


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    pack = CATALOG / "Sticker Pack.stickerpack"
    if CATALOG.exists(): shutil.rmtree(CATALOG)
    pack.mkdir(parents=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    entries = []
    for name, text, light, dark, kind in STICKERS:
        image = sticker(text, light, dark, kind)
        image.save(MEDIA / f"sticker-{name}.png", optimize=True)
        folder = pack / f"{name}.sticker"; folder.mkdir()
        image.save(folder / f"{name}.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"filename": f"{name}.png", "accessibility-label": text.replace("\n", " ")}}, indent=2))
        entries.append({"filename": f"{name}.sticker"})
    (pack / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"grid-size": "regular"}, "stickers": entries}, indent=2))
    # The Messages app icon set, drawn from the app icon.
    icon_source = Image.open(ROOT / "Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png").convert("RGB")
    icons = CATALOG / "iMessage App Icon.stickersiconset"; icons.mkdir()
    specs = [("iphone", "29x29", "2x"), ("iphone", "29x29", "3x"), ("iphone", "60x45", "2x"), ("iphone", "60x45", "3x"),
             ("ipad", "29x29", "2x"), ("ipad", "67x50", "2x"), ("ipad", "74x55", "2x"), ("ios-marketing", "1024x1024", "1x"),
             ("universal", "27x20", "2x"), ("universal", "27x20", "3x"), ("universal", "32x24", "2x"), ("universal", "32x24", "3x"),
             ("ios-marketing", "1024x768", "1x")]
    images = []
    for idiom, size, scale in specs:
        w, h = (float(v) for v in size.split("x")); factor = int(scale[0])
        pixels = (int(round(w * factor)), int(round(h * factor)))
        filename = f"icon-{idiom}-{size}@{scale}.png"
        canvas = Image.new("RGB", pixels, (10, 40, 50))
        side = min(pixels); icon = icon_source.resize((side, side), Image.LANCZOS)
        canvas.paste(icon, ((pixels[0] - side) // 2, (pixels[1] - side) // 2))
        canvas.save(icons / filename)
        entry = {"idiom": idiom, "size": size, "scale": scale, "filename": filename}
        if idiom == "universal" or size == "1024x768": entry["platform"] = "ios"  # Xcode only assigns the Messages store icon with this
        images.append(entry)
    (icons / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
    print(f"{len(STICKERS)} stickers written")


if __name__ == "__main__":
    main()
