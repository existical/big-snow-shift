extends SceneTree
## Exercise the real menus, save/Continue, retry and replacement-confirmation flow.
var game: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)

func keys(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Button and node.has_meta("translation_key"): result.append(node.get_meta("translation_key"))
	for child in node.get_children(): result.append_array(keys(child))
	return result

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.sound.stopped = true
	game.profile.path = "res://builds/rule-lock-profile.json"
	root.add_child(game)
	game.set_physics_process(false)
	game.change_language("en",false)
	await process_frame
	for mode in ["easy","medium","hard","extreme","custom"]:
		var parameters := DifficultyRules.custom_defaults()
		parameters.extra_seconds = 210
		parameters.landing_warnings = false
		game.model.start(42,"hard" if mode == "custom" else mode,{"no_time_limit":true,"no_icicles":true},"custom" if mode == "custom" else "standard",parameters)
		game.active_run = true
		game.model.begin_round(1)
		game.model.score = 777
		game.model.time_left = 100
		game.model.snow.brush(Vector2(.5,.5),Vector2(.2,.1),255)
		game.profile.active_run = game.model.snapshot()
		var original: Dictionary = game.model.snapshot()
		var preferences: Dictionary = game.profile.settings.duplicate(true)
		var rules: Dictionary = game.model.rules_snapshot()
		game.show_pause()
		game.show_settings("pause")
		var buttons := keys(game.overlay)
		check(not buttons.has("difficulty.change") and not buttons.has("custom.change") and not buttons.has("difficulty.setup"),mode+" pause Settings has no rules action")
		game.show_difficulty()
		game.open_custom_game()
		game.commit_difficulty()
		check(game.view == "settings" and game.model.snapshot() == original and game.profile.active_run == original,mode+" settings cannot enter or commit new rules")
		game.close_settings()
		check(game.view == "pause",mode+" Done returns to pause")
		game.show_difficulty()
		check(game.view == "pause",mode+" paused game rejects direct setup navigation")
		game.show_menu()
		game.show_settings("menu")
		check(not keys(game.overlay).has("difficulty.change"),mode+" main-menu Settings also has no rules action")
		game.close_settings()
		check(game.profile.settings == preferences,mode+" viewing Settings preserves difficulty and Custom preferences")
		game.continue_night()
		check(game.model.snapshot() == original and game.view == "pause",mode+" Continue keeps the exact saved game")
		game.model.state = "lost"
		game.show_result()
		check(keys(game.overlay) == ["result.retry","common.mainMenu"],mode+" loss offers retry and Main menu only")
		game.show_difficulty()
		game.commit_difficulty()
		check(game.view == "result" and game.model.rules_snapshot() == rules,mode+" result cannot apply a different difficulty")
		game.retry_round()
		check(game.model.run_id == original.id and game.model.stage_index == 1 and game.model.score == 777 and game.model.rules_snapshot() == rules,mode+" retry preserves identity, completed score and rules")
		game.model.state = "celebrating"
		game.next_round()
		check(game.model.stage_index == 2 and game.model.rules_snapshot() == rules,mode+" next round keeps its starting rules")
		game.profile.active_run = game.model.snapshot()
		var old_save: Dictionary = game.profile.active_run.duplicate(true)
		game.show_menu()
		game.show_difficulty()
		game.open_custom_game()
		game.selected_custom_parameters.extra_seconds = 900
		game.selected_assists.no_icicles = false
		check(game.model.rules_snapshot() == rules and game.profile.active_run == old_save,mode+" editing a future game's draft leaves the current game intact")
		game.commit_difficulty()
		check(game.view == "confirm" and game.profile.active_run == old_save,mode+" replacement must be confirmed")
		game.continue_night()
		check(game.view == "pause" and game.model.rules_snapshot() == rules,mode+" Keep current game discards the pending replacement")
		game.show_menu()
		game.show_difficulty()
		game.open_custom_game()
		game.selected_custom_parameters.extra_seconds = 900
		game.commit_difficulty()
		game.start_night()
		check(game.model.run_id != old_save.id and game.model.stage_index == 0 and game.model.score == 0 and game.model.custom_parameters.extra_seconds == 900,mode+" confirmed changes start a separate game at round one")
	game.profile.shutdown()
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	var result := {"checks":checks,"failures":failures}
	FileAccess.open("res://builds/rule-lock-tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
