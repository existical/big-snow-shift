extends SceneTree

var failures: Array[String] = []
var checks := 0
var folder: String

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)

func open_game(filename: String):
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile.path = folder+filename
	game.profile.settings.language = "en"
	game.sound.stopped = true
	root.add_child(game)
	game.set_physics_process(false)
	return game

func label_key(game: Control, key: String) -> bool:
	for node in game.overlay.find_children("*","Label",true,false):
		if node.visible and node.get_meta("translation_key","") == key: return true
	return false

func run() -> void:
	folder = "res://builds/recovery-tests/"+str(Time.get_ticks_usec())+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var game = open_game("storm.json")
	game.show_difficulty()
	game.open_custom_game()
	game.selected_custom_parameters.interval_multiplier = .25
	game.selected_custom_parameters.extra_warning = 10
	game.start_night()
	game.model.begin_round(2)
	for tick in 60*60:
		game.model.step(1.0/60,Vector2.ZERO)
		if game.model.hazards.size() > 12: break
	var count: int = game.model.hazards.size()
	check(count > 12,"fixture produces a legal high-density Custom storm")
	game.show_pause()
	game.show_menu()
	var ages: Array = game.model.hazards.duplicate(true)
	check(game.world.menu_pose and game.model.hazards == ages,"title pose retains the frozen hazards")
	game.free()
	game = open_game("storm.json")
	game.continue_night()
	check(game.view == "pause" and game.model.hazards.size() == count,"cold Continue restores the dense storm")
	var good: Dictionary = game.model.snapshot()
	var bad := good.duplicate(true)
	bad.hazards[0].x = -1
	game.profile.active_run = good
	game.profile.save()
	game.profile.active_run = bad
	game.profile.save()
	game.continue_night()
	check(game.view == "pause" and game.model.hazards[0].x >= 0,"invalid primary restores the matching backup")
	check(PlayerProfile.read_document(game.profile.path).run.hazards[0].x >= 0,"recovered primary is repaired")
	check(PlayerProfile.read_document(game.profile.path+".bak").run.hazards[0].x >= 0,"recovery preserves the valid backup")
	bad.id += "-different"
	game.profile.active_run = bad
	game.profile.save()
	check(not game.profile.restore_active(game.model),"an unrelated backup cannot replace this run")
	game.model.state = "lost"
	game.show_result()
	var path: String = game.profile.path
	FileAccess.open(path,FileAccess.WRITE).store_string("{")
	game.free()
	game = open_game("storm.json")
	check(game.profile.active_run.is_empty() and game.view == "menu","corrupt primary cannot revive a finished loss")
	game.free()

	for count_rounds in [1,2,3]:
		var filename := "win-"+str(count_rounds)+".json"
		game = open_game(filename)
		var mode := "standard" if count_rounds == 3 else "custom"
		game.model.start(25,"hard",{} if mode == "standard" else {"no_time_limit":false,"no_icicles":false},mode,{},count_rounds)
		game.model.begin_round(count_rounds-1)
		game.active_run = true
		game.model.state = "won"
		game.model.score = 4321
		var id: String = game.model.run_id
		game.show_result()
		game.free()
		game = open_game(filename)
		check(game.view == "result" and game.displayed_result.id == id and game.displayed_result.round_count == count_rounds,"cold launch restores the earned result")
		check(game.profile.active_run.is_empty() and label_key(game,"result.name"),"pending win has a visible name label and no playable save")
		check(("hard" in game.profile.badges) == (mode == "standard"),"badges earned at victory use ranked rules")
		game.name_edit.text = "Bolyus"
		game.profile.path = folder+"missing/profile.json"
		game.submit_score()
		check(game.view == "result" and not game.profile.storage_ok and game.name_edit.text == "Bolyus","failed score write remains editable")
		game.handle_back_request()
		check(game.view == "menu" and game.profile.pending_results.size() == 1,"failure allows leaving and deferring the score")
		game.profile.path = folder+filename
		game.show_result(game.profile.pending_results[0])
		game.submit_score()
		check(game.view == "scores" and game.profile.pending_results.is_empty() and not game.profile.submit_pending(id,"Again"),"pending result submits exactly once")
		if mode == "standard":
			check(label_key(game,"scores.best"),"record banner appears on the ranked submission visit")
			game.show_menu()
			game.show_scores("hard")
			check(not label_key(game,"scores.best"),"fresh visit clears the prior submission banner")
		game.free()
		game = open_game(filename)
		check(game.view == "menu" and game.profile.scores.size() == 1,"cold launch after submission keeps a single result")
		game.free()

	game = open_game("cutoff.json")
	game.model.start(22,"easy")
	game.active_run = true
	game.profile.scores = []
	for i in 10:
		game.profile.scores.append({"name":"Friend","score":900+i,"category":"standard","difficulty":"easy","balance":game.model.balance_version})
	game.model.state = "won"
	game.model.score = 100
	game.show_result()
	game.submit_score()
	check(label_key(game,"scores.outside") and game.profile.scores.size() == 10,"eleventh place receives visible feedback with ten retained records")
	game.show_menu()
	game.start_night()
	game.profile.path = folder+"missing/profile.json"
	game.show_pause()
	check(label_key(game,"messages.storageFailed") and not label_key(game,"difficulty.paused"),"failed pause shows the persistent failure message")
	game.profile.path = folder+"cutoff.json"
	game.show_pause()
	game._physics_process(.01)
	check(label_key(game,"difficulty.paused") and not game.last_storage_warning,"successful pause write restores the saved caption and resets warnings")
	game.profile.path = folder+"missing/profile.json"
	game.show_pause()
	check(game.last_storage_warning and game.toast_key == "messages.storageFailed","a subsequent failure warns again")
	game.free()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
