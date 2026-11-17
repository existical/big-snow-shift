extends SceneTree

var game: Control
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = "res://builds/ui-test-profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(game.profile.path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile.path + suffix))
	root.add_child(game)
	await process_frame
	check(game.view == "menu", "starts at menu")
	check(ProjectSettings.get_setting("application/config/name") == "Big Snow Shift", "current game title")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name") == "Godot/app_userdata/Big Snow Shift", "new game identity has its own saved data")
	var title_fits := false
	for child in game.overlay.get_children():
		if child is TextureRect:
			title_fits = child.size.x <= 640 and child.size.y <= 300 and child.position.x >= 0
	check(title_fits, "illustrated title stays within the menu layout")
	game.start_night()
	check(game.view == "playing" and not game.model.paused, "start enters playing")
	check_hud_progress()
	game.handle_back_request()
	game.handle_back_request()
	check(game.view == "pause", "duplicate Android Back notification does not immediately resume")
	var saved_time: float = game.model.time_left
	await create_timer(0.1).timeout
	check(game.model.time_left == saved_time, "UI pause freezes clock")
	game.show_settings("pause")
	game.profile.settings.music = 0.0
	game.close_settings()
	check(game.view == "pause" and game.model.paused, "settings returns to paused game")
	game.profile.active_run = game.model.snapshot()
	check(game.profile.save(), "profile writes atomically")
	var recovered := PlayerProfile.new()
	recovered.path = game.profile.path
	recovered.load_profile()
	check(recovered.settings.music == 0 and recovered.active_run.id == game.model.run_id, "settings and active run survive disk load")
	var legacy_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.profile.path))
	legacy_data.settings.reduced_motion = true
	var legacy_file := FileAccess.open(game.profile.path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_data))
	legacy_file.close()
	var legacy := PlayerProfile.new()
	legacy.path = game.profile.path
	legacy.load_profile()
	check(not legacy.settings.has("reduced_motion") and legacy.active_run.id == game.model.run_id and legacy.settings.music == 0, "old reduced-motion preference is ignored while retaining the saved night and audio preferences")
	game.world.reduced_motion = true
	game.apply_settings()
	check(not game.world.reduced_motion, "applying player settings restores normal animations")
	legacy.settings.reduced_motion = true
	check(legacy.save() and not JSON.parse_string(FileAccess.get_file_as_string(legacy.path)).settings.has("reduced_motion"), "saving retires an obsolete reduced-motion key from an older in-memory profile")
	check(recovered.save(), "profile replaces existing file")
	var file := FileAccess.open(game.profile.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var backup := PlayerProfile.new()
	backup.path = game.profile.path
	backup.load_profile()
	check(backup.active_run.id == game.model.run_id, "corrupted primary recovers from backup")
	game.continue_night()
	check(game.view == "pause" and game.model.paused, "continue resumes safely at pause screen")
	game.resume_game()
	# Send actual InputEventScreenTouch/Drag events through Godot's input pipeline.
	game.profile.settings.control_mode = "pad"
	game.apply_settings()
	var center: Vector2 = game.pad.get_global_transform_with_canvas() * Vector2(83, 83)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = center
	touch.pressed = true
	root.push_input(touch, true)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(0, -60) * game.stage.scale.x
	root.push_input(drag, true)
	await process_frame
	check(game.pad.direction.y < -0.9, "touch drag steers up")
	var old_y: float = game.model.player.y
	await create_timer(0.70).timeout
	check(game.model.player.y < old_y, "held touch completes preparation and moves after the first scoop")
	game.show_pause()
	check(game.pad.direction == Vector2.ZERO and game.pad.finger == -1, "pause releases held touch")
	for round_index in 3:
		game.model.begin_round(round_index)
		game.model.snow.brush(Vector2(0.5, 0.5), Vector2.ONE * 2, 255)
		game.resume_game()
		await physics_frame
		await process_frame
		check(game.view == "playing" and game.model.state == "returning" and game.progress_label.text.contains("door"), "cleared round keeps gameplay open and guides the player to the door")
		game.set_physics_process(false)
		if round_index == 0:
			# Exercise actual persistence against this test's builds/ profile.
			# QA capture mode normally suppresses store_run altogether.
			game.qa_mode = false
			game.store_run()
			game.show_menu()
			game.continue_night()
			check(game.view == "pause" and game.model.state == "returning", "Continue restores a safe walk to the door at pause")
			game.resume_game()
			game.model.player = Vector2(.5,.025)
			game.model.step(.01, Vector2.ZERO)
			for tick in 20:
				game.model.step(.1, Vector2.ZERO)
			var phase: float = game.model.ending_time
			game.store_run()
			game.show_menu()
			game.continue_night()
			check(game.view == "pause" and game.model.state == "greeting" and absf(game.model.ending_time - phase) < .00001, "Continue restores Santa's scene instead of opening results early")
			game.resume_game()
			check(not game.pad.visible, "touch movement stays hidden during Santa's scene")
			game.qa_mode = true
		for tick in 900:
			var direction := Vector2.ZERO
			if game.model.state == "returning":
				direction = Vector2.UP if game.model.player.y > .04 else Vector2.ZERO
			game.model.step(1.0 / 60, direction)
		game.set_physics_process(true)
		await physics_frame
		await process_frame
		check(game.view == "result", "result UI waits until Santa's action finishes")
	check(game.model.state == "won" and is_instance_valid(game.name_edit), "final result offers name entry")
	check(not game.active_run and game.profile.active_run.is_empty(), "win clears Continue before the score is submitted")
	game.name_edit.text = "Snow Tester"
	game.submit_score()
	check(game.view == "scores" and game.profile.scores.size() == 1, "score submitted and leaderboard opens")
	check_score_navigation()
	check(not game.profile.submit(game.model, "Duplicate") and game.profile.scores.size() == 1, "same run cannot submit twice")
	game.show_menu()
	check(game.profile.active_run.is_empty(), "finished run no longer offers continue")
	game.show_settings("menu")
	game.close_settings()
	check(game.view == "menu", "menu settings returns to menu")
	game.start_night()
	game.set_physics_process(false)
	game.model.begin_round(1)
	game.model.score = 777
	game.model.time_left = .001
	game._physics_process(.1)
	check(game.view == "playing" and game.model.state == "timeout" and not game.pad.visible, "timeout keeps the scene visible and disables touch instead of opening retry early")
	for tick in 25: game._physics_process(.1)
	var fall_phase: float = game.model.failure_time
	game.qa_mode = false # Isolated builds/ profile, not a real player profile.
	game.show_pause()
	game.show_menu()
	game.continue_night()
	check(game.view == "pause" and game.model.state == "timeout" and absf(game.model.failure_time - fall_phase) < .00001, "Continue resumes an interrupted Santa fall at its saved phase")
	game.resume_game()
	check(not game.pad.visible, "resuming a fall does not enable movement controls")
	game.qa_mode = true
	for tick in 80: game._physics_process(.1)
	check(game.view == "result" and game.model.state == "lost" and game.model.score == 777, "retry screen waits for Santa's exit and preserves previous points")
	check(not game.active_run and game.profile.active_run.is_empty(), "completed loss clears the Continue save")
	game.retry_round()
	check(game.active_run and game.view == "playing" and game.model.stage_index == 1 and game.model.failure_time == 0 and game.model.score == 777, "retry starts a saveable attempt of the same round with no fall animation or lost points")
	game.model.apply_hit()
	for tick in 5: game._physics_process(.1)
	check(game.view == "playing" and is_equal_approx(game.model.stun,game.model.hit_duration-.5) and game.pad.visible, "hit recovery remains in gameplay with the touch pad available")
	var hit_remaining: float = game.model.stun
	game.qa_mode = false
	game.show_pause()
	game._physics_process(.1)
	check(game.model.stun == hit_remaining, "UI pause freezes the seated reaction")
	game.show_menu()
	game.continue_night()
	check(game.view == "pause" and is_equal_approx(game.model.stun,hit_remaining) and game.model.hit_duration == game.model.settings.hit_recovery_seconds, "Continue restores the seated reaction at its exact saved phase")
	game.resume_game()
	game.qa_mode = true
	game._physics_process(.1)
	check(game.view == "playing" and is_equal_approx(game.model.stun,hit_remaining - .1) and game.model.round_hits == 1, "resuming recovery advances its phase without replaying the hit")
	check_finished_saves()
	print(JSON.stringify({"ui_checks": checks, "failures": failures}))
	game.sound.music.stop()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_score_navigation() -> void:
	var actions: Array[String] = []
	for card in game.overlay.get_children():
		for child in card.get_children():
			if child is Button: actions.append(child.get_meta("translation_key",""))
	check(actions == ["difficulty.easy","difficulty.medium","difficulty.hard","difficulty.extreme","scores.personal","common.mainMenu"],"score screen after a win contains only score tabs and Main menu")
	var saved_scores: Array = game.profile.scores.duplicate(true)
	game.show_scores("previous")
	check(game.scores_tab == game.profile.settings.difficulty and game.profile.scores == saved_scores,"retired score selections fall back without deleting records")

func check_finished_saves() -> void:
	game.qa_mode = false # Writes only the isolated builds/ui-test-profile.json.
	game.set_physics_process(false)
	for state in ["won","lost"]:
		game.start_night()
		game.model.begin_round(2 if state == "won" else 1)
		game.store_run() # Leave a resumable autosave queued as the game ends.
		game.model.state = state
		var finished: Dictionary = game.model.snapshot()
		game.show_result()
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.profile.path))
		check(disk.run.is_empty() and not game.active_run,state+" clears the on-disk Continue save after pending writes")
		game._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
		game.show_menu()
		game.store_run(true)
		var loaded := PlayerProfile.new()
		loaded.path = game.profile.path
		loaded.load_profile()
		check(loaded.active_run.is_empty(),state+" cannot return through focus loss, Main menu or a cold profile load")
		loaded.shutdown()
		if state == "lost":
			game.retry_round()
			game.profile.flush_pending()
			disk = JSON.parse_string(FileAccess.get_file_as_string(game.profile.path))
			check(game.active_run and disk.run.state == "playing" and disk.run.stage == 1,"immediate retry creates a new resumable attempt on disk")
		# Upgrade fixture bypasses the current serializer, as a real old beta did.
		var old: Dictionary = game.profile.document()
		old.run = finished
		var old_path := "res://builds/ended-legacy-profile.json"
		PlayerProfile.write_document(ProjectSettings.globalize_path(old_path),old)
		loaded = PlayerProfile.new()
		loaded.path = old_path
		loaded.load_profile()
		check(loaded.active_run.is_empty() and loaded.scores.size() == game.profile.scores.size(),state+" old save loses Continue while preserving scores")
		loaded.save()
		loaded.shutdown()
		game.profile.active_run = finished
		game.continue_night()
		check(game.view == "menu" and not game.active_run and game.profile.active_run.is_empty(),state+" stale in-memory Continue cannot reopen the result")
	game.qa_mode = true

func check_hud_progress() -> void:
	var original: Dictionary = game.model.snapshot()
	game.model.time_left = 20
	game.model.score = 25
	game.refresh_hud()
	check(game.time_label.accessibility_name == "Time left: 0:20" and game.score_label.text == "25", "icon HUD retains a localized countdown name and omits score padding")
	check(game.progress_bar.visible and not game.progress_fill.visible, "empty clearing bar keeps its visible track")
	check(game.time_label.get_theme_color("font_color") == Color("ffac8e"), "active low-time countdown warns the player")
	game.model.snow.brush(Vector2(.5,.5), Vector2(.2,.2), 255)
	game.refresh_hud()
	var cleared_width: float = game.progress_fill.size.x
	var cleared_text: String = game.progress_label.text
	check(cleared_width > 0 and game.progress_fill.visible, "shovel stroke advances the clearing bar")
	for i in 10:
		game.model.snow.add_pile(Vector2(.4+i*.02,.5), 300)
	game.refresh_hud()
	check(game.progress_fill.size.x < cleared_width and game.progress_label.text != cleared_text, "new icicle snow reduces both the fill and percentage")
	game.model.snow.brush(Vector2(.5,.5), Vector2.ONE*2, 255)
	game.model.prepare_finish()
	game.refresh_hud()
	check(game.time_label.accessibility_name == "Time saved: 0:20" and game.time_label.text == "0:20", "clearing preserves the remaining time and its localized meaning")
	check(game.time_label.get_theme_color("font_color") == game.CREAM, "finishing clears the low-time warning even within the same second")
	check(is_equal_approx(game.progress_fill.size.x,game.progress_bar.size.x-2), "completed clearing fills the track without covering its border")
	game.model.begin_round(1)
	game.refresh_hud()
	check(game.time_label.get_meta("stat_key") == "hud.time" and not game.progress_fill.visible, "next round resets countdown meaning and clearing bar")
	check(game.model.restore(original), "HUD fixture restores its original round")
	game.world.set_model(game.model)
	game.refresh_hud()
