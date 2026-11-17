extends SceneTree

var game: Control
var failures: Array[String] = []
var checks := 0
var locale := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(locale + ": " + message)
		printerr("FAIL: " + locale + ": " + message)

func inspect_ui(node: Node) -> void:
	if node.has_meta("translation_font_size"):
		var dimensions: Vector2 = node.get_meta("translation_size", node.size)
		check(node.size.x <= dimensions.x + 1 and node.size.y <= dimensions.y + 1, "control expanded beyond authored size: " + node.text + " actual=" + str(node.size) + " intended=" + str(dimensions) + " font=" + str(node.get_theme_font_size("font_size")))
		game.fit_localized_text(node, true)
		check(node.get_meta("text_fits", true), "text exceeds bounds: " + node.text)
		if node is Label and not node.text.is_empty():
			check(node.get_visible_line_count() >= node.get_line_count(), "wrapped text is clipped: " + node.text)
	if node is Control and node.has_meta("layout_position") and node.get_parent() is Control:
		check(node.position.is_equal_approx(node.get_meta("layout_position")), "language moved a UI control: " + str(node.name))
		var bounds: Rect2 = node.get_rect()
		var available: Vector2 = node.get_parent().size
		check(bounds.position.x >= -1 and bounds.position.y >= -1 and bounds.end.x <= available.x + 1 and bounds.end.y <= available.y + 1, "control outside parent: " + str(node.name) + " " + str(bounds))
	if node.has_meta("translation_key"):
		check(not node.text.contains("{{"), "unresolved UI variables: " + node.text)
	for child in node.get_children():
		inspect_ui(child)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = "res://builds/localization-test-profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(game.profile.path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile.path + suffix))
	game.profile.settings.language = "en"
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	var l10n: GameLocalization = game.localization
	check(l10n.languages.size() == 56, "all requested locale variants available")
	for added in ["af-ZA", "be-BY", "cy-GB", "is-IS", "mt-MT"]:
		check(l10n.resolve_locale(added.replace("-", "_")) == added, "new system locale resolves: " + added)
		check(l10n.resolve_locale(added.get_slice("-", 0)) == added, "new language without region resolves: " + added)
	check(l10n.resolve_locale("fil") == "fil-PH", "Filipino language negotiation")
	check(l10n.resolve_locale("tl-PH") == "fil-PH", "Tagalog system locale uses Filipino catalog")
	check(l10n.resolve_locale("fr-BE") == "fr-FR", "French region negotiation")
	check(l10n.resolve_locale("nb-NO") == "no", "Bokmål alias")
	check(l10n.resolve_locale("zh-TW") == "zh-Hant", "traditional Chinese region negotiation")
	check(l10n.resolve_locale("zh-Hans") == "zh-CN", "simplified Chinese script negotiation")
	check(l10n.resolve_locale("xx-YY") == "en", "unsupported system locale falls back to English")
	check(l10n.text("missing.key") == "missing.key", "missing message exposes key")
	check(l10n.text("hud.round").contains("{{round}}"), "unresolved variables remain visible")
	check(l10n.text("hud.cleared", {"percent": 0}) == "Cleared 0%", "zero interpolation")
	check(l10n.text("hud.cleared", {"percent": false}) == "Cleared false%", "false interpolation")
	var before := l10n.active_code
	check(not l10n.set_language("../../outside") and l10n.active_code == before, "unsupported language does not change runtime")
	l10n.languages.append({"code": "zz", "name": "Missing fixture"})
	check(not l10n.set_language("zz") and l10n.active_code == before, "unreadable catalog retains previous language")
	l10n.languages.pop_back()
	var fixture_path := "res://builds/localization-malformed.json"
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string('{"hud":{"bad":42}}')
	file.close()
	check(GameLocalization.read_catalog(fixture_path).is_empty(), "invalid catalog leaves rejected")
	file = FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string('{broken')
	file.close()
	check(GameLocalization.read_catalog(fixture_path).is_empty(), "malformed JSON rejected")
	# A partial valid catalog keeps English through the native translation API.
	l10n.register_translation("lv-LV", {"menu.play": "Spēlēt!"})
	l10n.catalogs["lv-LV"] = {"menu.play": "Spēlēt!"}
	l10n.set_language("lv-LV")
	check(l10n.text("menu.play") == "Spēlēt!" and l10n.text("common.settings") == "Settings", "per-message English fallback")
	TranslationServer.remove_translation(l10n.translations["lv-LV"])
	l10n.translations.erase("lv-LV")
	l10n.catalogs.erase("lv-LV")
	# Prove the actual selector updates the current screen without a rebuild.
	l10n.set_language("en")
	game.show_settings("menu")
	var selector: OptionButton = game.overlay.find_child("LanguageChoice", true, false)
	check(selector.item_count == 57, "selector includes system and all 56 locales")
	for selected_code in ["fil-PH", "af-ZA", "be-BY", "cy-GB", "is-IS", "mt-MT"]:
		var selected_index := 0
		for index in selector.item_count:
			if selector.get_item_metadata(index) == selected_code: selected_index = index
		selector.item_selected.emit(selected_index)
		check(l10n.active_code == selected_code and game.profile.settings.language == selected_code, "selector applies and persists " + selected_code)
		var recovered := PlayerProfile.new()
		recovered.path = game.profile.path
		recovered.load_profile()
		check(recovered.settings.language == selected_code, "saved preference survives reload: " + selected_code)
		var fresh := GameLocalization.new()
		fresh.initialize(recovered.settings.language)
		check(fresh.active_code == selected_code, "startup restores preference: " + selected_code)
		fresh.dispose()
	var rtl_start: Control = load("res://scenes/main.tscn").instantiate()
	rtl_start.qa_mode = true
	rtl_start.profile.path = "res://builds/localization-rtl-startup-unused.json"
	rtl_start.profile.settings.language = "ar"
	root.add_child(rtl_start)
	rtl_start.set_physics_process(false)
	await process_frame
	check(rtl_start.localization.active_code == "ar" and rtl_start.overlay.get_child(0).position.is_equal_approx(Vector2(24, 30)), "cold RTL startup preserves the original logo position")
	rtl_start.sound.shutdown()
	rtl_start.queue_free()
	await process_frame
	# Restore this instance's registered translations after the startup probe.
	game.change_language("en", false)
	for entry in l10n.languages:
		locale = entry.code
		check(game.change_language(locale, false), "catalog loads")
		check(l10n.catalogs[locale].size() == l10n.english.size(), "complete catalog")
		check(String(TranslationServer.translate("common.settings")) == l10n.catalogs[locale]["common.settings"], "native TranslationServer integration")
		var glyphs := "".join(l10n.catalogs[locale].values())
		var missing := ""
		for character in glyphs:
			if character.unicode_at(0) > 32 and not game.body_font.has_char(character.unicode_at(0)) and not missing.contains(character):
				missing += character
		check(missing.is_empty(), "bundled font coverage: " + missing)
		var missing_display := ""
		for character in glyphs:
			if character.unicode_at(0) > 32 and (not game.display_font.has_char(character.unicode_at(0)) or not game.secondary_font.has_char(character.unicode_at(0))) and not missing_display.contains(character):
				missing_display += character
		check(missing_display.is_empty(), "both display weights cover the catalog: " + missing_display)
		if locale in ["zh-CN", "zh-Hant"]:
			var expected := "NotoSansSC.ttf" if locale == "zh-CN" else "NotoSansTC.ttf"
			check(game.display_font.base_font.resource_path.ends_with(expected) and game.secondary_font.base_font.resource_path.ends_with(expected), "Chinese display roles use the regional font")
			var shaped := TextLine.new()
			shaped.add_string("冰你雪骨直", game.display_font, 30)
			shaped.get_size()
			var primary_rid: RID = game.display_font.get_rids()[0]
			var region_only := true
			for glyph in TextServerManager.get_primary_interface().shaped_text_get_glyphs(shaped.get_rid()):
				if glyph.font_rid != primary_rid: region_only = false
			check(region_only, "Chinese Han glyphs are shaped by one regional display face")
		elif locale in ["en", "ru-RU", "el-GR", "he-IL", "ja-JP"]:
			check(game.display_font.base_font.resource_path.ends_with("MPLUSRounded1c-Black.ttf") and game.secondary_font.base_font.resource_path.ends_with("MPLUSRounded1c-ExtraBold.ttf"), "supported scripts use the two real rounded weights")
		var missing_names := ""
		for language_entry in l10n.languages:
			for character in language_entry.name:
				if not game.language_font.has_char(character.unicode_at(0)):
					missing_names += character
		check(missing_names.is_empty(), "language selector covers all native names: " + missing_names)
		game.show_menu()
		await process_frame
		inspect_ui(game.overlay)
		game.show_difficulty()
		if game.selected_game_mode != "custom": game.open_custom_game()
		inspect_ui(game.overlay)
		game.change_custom_page(true)
		inspect_ui(game.overlay)
		game.difficulty_back()
		game.confirm_new_night()
		await process_frame
		inspect_ui(game.overlay)
		game.show_settings("pause")
		await process_frame
		inspect_ui(game.overlay)
		check(not game.overlay.is_layout_rtl(), "UI geometry stays fixed for every language")
		game.show_pause()
		await process_frame
		inspect_ui(game.overlay)
		game.show_scores()
		await process_frame
		inspect_ui(game.overlay)
		for state in ["round_done", "lost", "won"]:
			game.model.state = state
			game.show_result()
			await process_frame
			inspect_ui(game.overlay)
		game.name_edit.text = "menu.play"
		game.toast("messages.clear", 5)
		var toast_remaining: float = game.toast_time
		game.change_language("en" if locale != "en" else "lv-LV", false)
		check(game.name_edit.text == "menu.play", "player text stays literal")
		check(game.toast_time == toast_remaining and game.toast_label.text == l10n.text("messages.clear"), "active toast retranslates without restarting")
		game.change_language(locale, false)
		game.model.state = "returning"
		game.refresh_hud()
		inspect_ui(game.hud)
		await process_frame
	locale = ""
	game.change_language("ar", false)
	game.model.snow.brush(Vector2(.5, .5), Vector2.ONE * 2, 128)
	game.refresh_hud()
	check(game.progress_fill.position.is_equal_approx(Vector2.ONE), "RTL progress keeps the original fill direction as clearing advances")
	check(game.change_language("system", false), "system language choice is available")
	game.change_language("en", false)
	game.model.time_left = 600
	game.model.score = 9999999
	game.resume_game()
	game.refresh_hud()
	check(game.time_label.text == "10:00" and game.time_label.get_meta("text_fits"), "longest round timer fits at the new HUD size")
	check(game.score_label.text == "9999999" and game.score_label.get_meta("text_fits"), "maximum score fits without clipping")
	check(game.time_label.get_theme_font_size("font_size") == 34, "timer retains its intended readable size")
	check(game.round_label.get_theme_font("font") == game.secondary_font and game.time_label.get_theme_font("font") == game.display_font, "HUD labels and values have distinct display weights")
	check("M PLUS Rounded 1c" in game.credits_text() and not "Lilita One" in game.credits_text(), "credits identify the bundled display font")
	var report := {"localization_checks": checks, "locales": l10n.languages.size(), "failures": failures}
	var output := FileAccess.open("res://builds/localization-runtime.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print(JSON.stringify(report))
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
