extends SceneTree

var checks := 0
var failures: Array[String] = []
const OFF := {"no_time_limit":false,"no_icicles":false}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func _initialize() -> void:
	for id in DifficultyRules.IDS:
		var game := GameModel.new(GameSettings.new())
		game.start(42,id)
		for round_index in 3:
			game.begin_round(round_index)
			check(game.landing_warnings == (id != "extreme"),id+" warning visibility in round "+str(round_index+1))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(game.snapshot()))
		var restored := GameModel.new(GameSettings.new())
		check(restored.restore(saved) and restored.landing_warnings == game.landing_warnings and restored.score_category() == "standard",id+" Continue keeps warnings and board eligibility")
		# Actual pre-toggle schema: every mode had markers, including Extreme.
		saved.rules.erase("landing_warnings")
		saved.rules.version = "big-snow-shift-1"
		saved.rule_catalog.erase("preset_versions")
		for preset in saved.rule_catalog.presets.values(): preset.erase("landing_warnings")
		check(restored.restore(saved) and restored.landing_warnings and restored.game_mode == "standard",id+" older save keeps its visible warnings")
		check(restored.score_category() == ("previous" if id == "extreme" else "standard"),id+" older records classified without resetting other difficulties")
		var profile := PlayerProfile.new()
		profile.scores = [{"name":"Family","score":1234,"difficulty":id,"category":"standard","balance":"big-snow-shift-1"}]
		check(profile.scores_for("previous" if id == "extreme" else id).size() == 1,id+" historical leaderboard is retained")
		profile.shutdown()
	var parameters := DifficultyRules.custom_defaults()
	var visible := GameModel.new(GameSettings.new())
	visible.start(72,"hard",OFF,"custom",parameters)
	parameters.landing_warnings = false
	var hidden := GameModel.new(GameSettings.new())
	hidden.start(72,"hard",OFF,"custom",parameters)
	check(not hidden.landing_warnings,"Custom can hide markers")
	for tick in 1000:
		visible.step(.02,Vector2.RIGHT)
		hidden.step(.02,Vector2.RIGHT)
	check(visible.hazards == hidden.hazards and visible.total_hits == hidden.total_hits and visible.time_left == hidden.time_left and visible.snow.cells == hidden.snow.cells and visible.player == hidden.player,"warning visibility leaves spawn, fall, hit, snow and movement mechanics identical")
	var restored := GameModel.new(GameSettings.new())
	check(restored.restore(JSON.parse_string(JSON.stringify(hidden.snapshot()))) and not restored.landing_warnings and restored.custom_parameters.landing_warnings == false,"Custom hidden markers survive Continue")
	var hazards := restored.hazards.duplicate(true)
	var snow := restored.snow.cells.duplicate()
	parameters.landing_warnings = true
	check(not restored.landing_warnings and restored.hazards == hazards and restored.snow.cells == snow,"editing a new draft cannot toggle an existing game's markers")
	check(restored.score_category() == "personal","Custom visibility changes never enter preset boards")
	for invalid in [0,"false",null]:
		parameters.landing_warnings = invalid
		check(not DifficultyRules.valid_parameters(parameters),"non-boolean warning choice rejected")
	var legacy := visible.snapshot()
	legacy.rules.erase("landing_warnings")
	legacy.custom_parameters.erase("landing_warnings")
	check(restored.restore(legacy) and restored.landing_warnings,"older Custom snapshot defaults to warnings on")
	var report := {"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/landing-warnings"))
	FileAccess.open("res://builds/landing-warnings/tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
