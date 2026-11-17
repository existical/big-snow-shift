extends SceneTree
## Custom length changes completion and presentation, never preset balance.
const OUTPUT := "res://builds/round-count/"
const OFF := {"no_time_limit":false,"no_icicles":false}
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func _initialize() -> void:
	run.call_deferred()

func copy_run(model: GameModel) -> GameModel:
	var restored := GameModel.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(model.snapshot()))),"JSON snapshot restores "+model.state+" with "+str(model.round_count)+" rounds")
	check(restored.round_count == model.round_count and restored.stage_index == model.stage_index and restored.ending_index() == model.ending_index() and restored.snow.cells == model.snow.cells and DifficultyRules.equivalent(restored.rules_snapshot(),model.rules_snapshot()),"Continue preserves length, stage, ending, snow and captured rules")
	return restored

func greeting(model: GameModel) -> void:
	model.paused = false
	model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,765)
	model.step(.01,Vector2.ZERO)
	check(model.state == "returning" and model.hazards.is_empty(),"clearing stops hazards before the mapped ending")
	copy_run(model)
	model.player = Vector2(.5,.025)
	model.step(.01,Vector2.ZERO)
	check(model.state == "greeting", "reaching the door begins the mapped ending")

func test_progression() -> void:
	for id in DifficultyRules.IDS:
		var model := GameModel.new()
		model.start(71,id,OFF,"standard",{},1)
		check(model.round_count == 3 and DifficultyRules.equivalent(model.rules_snapshot(),DifficultyRules.standard(id)) and model.score_category() == "standard",id+" ignores stale Custom count and retains exact standard rules")
	for count in [1,2,3]:
		for mask in 4:
			var model := GameModel.new()
			var assists := {"no_time_limit":bool(mask&1),"no_icicles":bool(mask&2)}
			model.start(71,"hard",assists,"custom",DifficultyRules.custom_defaults(),count)
			check(model.round_count == count and model.stages.size() == 3 and model.score_category() == "personal","Custom length keeps all gameplay definitions and remains unranked")
			var events: Array[bool] = []
			var trees: Array[bool] = []
			model.round_completed.connect(func(final_round: bool): events.append(final_round))
			model.tree_revealed.connect(func(): trees.append(true))
			for index in count:
				check(model.stage_index == index and model.stage() == model.stages[index],"short games use the first gameplay rounds in order")
				check(model.ending_index() == [[2],[1,2],[0,1,2]][count-1][index],"Custom success sequence matches the agreed rewards")
				var reward := model.score + int(model.stage().reward) + (0 if assists.no_time_limit else int(ceil(model.time_left-.01))*10) + 300
				greeting(model)
				var restored := copy_run(model)
				check(restored.paused,"Continue pauses the scene")
				for seconds in [0.0,.6,1.35,2.8,4.0,RoundEnding.duration(model.ending_index())-.01]:
					model.ending_time = seconds
					copy_run(model)
				model.ending_time = 0
				for tick in 80: model.step(.1,Vector2.LEFT)
				check(model.state == ("won" if index == count-1 else "celebrating") and events.size() == index+1 and events[-1] == (index == count-1),"completion occurs once after the full selected ending")
				check(model.score == reward,"completion rewards use the gameplay round, including untimed/no-hit rules")
				check(trees.size() == (1 if index == count-1 else 0),"tree reveal occurs once in the selected final round")
				if model.state == "celebrating": copy_run(model)
				var score := model.score
				for tick in 5: model.step(.1,Vector2.ZERO)
				model.finish_round()
				check(model.score == score,"a completed animation cannot duplicate its reward")
				model.next_round()
			check(model.state == "won" and model.stage_index == count-1,"Next cannot create a phantom round after victory")
			model.start(72,"medium")
			check(model.round_count == 3 and model.ending_index() == 0 and model.stages.size() == 3,"reused short-game model starts a complete preset game")

func test_validation_and_phases() -> void:
	var model := GameModel.new()
	model.start(1,"hard",OFF,"custom",{},2)
	model.begin_round(1)
	model.apply_hit()
	var restored := copy_run(model)
	check(restored.stun == model.stun and restored.time_left == model.time_left,"hit reaction and countdown survive short-game Continue")
	model.begin_timeout()
	model.step(.1,Vector2.ZERO)
	restored = copy_run(model)
	check(restored.failure_time == model.failure_time and restored.is_timeout_scene(),"short games retain the independent Santa slip scene")
	model.begin_round(model.stage_index)
	check(model.round_count == 2 and model.stage_index == 1 and model.state == "playing","retry retains the selected length and gameplay stage")
	var saved := model.snapshot()
	for value in [0,4,1.5,"2",true,INF,NAN]:
		var broken := saved.duplicate(true)
		broken.round_count = value
		check(not DifficultyRules.valid_round_count(value) and not restored.restore(broken),"invalid count is rejected: "+str(value))
	for value in [-1,2,1.5]:
		var broken := saved.duplicate(true)
		broken.stage = value
		check(not restored.restore(broken),"stage outside selected game rejected: "+str(value))
	var broken := saved.duplicate(true)
	broken.game_mode = "standard"
	check(not restored.restore(broken),"short standard snapshot cannot enter preset records")
	broken = saved.duplicate(true)
	broken.state = "celebrating"
	check(not restored.restore(broken),"final selected round cannot retain a Next-round state")
	model.start(2,"hard",OFF,"custom",{},1)
	greeting(model)
	model.ending_time = 6.8
	restored = copy_run(model)
	check(restored.ending_time == 6.8 and restored.ending_index() == 2,"one-round Continue accepts the full 7.2-second tree scene")
	broken = model.snapshot()
	broken.ending_time = 7.3
	check(not restored.restore(broken),"scene time beyond the actual ending is rejected")
	model.start(3,"hard")
	model.begin_round(1)
	saved = model.snapshot()
	saved.erase("round_count")
	check(restored.restore(saved) and restored.round_count == 3 and restored.stage_index == 1 and restored.score_category() == "standard","older snapshots retain three rounds and preset eligibility")

func test_profiles() -> void:
	var model := GameModel.new()
	model.start(5,"hard",OFF,"custom",{},2)
	for version in [1,2,3,4]:
		var old_run := model.snapshot()
		old_run.erase("round_count")
		var old := {"version":version,"settings":{"language":"ru-RU","music":.2,"difficulty":"hard","game_mode":"custom"},"run":old_run,"name":"Family","badges":["hard"],"scores":[{"name":"Family","score":1234,"difficulty":"hard","category":"personal","game_mode":"custom"}]}
		var path := OUTPUT+"old-"+str(version)+".json"
		PlayerProfile.write_document(ProjectSettings.globalize_path(path),old)
		var profile := PlayerProfile.new()
		profile.path = path
		profile.load_profile()
		check(profile.settings.custom_round_count == 3 and profile.scores[0].round_count == 3 and DifficultyRules.equivalent(profile.active_run,old_run),"profile version "+str(version)+" defaults missing counts without changing its saved run")
		check(profile.settings.language == "ru-RU" and profile.settings.music == .2 and profile.player_name == "Family" and profile.badges == ["hard"],"migration preserves other profile data")
		check(profile.document().version == 5,"new profile uses schema 5")
		profile.shutdown()
	var profile := PlayerProfile.new()
	profile.path = OUTPUT+"new-profile.json"
	profile.settings.custom_round_count = 1
	profile.active_run = model.snapshot() # Preferences differ from the captured run.
	check(profile.save(),"short-game preferences and captured run save")
	profile.shutdown()
	profile = PlayerProfile.new()
	profile.path = OUTPUT+"new-profile.json"
	profile.load_profile()
	var resumed := GameModel.new()
	check(profile.settings.custom_round_count == 1 and resumed.restore(profile.active_run) and resumed.round_count == 2,"loaded preferences cannot replace the running game's count")
	profile.scores.clear()
	for count in [1,2,3]:
		for i in 12:
			profile.scores.append({"name":"Family","score":count*1000+i,"difficulty":"hard","game_mode":"custom","category":"personal","balance":"test","round_count":count})
	profile.trim_scores()
	check(profile.scores.size() == 30,"each Custom length retains its own ten results")
	check(profile.scores_for("hard").is_empty() and profile.scores_for("personal").size() == 30,"all Custom lengths remain outside preset boards")
	var score := {"name":"Family","score":1234,"difficulty":"hard","game_mode":"standard","category":"standard","round_count":1}
	check(PlayerProfile.clean_score(score).is_empty(),"contradictory short standard score is rejected")
	for count in [1,2,3]:
		model.start(11+count,"hard",OFF,"custom",{},count)
		model.run_id = "round-count-result-"+str(count)
		model.begin_round(count-1)
		greeting(model)
		for tick in 80: model.step(.1,Vector2.ZERO)
		check(profile.submit(model,"Family") and not profile.submit(model,"Family"),"short-game score submits exactly once")
		check(profile.scores_for("personal").any(func(entry): return entry.get("id","") == model.run_id and entry.round_count == count),"new result stores the completed Custom length")
	check(profile.badges == [] and profile.active_run.is_empty(),"Custom completions grant no badges and leave no Continue save")
	profile.shutdown()
	profile = PlayerProfile.new()
	profile.path = OUTPUT+"new-profile.json"
	profile.load_profile()
	check(profile.scores_for("personal").size() == 33 and profile.scores.all(func(entry): return DifficultyRules.valid_round_count(entry.round_count)),"round-count result metadata survives disk reload")
	profile.shutdown()
	for invalid in [0,4,1.5,"2",true]:
		var path := OUTPUT+"invalid-preference.json"
		PlayerProfile.write_document(ProjectSettings.globalize_path(path),{"version":5,"settings":{"custom_round_count":invalid},"run":resumed.snapshot()})
		profile = PlayerProfile.new()
		profile.path = path
		profile.load_profile()
		check(profile.settings.custom_round_count == 3 and profile.active_run.round_count == 2,"invalid length preference defaults safely without changing the saved game")
		profile.shutdown()

func test_ui() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.sound.stopped = true
	game.profile.path = OUTPUT+"unused-ui-profile.json"
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.change_language("en",false)
	game.profile.settings.custom_round_count = 3
	for count in [3,1,2]:
		game.model.start(9,"hard",OFF,"custom",{},count)
		game.refresh_hud()
		check(game.round_label.text == "Round 1/"+str(count),"HUD cache refreshes when only total rounds changes")
		greeting(game.model)
		game.refresh_hud()
		check(game.progress_label.text == game.localization.text(["hud.handshake","hud.present","hud.magic"][game.model.ending_index()]),"HUD greeting describes the mapped reward")
		check(game.toast_label.text == game.localization.text(["messages.handshake","messages.present","messages.magic"][game.model.ending_index()]),"toast describes the mapped reward")
		for tick in 80: game.model.step(.1,Vector2.ZERO)
		game.show_result()
		if game.model.state == "won":
			check(game.profile.active_run.is_empty() and not game.active_run,"completed selected length has no Continue save")
		if count == 2:
			check(game.model.state == "celebrating","two-round present result offers its remaining round")
			check(game.overlay.find_children("*","Label",true,false).any(func(node): return node.text == game.localization.text("result.presentMessage")),"two-round intermediate result describes a present and one remaining snowfall")
		game.model.state = "lost"
		game.show_result()
		game.retry_round()
		check(game.model.round_count == count and game.model.stage_index == 0 and game.model.state == "playing","immediate retry preserves short-game length")
	game.profile.active_run = game.model.snapshot()
	game.show_menu()
	game.show_difficulty()
	game.open_custom_game()
	var saved: Dictionary = game.profile.active_run.duplicate(true)
	game.overlay.find_child("CustomRounds_1",true,false).pressed.emit()
	check(game.selected_round_count == 1 and game.profile.settings.custom_round_count == 3 and game.profile.active_run == saved,"round-count selection edits only the future-game draft")
	game.commit_difficulty()
	check(game.view == "confirm" and game.profile.active_run == saved,"short replacement keeps the existing save until confirmation")
	game.continue_night()
	check(game.model.round_count == 2,"cancelling replacement retains the captured count")
	game.show_settings("pause")
	game.show_difficulty()
	check(game.view == "settings" and game.overlay.find_child("CustomRounds_1",true,false) == null,"paused Settings cannot change game length")
	game.profile.settings.custom_round_count = 1
	game.profile.scores = [{"name":"Family","score":1234,"game_mode":"custom","difficulty":"hard","category":"personal","round_count":2}]
	game.show_scores("personal")
	check(game.overlay.find_children("*","Label",true,false).any(func(node): return "Rounds: 2" in node.text),"My results visibly identifies the completed Custom length")
	game.profile.shutdown()
	game.sound.shutdown()
	game.queue_free()
	await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	test_progression()
	test_validation_and_phases()
	test_profiles()
	await test_ui()
	var report := {"checks":checks,"failures":failures}
	FileAccess.open(OUTPUT+"tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
