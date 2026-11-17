"""Validate shipped catalogs and source references without network access."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "localization" / "translations"
MARKER = re.compile(r"\{\{(\w+)\}\}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate key: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def flatten(tree, prefix=""):
    if not isinstance(tree, dict) or not tree:
        raise ValueError(f"{prefix or 'catalog'} must be a nonempty object")
    result = {}
    for name, value in tree.items():
        if not name or "." in name:
            raise ValueError(f"Invalid key segment: {name!r}")
        key = f"{prefix}.{name}" if prefix else name
        if isinstance(value, dict):
            result.update(flatten(value, key))
        elif isinstance(value, str) and value.strip():
            if "XQVAR" in value or "987654321" in value:
                raise ValueError(f"Unresolved translation token: {key}")
            result[key] = value
        else:
            raise ValueError(f"{key} must be a nonblank string")
    return result


def protected_term_errors(catalog, rules):
    errors = []
    for key, terms in rules.items():
        if key not in catalog:
            errors.append(f"Protected-term rule references an unknown message: {key}")
            continue
        for term in terms:
            if term not in catalog[key]:
                errors.append(f"{key} must preserve the credited name/title {term!r}")
    return errors


def main():
    errors = []
    manifest = read_json(ROOT / "localization" / "languages.json")
    codes = [entry["code"] for entry in manifest["languages"]]
    if len(codes) != 56 or len(set(codes)) != 56 or manifest["fallback"] != "en":
        errors.append("Expected exactly 56 distinct locale variants with English fallback")
    if set(codes) != {path.stem for path in DIRECTORY.glob("*.json")}:
        errors.append("Catalog filenames must exactly match the language manifest")
    english = flatten(read_json(DIRECTORY / "en.json"))
    protected_terms = read_json(ROOT / "localization" / "protected-terms.json")
    for code in codes:
        try:
            if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z]{2,4}){0,2}", code):
                raise ValueError("Invalid locale identifier")
            catalog = flatten(read_json(DIRECTORY / f"{code}.json"))
            if set(catalog) != set(english):
                raise ValueError(f"Missing keys: {set(english) - set(catalog)}; extra keys: {set(catalog) - set(english)}")
            for key, source in english.items():
                if set(MARKER.findall(source)) != set(MARKER.findall(catalog[key])):
                    raise ValueError(f"Placeholder mismatch: {key}")
            if code != "en" and catalog == english:
                raise ValueError("Entire catalog is untranslated English")
            if "custom.seconds" in catalog and not catalog["custom.seconds"].replace("{{value}}", "").strip():
                raise ValueError("Custom duration display is missing its seconds unit")
            errors.extend(f"{code}: {message}" for message in protected_term_errors(catalog, protected_terms))
        except (ValueError, OSError) as error:
            errors.append(f"{code}: {error}")
    # All dynamic key families in this game are explicit arrays/conditionals.
    groups = "|".join(read_json(DIRECTORY / "en.json"))
    references = set()
    for path in (ROOT / "scripts").glob("*.gd"):
        source = path.read_text(encoding="utf-8")
        references.update(re.findall(r'"((?:' + groups + r')\.[A-Za-z0-9_.]+)"', source))
        if path.name == "main.gd":
            for value in re.findall(r'\b(?:label|button|toast)\([^\n]*?"([^"\n]*)"', source):
                if value and value not in english and value not in {"X", "II", "%02d   %s", "%06d", "difficulty."}:
                    errors.append(f"Uncatalogued UI literal: {value}")
    # Difficulty cards construct their mode and explanation keys from fixed IDs.
    references.update("difficulty." + mode + suffix for mode in ("easy", "medium", "hard", "extreme") for suffix in ("", "Help"))
    for key in references - set(english):
        errors.append(f"Unknown source translation key: {key}")
    for preset in (ROOT / "export_presets.cfg").read_text(encoding="utf-8").split("include_filter=")[1:]:
        if "localization/translations/*.json" not in preset.splitlines()[0] or "localization/languages.json" not in preset.splitlines()[0]:
            errors.append("Export preset omits localization JSON")
    report = {"locales": len(codes), "keys_per_locale": len(english), "source_references": len(references),
              "unreferenced_keys": sorted(set(english) - references), "errors": errors}
    output = ROOT / "builds" / "localization-check.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
