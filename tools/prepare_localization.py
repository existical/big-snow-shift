"""Create the initial machine translation drafts. Never run during normal builds.

Only English UI messages are sent to Google's public translation endpoint.
Existing catalogs are retained unless --overwrite is explicitly provided.
Generated translations still require native-speaker review.
"""
import argparse
import concurrent.futures
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "localization" / "translations"
PROTECTED_TERMS = json.loads((ROOT / "localization" / "protected-terms.json").read_text(encoding="utf-8"))
LANGUAGES = [
    ("af-ZA", "Afrikaans", "af"),
    ("ar", "العربية", "ar"), ("az", "Azərbaycanca", "az"),
    ("be-BY", "Беларуская", "be"),
    ("bg-BG", "Български", "bg"), ("ca", "Català", "ca"),
    ("cs-CZ", "Čeština", "cs"), ("cy-GB", "Cymraeg", "cy"), ("da-DK", "Dansk", "da"),
    ("de-DE", "Deutsch", "de"), ("el-GR", "Ελληνικά", "el"),
    ("en", "English", "en"), ("es-ES", "Español (España)", "es"),
    ("es-MX", "Español (México)", "es"), ("et-EE", "Eesti", "et"),
    ("fi-FI", "Suomi", "fi"), ("fil-PH", "Filipino", "tl"),
    ("fr-CA", "Français (Canada)", "fr"),
    ("fr-FR", "Français (France)", "fr"), ("ga-IE", "Gaeilge", "ga"),
    ("he-IL", "עברית", "iw"), ("hr-HR", "Hrvatski", "hr"),
    ("hu-HU", "Magyar", "hu"), ("hy-AM", "Հայերեն", "hy"),
    ("id-ID", "Bahasa Indonesia", "id"), ("is-IS", "Íslenska", "is"), ("it-IT", "Italiano", "it"),
    ("ja-JP", "日本語", "ja"), ("ka-GE", "ქართული", "ka"),
    ("kk-KZ", "Қазақша", "kk"), ("ko-KR", "한국어", "ko"),
    ("lt-LT", "Lietuvių", "lt"), ("lv-LV", "Latviešu", "lv"),
    ("mk-MK", "Македонски", "mk"), ("ms-MY", "Bahasa Melayu", "ms"),
    ("mt-MT", "Malti", "mt"),
    ("nl-BE", "Nederlands (België)", "nl"), ("nl-NL", "Nederlands (Nederland)", "nl"),
    ("no", "Norsk bokmål", "no"), ("pl-PL", "Polski", "pl"),
    ("pt-BR", "Português (Brasil)", "pt"), ("pt-PT", "Português (Portugal)", "pt"),
    ("ro-RO", "Română", "ro"), ("ru-RU", "Русский", "ru"),
    ("sk-SK", "Slovenčina", "sk"), ("sl-SI", "Slovenščina", "sl"),
    ("sq-AL", "Shqip", "sq"), ("sr-Cyrl-RS", "Српски (ћирилица)", "sr"),
    ("sv-SE", "Svenska", "sv"), ("th-TH", "ไทย", "th"),
    ("tr-TR", "Türkçe", "tr"), ("uk-UA", "Українська", "uk"),
    ("uz", "O‘zbekcha", "uz"), ("vi-VN", "Tiếng Việt", "vi"),
    ("zh-CN", "简体中文", "zh-CN"), ("zh-Hant", "繁體中文", "zh-TW"),
]


def flatten(tree, prefix=""):
    result = {}
    for name, value in tree.items():
        key = f"{prefix}.{name}" if prefix else name
        if isinstance(value, dict):
            result.update(flatten(value, key))
        else:
            result[key] = value
    return result


def expand(flat):
    tree = {}
    for key, value in flat.items():
        node = tree
        parts = key.split(".")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return tree


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def protect_text(key, value, replacements):
    literals = re.findall(r"\{\{\w+\}\}", value) + PROTECTED_TERMS.get(key, [])
    for literal in sorted(dict.fromkeys(literals), key=len, reverse=True):
        if literal not in value:
            continue
        token = f"987654321{len(replacements):03d}123456789"
        replacements[token] = literal
        value = value.replace(literal, token)
    return value


def restore_text(value, replacements):
    for token, literal in replacements.items():
        value = re.sub(r"\s*".join(map(re.escape, token)), lambda _: literal, value, flags=re.I)
    return value


def validate_translation(key, source, value):
    if not value or set(re.findall(r"\{\{(\w+)\}\}", value)) != set(re.findall(r"\{\{(\w+)\}\}", source)):
        raise ValueError(f"Invalid placeholders: {key}")
    if "987654321" in value:
        raise ValueError(f"Unrestored translation token: {key}")
    for term in PROTECTED_TERMS.get(key, []):
        if term not in value:
            raise ValueError(f"Altered credited name/title in {key}: {term}")


def translate_batch(items, target):
    placeholders = {}
    lines = []
    for index, (key, value) in enumerate(items):
        value = protect_text(key, value, placeholders)
        lines.append(f"[{index:03d}] {value}")
    query = urllib.parse.urlencode({"client": "gtx", "sl": "en", "tl": target, "dt": "t", "q": "\n".join(lines)})
    request = urllib.request.Request("https://translate.googleapis.com/translate_a/single?" + query,
                                     headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = json.load(response)
    translated = "".join(part[0] for part in data[0] if part[0])
    translated = restore_text(translated, placeholders)
    matches = list(re.finditer(r"\[\s*(\d{3})\s*\]", translated))
    if len(matches) != len(items):
        raise ValueError(f"{target}: message boundary count {len(matches)} != {len(items)}")
    result = {}
    for position, match in enumerate(matches):
        index = int(match.group(1))
        end = matches[position + 1].start() if position + 1 < len(matches) else len(translated)
        value = translated[match.end():end].strip()
        key, source = items[index]
        validate_translation(key, source, value)
        result[key] = value
    if set(result) != {key for key, _ in items}:
        raise ValueError(f"{target}: duplicate or missing message boundaries")
    return result


def translate_language(target, source):
    result = {}
    items = list(source.items())
    for start in range(0, len(items), 20):
        batch = items[start:start + 20]
        try:
            result.update(translate_batch(batch, target))
        except Exception:
            # Some scripts translate numbered message boundaries. Translate
            # those messages individually rather than guessing their mapping.
            for key, value in batch:
                replacements = {}
                protected = protect_text(key, value, replacements)
                query = urllib.parse.urlencode({"client": "gtx", "sl": "en", "tl": target, "dt": "t", "q": protected})
                for attempt in range(4):
                    try:
                        with urllib.request.urlopen("https://translate.googleapis.com/translate_a/single?" + query, timeout=60) as response:
                            data = json.load(response)
                        translated = "".join(part[0] for part in data[0] if part[0]).strip()
                        translated = restore_text(translated, replacements)
                        validate_translation(key, value, translated)
                        result[key] = translated
                        break
                    except Exception:
                        if attempt == 3:
                            raise
                        time.sleep(1 + attempt * 2)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--keys", nargs="+", help="Regenerate only these keys, preserving other translations")
    args = parser.parse_args()
    source = flatten(json.loads((DIRECTORY / "en.json").read_text(encoding="utf-8")))
    if args.keys:
        source = {key: source[key] for key in args.keys}
    manifest_path = ROOT / "localization" / "languages.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"version": 1, "fallback": "en"}
    existing = {entry["code"]: entry for entry in manifest.get("languages", [])}
    manifest["languages"] = [existing.get(code, {"code": code, "name": name, "review": "source" if code == "en" else "machine-draft"}) for code, name, _ in LANGUAGES]
    manifest_entries = {entry["code"]: entry for entry in manifest["languages"]}
    write_json(ROOT / "localization" / "languages.json", manifest)
    targets = sorted({target for code, _, target in LANGUAGES if code != "en" and
                      (args.overwrite or args.keys or not (DIRECTORY / f"{code}.json").exists())})
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        pending = {executor.submit(translate_language, target, source): target for target in targets}
        for future in concurrent.futures.as_completed(pending):
            target = pending[future]
            try:
                translated = future.result()
                for code, _, language_target in LANGUAGES:
                    path = DIRECTORY / f"{code}.json"
                    if code != "en" and language_target == target and (args.overwrite or args.keys or not path.exists()):
                        catalog = flatten(json.loads(path.read_text(encoding="utf-8"))) if args.keys and path.exists() else {}
                        catalog.update(translated)
                        write_json(path, expand(catalog))
                        manifest_entries[code]["review"] = "machine-draft"
                        manifest_entries[code].pop("reviewed_on", None)
                        print(f"{code}: {len(translated)} draft messages", flush=True)
            except Exception as error:
                failures.append(f"{target}: {error}")
    write_json(manifest_path, manifest)
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
