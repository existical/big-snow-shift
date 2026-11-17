class_name GameLocalization
extends RefCounted

signal language_changed(code: String)

const DIRECTORY := "res://localization/translations/"
const MANIFEST := "res://localization/languages.json"
const FONT_NAMES := ["NotoSans", "NotoSansArabic", "NotoSansHebrew", "NotoSansArmenian", "NotoSansGeorgian", "NotoSansThai", "NotoSansJP", "NotoSansKR", "NotoSansSC", "NotoSansTC"]
const DISPLAY_FONT_NAMES := {800: "MPLUSRounded1c-ExtraBold", 900: "MPLUSRounded1c-Black"}
const REGIONAL_DISPLAY_FONTS := {"ar": "NotoSansArabic", "hy-AM": "NotoSansArmenian", "ka-GE": "NotoSansGeorgian", "th-TH": "NotoSansThai", "ko-KR": "NotoSansKR", "zh-CN": "NotoSansSC", "zh-Hant": "NotoSansTC"}
const DEFAULT_REGIONS := {"es": "es-ES", "fr": "fr-FR", "nl": "nl-NL", "pt": "pt-PT", "zh": "zh-CN"}

var languages: Array = []
var active_code := "en"
var preference := "system"
var catalogs: Dictionary = {}
var translations: Dictionary = {}
var english: Dictionary = {}
var fonts: Dictionary = {}
var markers := RegEx.new()

func _init() -> void:
	markers.compile("\\{\\{(\\w+)\\}\\}")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if manifest is Dictionary and manifest.get("languages") is Array:
		languages = manifest.languages
	english = read_catalog(DIRECTORY + "en.json")
	if english.is_empty():
		push_error("English localization catalog is unavailable.")
	catalogs["en"] = english
	register_translation("en", english)

func initialize(saved_preference: String = "system") -> void:
	if not set_language(saved_preference):
		set_language("en")

func has_language(code: String) -> bool:
	for entry in languages:
		if entry.code == code:
			return true
	return false

func resolve_locale(code: String) -> String:
	var normalized := TranslationServer.standardize_locale(code)
	for entry in languages:
		if TranslationServer.standardize_locale(entry.code) == normalized:
			return entry.code
	var language := normalized.get_slice("_", 0)
	if language == "tl":
		return "fil-PH"
	# Keep the requested catalog name 'no', including on Bokmål systems.
	if language in ["no", "nb", "nn"]:
		return "no"
	if language == "zh":
		return "zh-Hant" if "Hant" in normalized or normalized.ends_with("_TW") or normalized.ends_with("_HK") or normalized.ends_with("_MO") else "zh-CN"
	if DEFAULT_REGIONS.has(language):
		return DEFAULT_REGIONS[language]
	for entry in languages:
		if TranslationServer.standardize_locale(entry.code).get_slice("_", 0) == language:
			return entry.code
	return "en"

func set_language(code: String) -> bool:
	if code != "system" and not has_language(code):
		return false
	var resolved := resolve_locale(OS.get_locale()) if code == "system" else code
	if not catalogs.has(resolved):
		var catalog := read_catalog(DIRECTORY + resolved + ".json")
		if catalog.is_empty():
			return false
		catalogs[resolved] = catalog
		register_translation(resolved, catalog)
	active_code = resolved
	preference = code
	TranslationServer.set_locale(TranslationServer.standardize_locale(resolved))
	language_changed.emit(active_code)
	return true

func register_translation(code: String, catalog: Dictionary) -> void:
	var translation := Translation.new()
	translation.locale = TranslationServer.standardize_locale(code)
	# Materialize English fallback so partial catalogs also work through tr().
	var merged := english.duplicate()
	merged.merge(catalog, true)
	for key in merged:
		translation.add_message(key, merged[key])
	translations[code] = translation
	TranslationServer.add_translation(translation)

func text(key: String, variables: Dictionary = {}) -> String:
	var source := String(TranslationServer.translate(key))
	var result := ""
	var cursor := 0
	for marker in markers.search_all(source):
		result += source.substr(cursor, marker.get_start() - cursor)
		var name := marker.get_string(1)
		result += str(variables[name]) if variables.has(name) else marker.get_string()
		cursor = marker.get_end()
	return result + source.substr(cursor)

func is_rtl() -> bool:
	return active_code == "ar" or active_code == "he-IL"

func display_base_font(weight: int) -> Font:
	# Chinese must use its regional Han forms throughout, rather than mixing
	# Japanese M PLUS glyphs with the remaining Chinese fallback characters.
	var name: String = REGIONAL_DISPLAY_FONTS.get(active_code, DISPLAY_FONT_NAMES[weight])
	return load("res://assets/fonts/" + name + ".ttf")

func fallback_fonts(all_scripts: bool = false) -> Array[Font]:
	var names: Array = FONT_NAMES.duplicate() if all_scripts else ["NotoSans"]
	var regional := {"ar": "NotoSansArabic", "he-IL": "NotoSansHebrew", "hy-AM": "NotoSansArmenian", "ka-GE": "NotoSansGeorgian", "th-TH": "NotoSansThai", "ja-JP": "NotoSansJP", "ko-KR": "NotoSansKR", "zh-CN": "NotoSansSC", "zh-Hant": "NotoSansTC"}
	if regional.has(active_code):
		names.erase(regional[active_code])
		names.push_front(regional[active_code])
	var result: Array[Font] = []
	for name in names:
		if not fonts.has(name):
			var variation := FontVariation.new()
			variation.base_font = load("res://assets/fonts/" + name + ".ttf")
			variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
			fonts[name] = variation
		result.append(fonts[name])
	return result

func dispose() -> void:
	for translation in translations.values():
		TranslationServer.remove_translation(translation)

static func read_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	var flat: Dictionary = {}
	return flat if flatten_catalog(parser.data, "", flat) else {}

static func flatten_catalog(tree: Dictionary, prefix: String, result: Dictionary) -> bool:
	for name in tree:
		if not name is String or name.is_empty() or "." in name:
			return false
		var key: String = prefix + "." + name if not prefix.is_empty() else name
		var value: Variant = tree[name]
		if value is Dictionary:
			if not flatten_catalog(value, key, result):
				return false
		elif value is String:
			if not value.strip_edges().is_empty():
				result[key] = value
		else:
			return false
	return true
