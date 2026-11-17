extends SceneTree

var checks := 0
var failures: Array[String] = []
const OUTPUT := "res://builds/difficulty/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func game(id: String, selected_assists: Dictionary = {"no_time_limit":false,"no_icicles":false}) -> GameModel:
	var model := GameModel.new(GameSettings.new())
	model.start(42,id,selected_assists)
	return model

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var catalog := DifficultyRules.catalog()
	check(DifficultyRules.valid_catalog(catalog),"shipped catalog is valid")
	var expected := {"easy":[540,2.2,3,2,3,8],"medium":[480,1.45,2.5,3.5,2.4,5],"hard":[420,1,2,6,1.8,2.5],"extreme":[420,.9,2,6,1.8,2.5]}
	for id in DifficultyRules.IDS:
		var model := game(id)
		var values: Array = expected[id]
		check(model.time_left == values[0] and is_equal_approx(model.stage().hazard_interval,5.2*values[1]) and model.stage().warning == values[2],id+" deadline and hazard rules")
		check(is_equal_approx(model.settings.hit_recovery_seconds,values[3]) and model.grace_seconds == values[4] and model.spawn_countdown == values[5],id+" recovery, protection and starting grace")
		check(model.settings.player_speed_multiplier == 1.75 and model.settings.idle_animation_multiplier == 1 and model.settings.snow_per_scoop == 255,id+" preserves movement, idle and scoops")
		check(model.score_category() == "standard",id+" is eligible for its own board")
		for round_index in 3:
			model.begin_round(round_index)
			check(model.time_left == values[0]+90*round_index,id+" all three round deadlines")
			check(model.snow.cells.count(0) == 0,id+" full-width starting snow")
		model.begin_round(0)
		model.apply_hit()
		var start_time := model.time_left
		check(is_equal_approx(model.stun,values[3]) and is_equal_approx(model.immunity,values[3]+values[4]),id+" hit duration")
		model.spawn_countdown = 50
		for tick in int(values[3]*20): model.step(.05,Vector2.ZERO)
		check(model.stun == 0 and is_equal_approx(model.time_left,start_time-values[3]),id+" recovery costs countdown time only")
		model.spawn_countdown = 13.2
		model.spawn_hazard()
		var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
		var restored := game("hard")
		check(restored.restore(saved),id+" JSON restore")
		check(restored.score_category() == "standard",id+" JSON round trip retains preset-board eligibility")
		check(restored.difficulty_id == id and is_equal_approx(restored.time_left,model.time_left) and is_equal_approx(restored.spawn_countdown,13.2) and is_equal_approx(restored.settings.hit_recovery_seconds,model.settings.hit_recovery_seconds),id+" restore does not clamp to old Hard limits")
		model.paused = false
		restored.paused = false
		for tick in 180:
			model.step(1.0/60,Vector2.RIGHT)
			restored.step(1.0/60,Vector2.RIGHT)
		var same_hazards := model.hazards.size() == restored.hazards.size()
		if same_hazards:
			for i in model.hazards.size():
				for key in model.hazards[i]: same_hazards = same_hazards and is_equal_approx(model.hazards[i][key],restored.hazards[i][key])
		check(model.snow.cells == restored.snow.cells and model.snow.piles == restored.snow.piles and model.player.is_equal_approx(restored.player) and is_equal_approx(model.time_left,restored.time_left) and model.rng.state == restored.rng.state and same_hazards,id+" deterministic continue through impacts and digging")
		# All presets keep the same Santa reward sequence and complete-game score.
		for round_index in 3:
			model.begin_round(round_index)
			model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,255)
			model.step(.01,Vector2.ZERO)
			check(model.state == "returning" and model.hazards.is_empty(),id+" hazards stop before Santa")
			model.player = RoundEnding.DOOR_TARGET
			model.step(.01,Vector2.ZERO)
			for tick in 200: model.step(.1,Vector2.ZERO)
			check(model.state == ("won" if round_index == 2 else "celebrating"),id+" Santa ending round "+str(round_index+1))
			model.next_round()
	test_locked_rules()
	test_saves()
	test_scores()
	var report := {"checks":checks,"failures":failures}
	FileAccess.open(OUTPUT+"rules-tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_locked_rules() -> void:
	for id in DifficultyRules.IDS:
		var model := game(id)
		var rules := model.rules_snapshot()
		var run_id := model.run_id
		check(not model.has_method("change_difficulty"),"no runtime rule-changing API")
		# Editing the catalogue for a future game cannot retune this one.
		model.difficulty_config.presets[id].extra_seconds = 1000
		for round_index in 3:
			model.begin_round(round_index)
			model.score = 777
			model.begin_timeout()
			model.begin_round(round_index)
			check(model.rules_snapshot() == rules and model.run_id == run_id and model.score == 777,id+" retry preserves selected rules, identity and earlier score")
			check(model.time_left == rules.stages[round_index].seconds,id+" retry uses the original deadline")
			model.state = "won" if round_index == 2 else "celebrating"
			model.next_round()
			check(model.rules_snapshot() == rules,id+" next round retains the same rules")
		var restored := game("hard")
		check(restored.restore(model.snapshot()) and restored.rules_snapshot() == rules,id+" Continue ignores changed catalogue values")
	var model := GameModel.new(GameSettings.new())
	model.start(42,"easy",{"no_time_limit":true,"no_icicles":true},"custom")
	var initial_time := model.time_left
	for tick in 200: model.step(.1,Vector2.RIGHT)
	check(model.time_left == initial_time and model.hazards.is_empty(),"preselected Custom switches apply for the entire round")
	model.state = "greeting"
	model.finish_round()
	check(model.last_reward == int(model.stage().reward) + 300,"untimed rounds award only the round reward and no-hit bonus")

func test_saves() -> void:
	var model := game("easy")
	var snapshot := model.snapshot()
	var retuned := GameSettings.new()
	retuned.player_speed_multiplier = 2.5
	retuned.hit_recovery_seconds = 9
	var restored := GameModel.new(retuned)
	check(restored.restore(snapshot) and restored.settings.player_speed_multiplier == 1.75 and restored.settings.hit_recovery_seconds == 2,"Continue uses saved tuning instead of current development overrides")
	model.settings.player_speed_multiplier = 2
	check(model.score_category() == "personal","developer gameplay overrides have separate records")
	model = game("hard")
	model.settings.idle_animation_multiplier = 2
	check(model.score_category() == "standard","cosmetic idle changes do not invalidate records")
	var legacy := model.snapshot()
	for key in ["rules","rule_catalog","base_stages","development_player","time_allowance","assists","adjusted_run","legacy_run","failed_attempts"]: legacy.erase(key)
	check(restored.restore(legacy) and restored.difficulty_id == "hard" and restored.score_category() == "previous","pre-difficulty saved games remain playable and separately labeled")
	legacy = model.snapshot()
	legacy.adjusted_run = true
	legacy.time_allowance = 540
	legacy.time = 320
	check(restored.restore(legacy) and restored.score_category() == "personal" and restored.time_left == 320,"older adjusted runs keep their rules, remaining time and personal classification")
	for key in ["rules","rule_catalog","base_stages","development_player","assists"]:
		var broken := snapshot.duplicate(true)
		broken[key] = "invalid"
		check(not restored.restore(broken),"invalid saved "+key+" rejected")
	var broken := snapshot.duplicate(true)
	broken.rules.player.speed = INF
	check(not restored.restore(broken),"nonfinite saved player rules rejected")
	broken = snapshot.duplicate(true)
	broken.rules.stages[0].seconds = -10
	check(not restored.restore(broken),"invalid saved deadline rejected")
	broken = snapshot.duplicate(true)
	broken.rules.version = "older-rules"
	check(restored.restore(broken) and restored.score_category() == "previous","earlier valid balance remains resumable with archived records")

func test_scores() -> void:
	var path := OUTPUT+"migration-profile.json"
	var old := {"version":1,"settings":{"music":.2,"language":"ru-RU","control_mode":"pad"},"scores":[{"name":"Family","score":1234}],"run":game("hard").snapshot(),"name":"Family","submitted":[]}
	PlayerProfile.write_document(ProjectSettings.globalize_path(path),old)
	var profile := PlayerProfile.new()
	profile.path = path
	profile.load_profile()
	check(profile.settings.difficulty == "easy" and profile.settings.music == .2 and profile.settings.language == "ru-RU" and profile.settings.control_mode == "pad","migration preserves preferences and starts new games on Easy")
	check(profile.scores_for("previous").size() == 1 and profile.scores_for("hard").is_empty() and not profile.active_run.is_empty(),"legacy score archived and active save preserved")
	check(profile.save(),"migrated profile writes atomically")
	for id in DifficultyRules.IDS:
		for i in 12:
			var model := game(id)
			model.run_id = id+"-"+str(i)
			model.state = "won"
			model.score = 1000+i*10
			check(profile.submit(model,"Player"),id+" score saved "+str(i))
			check(not profile.submit(model,"Player"),"duplicate score blocked")
		var entries := profile.scores_for(id)
		check(entries.size() == 10 and entries[0].score == 1110 and entries[9].score == 1020,id+" independently keeps its ten best")
	check(profile.scores.size() == 41 and profile.badges.has("hard") and profile.badges.has("extreme"),"all four boards and old scores survive; challenge badges persist")
	var personal := game("hard")
	var historical := personal.snapshot()
	historical.adjusted_run = true
	check(personal.restore(historical),"load a historical adjusted game for score migration")
	personal.state = "won"
	personal.run_id = "adjusted"
	check(profile.submit(personal,"Family") and profile.scores_for("personal").size() == 1 and not profile.last_was_best,"adjusted completion saved positively outside preset lists")
	var older := game("easy")
	older.legacy_run = true
	older.state = "won"
	older.run_id = "continued-legacy"
	check(profile.submit(older,"Returning player") and profile.scores_for("personal").size() == 2,"finishing an older saved game produces a visible personal result")
	check(profile.scores_for("easy").size() == 10 and profile.scores_for("previous").size() == 1 and not profile.last_was_best,"legacy completion preserves archives and current difficulty records")
	profile.shutdown()
	var loaded := PlayerProfile.new()
	loaded.path = path
	loaded.load_profile()
	for id in DifficultyRules.IDS: check(loaded.scores_for(id).size() == 10,"reload keeps entire "+id+" board")
	check(loaded.badges.size() == 2 and loaded.scores_for("previous").size() == 1,"reload keeps badges and legacy score")
	loaded.shutdown()
