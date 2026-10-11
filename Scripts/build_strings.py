#!/usr/bin/env python3
"""Build the companion app's String Catalog from Scripts/data/app-translations.json.
Translations were written for WianTribe and should be reviewed by native speakers before release."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = ["es", "fr", "pt", "de", "ar"]
source = json.loads((ROOT / "Scripts/data/app-translations.json").read_text(encoding="utf-8"))
strings = {}
for key, values in source.items():
    strings[key] = {"localizations": {code: {"stringUnit": {"state": "translated", "value": values[code]}} for code in LANGUAGES if code in values}}
catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
(ROOT / "Sources/App/Localizable.xcstrings").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"{len(strings)} strings in {len(LANGUAGES)} languages")
