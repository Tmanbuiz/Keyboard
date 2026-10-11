#!/usr/bin/env python3
"""Build the keyboard's emoji list and search keywords from emojibase-data (MIT licence).

Usage: npm install emojibase-data && python3 Scripts/build_emoji.py node_modules/emojibase-data
Only emoji up to Unicode Emoji 15.0 are included so every emoji renders on iOS 17.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/Core/Resources"
MAX_VERSION = 15.0
# emojibase locale -> keyboard language code
LOCALES = {"en": "en", "es": "es", "fr": "fr", "pt": "pt", "de": "de", "it": "it", "nl": "nl", "sv": "sv", "nb": "nb",
           "da": "da", "fi": "fi", "pl": "pl", "hu": "hu", "ms": "ms", "ru": "ru", "uk": "uk"}


def main(source):
    source = pathlib.Path(source)
    base = json.loads((source / "en/data.json").read_text())
    included = []
    for item in sorted(base, key=lambda x: x.get("order", 1e9)):
        if item.get("group") in (None, 2) or item.get("version", 99) > MAX_VERSION:
            continue
        # One tone per emoji (multi-person combinations are left to Apple's own keyboard).
        skins = [s["emoji"] for s in item.get("skins", []) if isinstance(s.get("tone"), int) and s.get("version", 99) <= MAX_VERSION]
        entry = {"e": item["emoji"], "g": item["group"]}
        if len(skins) == 5:
            entry["s"] = skins
        included.append(entry)
    (OUT / "emoji.json").write_text(json.dumps(included, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    hexes = {item["hexcode"] for item in base}
    allowed = {entry["e"] for entry in included}
    for locale, code in LOCALES.items():
        path = source / locale / "data.json"
        if not path.exists():
            continue
        lines = []
        for item in json.loads(path.read_text()):
            if item.get("emoji") not in allowed or item.get("hexcode") not in hexes:
                continue
            words = " ".join(dict.fromkeys([item.get("label", "")] + item.get("tags", []))).lower().replace("\t", " ").replace("\n", " ")
            lines.append(f"{item['emoji']}\t{words}")
        (OUT / f"emojikw-{code}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(included)} emoji, {sum(1 for e in included if 's' in e)} with skin tones")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "node_modules/emojibase-data")
