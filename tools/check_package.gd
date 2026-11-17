extends SceneTree

func files_in(path: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(path):
		found.append(path.path_join(file))
	for directory in DirAccess.get_directories_at(path):
		found.append_array(files_in(path.path_join(directory)))
	return found

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("FAIL: package could not be mounted")
		quit(1)
		return
	var files := files_in("res://")
	var forbidden: Array[String] = []
	for path in files:
		for name in ["archive/", "art-masters/", "winter_house.png", "icon_caretaker_tree_adaptive_v019.png", "icon_caretaker_tree_monochrome_v019.png", "reference/", "SCLAUS", "original-assets", "caretaker_animation", "caretaker_shoveling", "shovel_rigid", "shovel_side_rigid"]:
			if name in path:
				forbidden.append(path)
	var has_character := ResourceLoader.exists("res://assets/art/caretaker_32_v05.png")
	var has_endings := ResourceLoader.exists("res://assets/art/endings_16_v011.png")
	var has_timeout := ResourceLoader.exists("res://assets/art/santa_fall_16_v012.png") and ResourceLoader.exists("res://assets/art/cottage_interior_v012.png")
	var has_doors := ResourceLoader.exists("res://assets/art/door_plain_v014.png") and ResourceLoader.exists("res://assets/art/door_wreath_v014.png")
	var has_hits := ResourceLoader.exists("res://assets/art/caretaker_hit_9_v015.png")
	var icicle_metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/icicle_atlas_v017.json"))
	var has_icicles: bool = ResourceLoader.exists("res://assets/art/icicle_atlas_v017.png") and icicle_metadata is Dictionary and icicle_metadata.get("frames",[]).size() == 16
	var has_screen_controls := ResourceLoader.exists("res://scripts/screen_steering.gd")
	var music_ids := ["jingle_bells","blue_ska","sunday_dub","no_frills_comparsa","peppy_pepe","bama_country"]
	var has_soundtrack := true
	var music_levels: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/music/playback_levels.json"))
	for id in music_ids:
		has_soundtrack = has_soundtrack and ResourceLoader.exists("res://assets/audio/music/" + id + ".mp3") and music_levels is Dictionary and music_levels.get("tracks",{}).has(id)
	var has_result_sounds := ResourceLoader.exists("res://assets/audio/click.ogg") and ResourceLoader.exists("res://assets/audio/win.ogg") and ResourceLoader.exists("res://assets/audio/lose.ogg")
	var music_credits := FileAccess.get_file_as_string("res://assets/licenses/MUSIC_CREDITS.txt")
	var has_music_credits := music_credits.contains("Kevin MacLeod") and not music_credits.contains("SOUND EFFECTS") and FileAccess.file_exists("res://assets/licenses/CC-BY-4.0.txt")
	var sound_credits := FileAccess.get_file_as_string("res://assets/licenses/SOUND_CREDITS.txt")
	var has_sound_credits := sound_credits.contains("complex_waveform") and sound_credits.contains("FunWithSound") and sound_credits.contains("TaranP") and FileAccess.file_exists("res://assets/licenses/CC0-1.0.txt")
	var obsolete_audio_absent := not ResourceLoader.exists("res://assets/audio/winter.wav") and not ResourceLoader.exists("res://assets/audio/click.wav")
	var superseded_doors := ResourceLoader.exists("res://assets/art/door_leaves_v013.png")
	var localization: RefCounted = load("res://scripts/game_localization.gd").new()
	var has_localization: bool = localization.languages.size() == 56 and not localization.english.is_empty()
	for entry in localization.languages:
		var catalog: Dictionary = localization.read_catalog("res://localization/translations/" + entry.code + ".json")
		has_localization = has_localization and catalog.size() == localization.english.size()
	var has_language_fonts := true
	for name in localization.FONT_NAMES:
		has_language_fonts = has_language_fonts and ResourceLoader.exists("res://assets/fonts/" + name + ".ttf") and FileAccess.file_exists("res://assets/fonts/" + name + "-LICENSE.txt")
	var has_display_fonts := ResourceLoader.exists("res://assets/fonts/MPLUSRounded1c-Black.ttf") and ResourceLoader.exists("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf") and FileAccess.file_exists("res://assets/fonts/MPLUSRounded1c-LICENSE.txt")
	var old_display_absent := not ResourceLoader.exists("res://assets/fonts/LilitaOne.ttf")
	localization.dispose()
	var tuning: RefCounted = load("res://scripts/game_settings.gd").new()
	var tuning_file_absent := not FileAccess.file_exists("res://game_settings.cfg")
	var has_tuning: bool = tuning_file_absent and tuning.player_speed_multiplier == 1.75 and tuning.idle_animation_multiplier == 1.0 and tuning.snow_per_scoop == 255 and tuning.hit_recovery_seconds == 6.0
	var difficulty_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/difficulty/presets.json"))
	var has_difficulty := difficulty_data is Dictionary and difficulty_data.get("presets") is Dictionary
	for id in ["easy","medium","hard","extreme"]:
		has_difficulty = has_difficulty and difficulty_data.presets.has(id)
	var has_privacy := FileAccess.file_exists("res://assets/licenses/PRIVACY_POLICY.txt") and ResourceLoader.exists("res://assets/art/menu_icons/privacy.svg")
	var has_branding := ResourceLoader.exists("res://assets/art/title_logo_big_snow_shift_v0301.png") and not ResourceLoader.exists("res://assets/art/title_logo_snow_patrol_v020.png")
	var policy_text := FileAccess.get_file_as_string("res://assets/licenses/PRIVACY_POLICY.txt")
	has_branding = has_branding and policy_text.contains("Big Snow Shift") and not policy_text.contains("Xmas Snow Patrol")
	var passed := has_privacy and forbidden.is_empty() and has_character and has_endings and has_timeout and has_doors and has_hits and has_icicles and has_screen_controls and has_soundtrack and has_result_sounds and has_music_credits and obsolete_audio_absent and has_tuning and not superseded_doors and has_localization and has_language_fonts and has_display_fonts and old_display_absent
	var report := {"passed":passed, "offline_privacy_present":has_privacy, "file_count":files.size(), "new_character_present":has_character, "ending_sprites_present":has_endings, "timeout_art_present":has_timeout, "hit_sprites_present":has_hits, "painted_icicles_present":has_icicles, "screen_controls_present":has_screen_controls, "soundtrack_present":has_soundtrack, "distinct_gameplay_tracks":5, "original_ogg_effects_present":has_result_sounds, "music_credits_and_license_present":has_music_credits, "obsolete_audio_absent":obsolete_audio_absent, "arched_door_art_present":has_doors, "separate_wreath_present":ResourceLoader.exists("res://assets/art/door_wreath_v014.png"), "superseded_door_art_present":superseded_doors, "forbidden_paths":forbidden, "built_in_player_defaults":has_tuning, "external_tuning_file_absent":tuning_file_absent, "bundled_speed":tuning.player_speed_multiplier, "idle_animation_multiplier":tuning.idle_animation_multiplier, "snow_per_scoop":tuning.snow_per_scoop,"hit_recovery_seconds":tuning.hit_recovery_seconds}
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	var expected_image_sizes := {"door_wreath_v014.png":Vector2(512,493),"cottage_interior_v012.png":Vector2(1024,1024),"icon_caretaker_tree_v019.png":Vector2(512,512)}
	var optimized_images := true
	for name in expected_image_sizes:
		var texture: Texture2D = load("res://assets/art/" + name)
		optimized_images = optimized_images and texture != null and texture.get_size() == expected_image_sizes[name]
	passed = passed and optimized_images
	report["optimized_image_dimensions"] = optimized_images
	passed = passed and has_difficulty and has_sound_credits and has_branding
	report["new_branding_and_retired_logo_absent"] = has_branding
	report["sound_credits_and_cc0_present"] = has_sound_credits
	report["passed"] = passed
	report["difficulty_presets_present"] = has_difficulty
	report["localization_catalogs"] = localization.languages.size() if has_localization else 0
	report["language_fonts_and_licenses_present"] = has_language_fonts
	report["rounded_display_fonts_and_license_present"] = has_display_fonts
	report["retired_lilita_font_absent"] = old_display_absent
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print(JSON.stringify(report))
	quit(0 if passed else 1)
