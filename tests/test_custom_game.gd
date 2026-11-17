extends SceneTree

var checks := 0
var failures: Array[String] = []
const OUTPUT := "res://builds/custom-game/"
const OFF := {"no_time_limit":false,"no_icicles":false}
const ON := {"no_time_limit":true,"no_icicles":true}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for id in DifficultyRules.IDS:
		var model := GameModel.new(GameSettings.new())
		model.start(91,id,ON)
		check(model.game_mode == "standard" and model.assists == OFF and model.score_category() == "standard",id+" rejects stale Custom switches at the model boundary")
		check(DifficultyRules.equivalent(model.rules_snapshot(),DifficultyRules.standard(id)),id+" retains exact preset parameters")
		for mask in 4:
			var options := {"no_time_limit":bool(mask & 1),"no_icicles":bool(mask & 2)}
			model.start(91,id,options,"custom")
			check(model.game_mode == "custom" and model.assists == options and model.score_category() == "personal",id+" Custom identity with switch combination "+str(mask))
			var initial_time := model.time_left
			model.spawn_hazard()
			check(model.hazards.is_empty() == options.no_icicles,"Custom icicle switch controls spawning")
			model.step(.1,Vector2.RIGHT)
			check(is_equal_approx(model.time_left,initial_time if options.no_time_limit else initial_time-.1),"Custom timer switch controls countdown")
			var snapshot: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
			var restored := GameModel.new(GameSettings.new())
			check(restored.restore(snapshot) and restored.game_mode == "custom" and restored.assists == options and restored.snow.cells == model.snow.cells and restored.player.is_equal_approx(model.player),"Custom JSON Continue preserves identity, switches and progress")
			check(restored.score_category() == "personal","Custom with switches off cannot enter a preset board after Continue")
		model.start(92,id,ON,"standard")
		check(model.game_mode == "standard" and model.assists == OFF and model.score_category() == "standard","a new preset game has independent fixed rules and record eligibility")
	test_migration()
	test_records()
	test_editor_parameters()
	var result := {"checks":checks,"failures":failures}
	FileAccess.open(OUTPUT+"tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func test_migration() -> void:
	var model := GameModel.new(GameSettings.new())
	model.start(71,"extreme",ON,"custom")
	model.time_left = 97
	model.score = 1234
	model.snow.brush(Vector2(.5,.5),Vector2(.2,.1),255)
	var old := model.snapshot()
	old.erase("game_mode")
	old.erase("custom_parameters")
	var restored := GameModel.new(GameSettings.new())
	check(restored.restore(old) and restored.game_mode == "custom" and restored.time_left == 97 and restored.score == 1234 and restored.snow.cells == model.snow.cells,"0.24 assisted run migrates to Custom without progress loss")
	check(restored.assists == ON and restored.score_category() == "personal","migration keeps both old switches")
	model.start(71,"medium")
	old = model.snapshot()
	old.erase("game_mode")
	check(restored.restore(old) and restored.game_mode == "standard" and restored.score_category() == "standard","0.24 ordinary run stays on its preset board")
	old.game_mode = "invalid"
	check(not restored.restore(old),"invalid mode rejected")
	old.game_mode = "standard"
	old.assists = ON
	check(not restored.restore(old),"new format rejects contradictory preset and help switches")
	var tuning := GameSettings.new()
	tuning.player_speed_multiplier = 2
	var tuned := GameModel.new(tuning)
	tuned.start(1,"hard")
	check(tuned.game_mode == "custom" and tuned.settings.player_speed_multiplier == 2,"developer speed overrides remain usable with Custom identity")
	tuning = GameSettings.new()
	tuning.idle_animation_multiplier = 2
	tuned = GameModel.new(tuning)
	tuned.start(1,"hard")
	check(tuned.game_mode == "standard","idle animation alone is cosmetic")
	var path := OUTPUT+"profile.json"
	var previous := {"version":2,"settings":{"difficulty":"extreme","assists":ON,"music":.2,"language":"ru-RU"},"run":model.snapshot(),"scores":[{"name":"Kid","score":1234,"difficulty":"hard","category":"standard","balance":model.balance_version}],"badges":["hard"]}
	PlayerProfile.write_document(ProjectSettings.globalize_path(path),previous)
	var profile := PlayerProfile.new()
	profile.path = path
	profile.load_profile()
	var previous_parameters: Dictionary = DifficultyRules.catalog().presets.extreme.merged({"landing_warnings":true},true)
	check(profile.settings.game_mode == "custom" and profile.settings.custom_parameters == previous_parameters and profile.settings.custom_assists == ON,"version 2 preferences migrate to adjustable Custom parameters")
	check(profile.settings.difficulty == "extreme" and profile.settings.music == .2 and profile.settings.language == "ru-RU" and profile.active_run.id == model.run_id,"migration preserves preset preference, audio, language and saved run")
	profile.settings.game_mode = "standard"
	profile.settings.difficulty = "easy"
	check(profile.save(),"version 3 saves successfully")
	profile.shutdown()
	profile = PlayerProfile.new()
	profile.path = path
	profile.load_profile()
	check(profile.document().version == 5 and not profile.settings.has("assists") and not profile.settings.has("custom_difficulty"),"retired global switches and Custom difficulty removed from new profile")
	check(profile.settings.game_mode == "standard" and profile.settings.difficulty == "easy" and profile.settings.custom_parameters == previous_parameters and profile.settings.custom_assists == ON,"independent preset and Custom preferences survive reload")
	check(profile.scores_for("hard").size() == 1 and profile.badges == ["hard"],"upgrade retains existing scores and badges")
	profile.shutdown()

func test_editor_parameters() -> void:
	var custom := {"extra_seconds":210.0,"interval_multiplier":3.0,"extra_warning":2.0,"deposit_multiplier":1.5,"target_bias":.25,"first_spawn":12.0,"recovery_multiplier":.5,"grace":5.0}
	var game := GameModel.new(GameSettings.new())
	game.start(51,"hard",OFF,"custom",custom)
	check(game.time_left == 630 and is_equal_approx(game.stage().hazard_interval,15.6) and game.stage().warning == 4 and is_equal_approx(game.stage().deposition,.675),"editor parameters control round deadline, spawning, warning and snow deposits")
	check(game.target_bias == .25 and game.spawn_countdown == 12 and game.grace_seconds == 5 and game.settings.hit_recovery_seconds == 3,"editor parameters control aiming, first icicle and hit recovery/protection")
	for i in 3:
		game.begin_round(i)
		check(game.time_left == 630+i*90 and is_equal_approx(game.stage().hazard_interval,game.base_stages[i].hazard_interval*3),"Custom applies parameters to each round")
	game.begin_round(0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.snapshot()))
	var restored := GameModel.new(GameSettings.new())
	check(restored.restore(saved) and DifficultyRules.equivalent(restored.custom_parameters,custom) and DifficultyRules.equivalent(restored.rules_snapshot(),game.rules_snapshot()),"custom parameters and effective rules survive JSON Continue")
	var rules := restored.rules_snapshot()
	custom.extra_seconds = 240
	custom.landing_warnings = false
	check(restored.time_left == 630 and restored.rules_snapshot() == rules and restored.custom_parameters.extra_seconds == 210,"editing a separate Custom draft cannot alter a running game")
	for index in 3:
		restored.begin_round(index)
		check(restored.rules_snapshot() == rules and restored.time_left == rules.stages[index].seconds,"Custom retries keep every original parameter")
	var player := DifficultyRules.player_values(GameSettings.new())
	var clamped := custom.duplicate()
	clamped.recovery_multiplier = .1
	check(CustomRules.adjusted(clamped,"recovery_multiplier",-1,player) == .1,"imported recovery below one second has no invisible decrease step")
	clamped.recovery_multiplier = 2
	check(CustomRules.adjusted(clamped,"recovery_multiplier",1,player) == 2,"imported recovery above ten seconds has no invisible increase step")
	for field in CustomRules.FIELDS:
		var key: String = field[0]
		var values := DifficultyRules.custom_defaults()
		for i in 1000: values[key] = CustomRules.adjusted(values,key,1,player)
		check(DifficultyRules.valid_parameters(values) and is_equal_approx(CustomRules.adjusted(values,key,1,player),values[key]),"upper bound clamps "+key)
		for i in 1000: values[key] = CustomRules.adjusted(values,key,-1,player)
		check(DifficultyRules.valid_parameters(values) and is_equal_approx(CustomRules.adjusted(values,key,-1,player),values[key]),"lower bound clamps "+key)
		var broken := saved.duplicate(true)
		broken.custom_parameters[key] = INF
		check(not restored.restore(broken),"invalid saved parameter rejected: "+key)
	var old_profile_path := OUTPUT+"version3-profile.json"
	var old_profile := {"version":3,"settings":{"game_mode":"custom","custom_difficulty":"medium","custom_assists":ON},"run":saved,"scores":[]}
	PlayerProfile.write_document(ProjectSettings.globalize_path(old_profile_path),old_profile)
	var profile := PlayerProfile.new()
	profile.path = old_profile_path
	profile.load_profile()
	check(DifficultyRules.equivalent(profile.settings.custom_parameters,DifficultyRules.catalog().presets.medium) and profile.settings.custom_assists == ON,"0.25 preferences migrate from named base to its parameter values")
	profile.settings.custom_parameters = custom.duplicate()
	profile.save()
	profile.shutdown()
	profile = PlayerProfile.new()
	profile.path = old_profile_path
	profile.load_profile()
	check(DifficultyRules.equivalent(profile.settings.custom_parameters,custom),"edited parameter preferences survive profile reload")
	profile.shutdown()
	for id in DifficultyRules.IDS:
		game.start(51,id,ON,"custom")
		var previous := game.snapshot()
		previous.erase("custom_parameters")
		check(restored.restore(previous) and DifficultyRules.equivalent(restored.custom_parameters,previous.rule_catalog.presets[id]) and DifficultyRules.equivalent(restored.rules_snapshot(),game.rules_snapshot()),"0.25 Custom save retains exact "+id+" values without showing a base selector")
	game.start(51,"hard",ON,"standard",custom)
	check(game.custom_parameters.is_empty() and game.assists == OFF and DifficultyRules.matches_standard(game.rules_snapshot()),"Custom numeric settings cannot leak into a fixed preset")

func test_records() -> void:
	var profile := PlayerProfile.new()
	profile.path = OUTPUT+"scores.json"
	for id in ["hard","extreme"]:
		var model := GameModel.new(GameSettings.new())
		model.start(2,id,OFF,"custom")
		model.state = "won"
		model.score = 20000
		model.run_id = "custom-"+id
		check(profile.submit(model,"Kid"),"Custom completion saved")
		check(profile.scores_for(id).is_empty() and profile.badges.is_empty() and not profile.last_was_best,"Custom without help never earns preset records or badges")
	profile.shutdown()
	profile = PlayerProfile.new()
	profile.path = OUTPUT+"scores.json"
	profile.load_profile()
	check(profile.scores_for("personal").size() == 2 and profile.scores_for("personal")[0].game_mode == "custom","Custom score identity persists after reload")
	profile.shutdown()
