#!/usr/bin/env python3
"""Build the language catalog and per-language dictionaries.

Word frequencies come from the `wordfreq` package (code Apache-2.0, data CC BY-SA 4.0,
https://github.com/rspeer/wordfreq). Yorùbá and Naija Pidgin come from the original
WianTribe starter list. Run `pip install wordfreq` first; the outputs are committed so
normal builds do not need it.
"""
import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/Core/Resources"
WORDS = 30000

QWERTY = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
QWERTZ = ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
NORDIC_SV = ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"]
NORDIC_NO = ["qwertyuiopå", "asdfghjkløæ", "zxcvbnm"]
LATIN = {"a": "àáâäãåāæ", "c": "çćč", "e": "èéêëēė", "i": "ìíîïī", "n": "ñń", "o": "òóôöõøōœ", "s": "ßśš", "u": "ùúûüū", "y": "ÿý", "z": "žźż"}

# code, native name, English name, short title, layout rows, long-press extras, wordfreq code,
# autocorrect allowed, UITextChecker language, right-to-left
LANGUAGES = [
    ("en", "English", "English", "EN", QWERTY, LATIN, "en", True, "en_US", False),
    ("es", "Español", "Spanish", "ES", ["qwertyuiop", "asdfghjklñ", "zxcvbnm"], {"a": "á", "e": "é", "i": "í", "o": "ó", "u": "úü", "n": "ñ", "?": "¿", "!": "¡"}, "es", True, "es", False),
    ("fr", "Français", "French", "FR", ["azertyuiop", "qsdfghjklm", "wxcvbn"], {"a": "àâæ", "c": "ç", "e": "éèêë", "i": "îï", "o": "ôœ", "u": "ùûü", "y": "ÿ"}, "fr", True, "fr", False),
    ("pt", "Português", "Portuguese", "PT", QWERTY, {"a": "ãáàâ", "c": "ç", "e": "éê", "i": "í", "o": "õóô", "u": "úü"}, "pt", True, "pt_BR", False),
    ("de", "Deutsch", "German", "DE", ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"], {"a": "ä", "o": "ö", "u": "ü", "s": "ß"}, "de", True, "de", False),
    ("it", "Italiano", "Italian", "IT", QWERTY, {"a": "àá", "e": "èé", "i": "ìí", "o": "òó", "u": "ùú"}, "it", True, "it", False),
    ("nl", "Nederlands", "Dutch", "NL", QWERTY, {"e": "éëè", "i": "ïí", "o": "óö", "u": "üú", "a": "áä"}, "nl", True, "nl", False),
    ("sv", "Svenska", "Swedish", "SV", NORDIC_SV, {"e": "é"}, "sv", True, "sv", False),
    ("nb", "Norsk", "Norwegian", "NO", NORDIC_NO, {"e": "éè", "o": "ö", "a": "ä"}, "nb", True, "nb", False),
    ("da", "Dansk", "Danish", "DA", NORDIC_NO, {"e": "é"}, "da", True, "da", False),
    ("fi", "Suomi", "Finnish", "FI", NORDIC_SV, {"s": "š", "z": "ž"}, "fi", True, "fi", False),
    ("pl", "Polski", "Polish", "PL", QWERTY, {"a": "ą", "c": "ć", "e": "ę", "l": "ł", "n": "ń", "o": "ó", "s": "ś", "z": "żź"}, "pl", True, "pl", False),
    ("cs", "Čeština", "Czech", "CS", QWERTZ, {"a": "á", "c": "č", "d": "ď", "e": "éě", "i": "í", "n": "ň", "o": "ó", "r": "ř", "s": "š", "t": "ť", "u": "úů", "y": "ý", "z": "ž"}, "cs", True, "cs", False),
    ("ro", "Română", "Romanian", "RO", QWERTY, {"a": "ăâ", "i": "î", "s": "ș", "t": "ț"}, "ro", True, "ro", False),
    ("hu", "Magyar", "Hungarian", "HU", QWERTZ, {"a": "á", "e": "é", "i": "í", "o": "óöő", "u": "úüű"}, "hu", True, "hu", False),
    ("tr", "Türkçe", "Turkish", "TR", ["qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç"], {"a": "â", "i": "î", "u": "û"}, "tr", True, "tr", False),
    ("id", "Bahasa Indonesia", "Indonesian", "ID", QWERTY, {}, "id", True, "id", False),
    ("ms", "Bahasa Melayu", "Malay", "MS", QWERTY, {}, "ms", True, "ms", False),
    ("fil", "Filipino", "Filipino", "FIL", QWERTY, {"n": "ñ"}, "fil", True, "fil", False),
    ("sw", "Kiswahili", "Swahili", "SW", QWERTY, {}, None, False, "sw", False),
    ("yo", "Yorùbá", "Yoruba", "YO", QWERTY, {"a": "àá", "e": "ẹẹ̀ẹ́èé", "i": "ìí", "o": "ọọ̀ọ́òó", "u": "ùú", "s": "ṣ", "n": "ǹń", "m": "m̀ḿ"}, None, False, "yo", False),
    ("pcm", "Naija Pidgin", "Nigerian Pidgin", "NG", QWERTY, {"a": "àá", "e": "ẹèé", "o": "ọòó"}, None, False, "en_US", False),
    ("ig", "Igbo", "Igbo", "IG", QWERTY, {"a": "àá", "e": "èé", "i": "ịìí", "o": "ọòó", "u": "ụùú", "n": "ṅńǹ", "m": "ḿ"}, None, False, "ig", False),
    ("ha", "Hausa", "Hausa", "HA", QWERTY, {"b": "ɓ", "d": "ɗ", "k": "ƙ", "y": "ƴ", "'": "ʼ", "a": "àâ", "e": "èê", "i": "ìî", "o": "òô", "u": "ùû"}, None, False, "ha", False),
    ("ru", "Русский", "Russian", "RU", ["йцукенгшщзх", "фывапролджэ", "ячсмитьбю"], {"е": "ё", "ь": "ъ"}, "ru", True, "ru", False),
    ("uk", "Українська", "Ukrainian", "UK", ["йцукенгшщзх", "фівапролджє", "ячсмитьбю"], {"і": "ї", "г": "ґ", "х": "ї", "ь": "'"}, "uk", True, "uk", False),
    ("ar", "العربية", "Arabic", "AR", ["ضصثقفغعهخحج", "شسيبلاتنمكط", "ءظذدزروةى"], {"ا": "أإآ", "ي": "ئ", "و": "ؤ", "ه": "ة", "ء": "ئؤ"}, "ar", False, "ar", True),
    ("he", "עברית", "Hebrew", "HE", ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"], {}, "he", False, "he", True),
]

# Starter English pairs; people's own pairs are learned on the device when they opt in.
NEXT_WORDS = {
    "en": {"": ["I", "the", "you"], "thank": ["you", "god", "goodness"], "how": ["are", "is", "do"], "good": ["morning", "night", "luck"], "i": ["am", "will", "have"],
           "see": ["you", "the", "it"], "happy": ["birthday", "new", "to"], "on": ["my", "the", "your"], "let": ["me", "us", "you"],
           "talk": ["to", "soon", "later"], "what": ["is", "are", "do"], "i'm": ["going", "not", "on"], "are": ["you", "we", "they"],
           "can": ["you", "i", "we"], "do": ["you", "not", "it"], "have": ["a", "you", "to"], "will": ["be", "you", "do"],
           "in": ["the", "a", "my"], "of": ["the", "my", "course"], "to": ["the", "be", "you"], "for": ["the", "you", "your"]},
    "yo": {"": ["ẹ", "mo", "ṣé"], "ẹ": ["kú", "káàárọ̀", "ṣé"], "ṣé": ["dáadáa", "o", "ẹ"]},
    "pcm": {"": ["how", "abeg", "i"], "how": ["far", "you", "body"], "i": ["dey", "go", "no"], "you": ["dey", "go", "sabi"], "wetin": ["dey", "happen", "you"], "e": ["don", "dey", "be"]},
}


def letters_of(rows, extras):
    chars = set("".join(rows))
    for key, values in extras.items():
        chars.add(key)
        chars.update(values)
    return chars


def frequency(zipf):
    return max(1, round(10 ** (zipf - 2)))


def build_dictionary(code, wf_code, rows, extras):
    allowed = letters_of(rows, extras) | {"'", "’", "-"}
    if code == "ar":
        allowed |= set("ًٌٍَُِّْـ")
    entries = {}
    if wf_code:
        import wordfreq
        for word in wordfreq.top_n_list(wf_code, WORDS * 2):
            if len(entries) >= WORDS:
                break
            if not (1 <= len(word) <= 24) or not all(ch in allowed for ch in word):
                continue
            if not any(ch not in "'’-" for ch in word) or word[0] in "'’-" or word[-1] in "-":
                continue
            entries[word] = frequency(wordfreq.zipf_frequency(word, wf_code))
    legacy = json.loads((ROOT / "Scripts/data/starter-lexicon.json").read_text())
    legacy_name = {"en": "english", "yo": "yoruba", "pcm": "pidgin"}.get(code)
    for entry in legacy:
        if entry["language"] == legacy_name:
            word = entry["word"].lower()
            entries[word] = max(entries.get(word, 0), entry["frequency"])
    return sorted(entries.items(), key=lambda item: (-item[1], item[0]))


def main():
    catalog = []
    total = 0
    for code, native, english, short, rows, extras, wf_code, autocorrect, checker, rtl in LANGUAGES:
        words = build_dictionary(code, wf_code, rows, extras)
        if words:
            text = "".join(f"{word}\t{freq}\n" for word, freq in words)
            (OUT / f"dict-{code}.txt").write_text(text, encoding="utf-8")
            total += len(text.encode())
        catalog.append({
            "code": code, "name": native, "englishName": english, "shortTitle": short, "rows": rows,
            "alternates": {key: list(dict.fromkeys(values)) for key, values in extras.items()},
            "hasDictionary": bool(words), "autocorrect": autocorrect and bool(words), "checker": checker,
            "rightToLeft": rtl, "nextWords": NEXT_WORDS.get(code, {}),
        })
        print(f"{code:4} {native:18} {len(words):6} words")
    (OUT / "Languages.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(catalog)} languages, {total / 1e6:.1f} MB of dictionaries")


if __name__ == "__main__":
    main()
