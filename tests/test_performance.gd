extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func reference_image(field: SnowField) -> Image:
	var pixels := PackedByteArray()
	pixels.resize(SnowField.WIDTH * SnowField.HEIGHT * 4)
	for i in field.cells.size():
		pixels[i * 4] = field.cells[i] - field.piles[i]
		pixels[i * 4 + 1] = 255 if field.cells[i] > 0 else 0
		pixels[i * 4 + 2] = roundi(field.piles[i] * 255.0 / SnowField.MAX_PILE_DEPTH)
		pixels[i * 4 + 3] = 255
	var image := Image.create_from_data(144, 72, false, Image.FORMAT_RGBA8, pixels)
	image.resize(288, 144, Image.INTERPOLATE_CUBIC)
	return image

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 913
	var field := SnowField.new()
	field.generate(1.0, rng)
	check(field.image().get_data() == reference_image(field).get_data(), "initial mask matches original cubic resize")
	check(not field.dirty and not field.dirty_cells.has_area(), "mask consumes dirty bounds")
	for operation in 120:
		var point := Vector2(rng.randf(), rng.randf())
		match operation % 4:
			0: field.add_pile(point, 180, operation)
			1: field.brush(point, Vector2(.09, .05), 255)
			2: field.box(Rect2(point, Vector2(.05, .07)), true, 255)
			3: field.tread_strip(operation % 16, 400 + point.x * 350, 450 + point.x * 350, true, 255)
		check(field.image().get_data() == reference_image(field).get_data(), "incremental mask matches full resize after operation %d" % operation)
	field.add_pile(Vector2(.1, .1), 180)
	field.add_pile(Vector2(.9, .9), 180)
	check(field.dirty_cells.position.x <= 14 and field.dirty_cells.end.x >= 129, "multiple deposits merge dirty bounds")
	check(field.image().get_data() == reference_image(field).get_data(), "merged changes match full resize")
	for corner in [Vector2.ZERO, Vector2.ONE, Vector2(0,1), Vector2(1,0)]:
		field.brush(corner, Vector2(.1, .1), 255)
		check(field.image().get_data() == reference_image(field).get_data(), "image border resampling matches original")
	field.dirty = true
	check(field.dirty_cells == SnowField.ALL_CELLS, "external invalidation rebuilds the full field")
	check(field.image().get_data() == reference_image(field).get_data(), "forced full rebuild matches original")
	await check_saves()
	await check_hud_and_fonts()
	print(JSON.stringify({"performance_checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func check_saves() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/performance/optimized"))
	var profile := PlayerProfile.new()
	profile.path = "res://builds/performance/optimized/async-save-test.json"
	profile.active_run = {"id":"original","value":0}
	check(profile.save(), "initial synchronous profile save succeeds")
	for index in 50:
		profile.player_name = "Kid %d" % index
		profile.active_run.value = index
		check(profile.save_async(), "asynchronous save accepted")
	check(profile.flush_pending(), "flush waits for newest queued save")
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	check(data.name == "Kid 49" and data.run.value == 49, "latest request wins and persists a complete document")
	check(profile._writes < 51, "queued saves coalesce")
	var writes := profile._writes
	profile.save_async()
	profile.flush_pending()
	check(profile._writes == writes, "unchanged snapshots do not repeat disk writes")
	profile.active_run.value = 999
	profile.save_async()
	profile.active_run.value = -1 # Must not mutate the worker's captured data.
	profile.shutdown()
	data = JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	check(data.run.value == 999, "shutdown flushes immutable pending snapshots")
	check(not profile.save_async() and not profile.save(), "closed profile cannot start new writes")
	var backup = JSON.parse_string(FileAccess.get_file_as_string(profile.path + ".bak"))
	check(backup is Dictionary and backup.version == 5, "previous complete document remains readable as backup")
	var failed := PlayerProfile.new()
	failed.path = "res://builds/performance/optimized/absent-directory/profile.json"
	failed.save_async()
	check(not failed.flush_pending() and not failed.poll_save(), "worker errors reach the game thread")
	failed.path = "res://builds/performance/optimized/recovered-save-test.json"
	failed.save_async()
	check(failed.flush_pending() and failed.poll_save(), "a later successful save recovers from an I/O failure")
	failed.shutdown()

func check_hud_and_fonts() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = "res://builds/performance/optimized/unused-hud-profile.json"
	root.add_child(game)
	game.set_physics_process(false)
	check(game.localization.fonts.size() < GameLocalization.FONT_NAMES.size(), "startup defers the all-script font collection")
	game.start_night()
	game.model.time_left = 120
	game.refresh_hud()
	check(game.time_label.text == "2:00", "HUD displays time after a model change")
	var before: String = game.round_label.text
	game.change_language("de-DE", false)
	check(game.round_label.text != before and not "{{" in game.round_label.text, "language changes invalidate cached HUD text")
	game.change_language("en", false)
	game.refresh_language("en")
	check(not "{{" in game.round_label.text, "same-language refresh restores formatted HUD text")
	game.show_settings("pause")
	check(game.localization.fonts.size() == GameLocalization.FONT_NAMES.size(), "language selector loads every script when opened")
	game.qa_mode = false
	game.profile.path = "res://builds/performance/optimized/absent-directory/visible-error.json"
	game.store_run(true)
	check(game.last_storage_warning and game.toast_key == "messages.storageFailed", "storage failures reach the localized game warning")
	game.sound.shutdown()
	await create_timer(.15).timeout
	game.free()
