extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func model_at(speed: float) -> GameModel:
	var tuning := GameSettings.new()
	tuning.player_speed_multiplier = speed
	var model := GameModel.new(tuning)
	model.start(197)
	model.player = Vector2(.5, .55)
	model.spawn_countdown = 999
	return model

func run() -> void:
	var current := GameSettings.new()
	check(GameModel.new().settings.player_speed_multiplier == 1.75 and current.idle_animation_multiplier == 1.0 and current.snow_per_scoop == 255 and current.hit_recovery_seconds == 6.0, "normal startup uses the built-in player defaults")
	test_idle_tuning()

	for speed in [.25, .5, 1.25, 1.75, 2.0, 3.0]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var original := model_at(1.0)
			var tuned := model_at(speed)
			# Equal player-time steps must trace the same path and remove the same
			# chunks, including stacked piles, in less/more real time.
			var contact := StairSurface.unproject(GameModel.horizontal_contact(original.player, direction)) if direction.x != 0 else GameModel.vertical_contact(original.player, direction)
			original.snow.add_pile(contact, 160)
			tuned.snow.add_pile(contact, 160)
			var impact_frames: Array[int] = []
			var on_cut := func(_amount: int): impact_frames.append(tuned.pose_frame())
			tuned.snow_cleared.connect(on_cut)
			var synchronized := true
			for tick in 360:
				original.step(1.0 / 120, direction)
				tuned.step(1.0 / (120 * speed), direction)
				synchronized = synchronized and original.player.distance_to(tuned.player) < .00001 and absf(original.shovel_time - tuned.shovel_time) < .00001
			check(synchronized and original.snow.cells == tuned.snow.cells and original.snow.piles == tuned.snow.piles, "scaled motion and chunk clearing stay together speed=%.2f direction=%s" % [speed, direction])
			var expected_frame := 11 if direction.x != 0 else (19 if direction.y < 0 else 27)
			check(not impact_frames.is_empty() and impact_frames.all(func(frame: int): return frame == expected_frame), "each scoop and debris burst uses the digging pose speed=%.2f direction=%s" % [speed, direction])
			tuned.snow_cleared.disconnect(on_cut)
			check(absf(tuned.elapsed * speed - original.elapsed) < .00001, "player speed does not accelerate the round clock")

			var bare := model_at(speed)
			bare.snow.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
			bare.snow.add_pile(Vector2(.05,.05), 160) # Keep the round active away from the walking lane.
			var start := StairSurface.project(bare.player)
			for tick in 48:
				bare.step(1.0 / 120, direction)
			var distance := StairSurface.project(bare.player) - start
			var travelled := absf(distance.x) if direction.x != 0 else absf(distance.y)
			var walk_speed := GameModel.SIDE_WALK_SPEED if direction.x != 0 else GameModel.VERTICAL_WALK_SPEED
			check(not bare.shoveling and absf(travelled - walk_speed * speed * .4) < .01, "cleared-path walking scales by the configured rate speed=%.2f direction=%s" % [speed, direction])
			check(bare.pose_frame() == ShovelRig.frame_for(direction, true, false, .4 * speed), "walking animation follows the same speed multiplier")

			# Exercise low framerates too; an impact can fall inside a frame.
			var coarse := model_at(speed)
			var safe := true
			for tick in 30:
				var previous := coarse.player
				coarse.step(.1, direction)
				safe = safe and (previous == coarse.player or not coarse.movement_blocked(previous, coarse.player, direction))
			check(safe, "snow gate prevents missed patches at 10 fps speed=%.2f direction=%s" % [speed, direction])

	# Real-time systems, idle animation, pause and continued runs.
	var normal := model_at(1.0)
	var faster := model_at(1.25)
	for model in [normal, faster]:
		model.apply_hit()
		model.hazards.assign([{"x":.1,"y":.1,"age":0.0,"warning":2.0,"flight":.75}])
		for tick in 25:
			model.step(.05, Vector2.ZERO)
	check(normal.time_left == faster.time_left and normal.stun == faster.stun and normal.immunity == faster.immunity and normal.hazards == faster.hazards and normal.spawn_countdown == faster.spawn_countdown, "round timer, icicles, stun and immunity retain real-time durations")
	check(faster.pose_frame() == ShovelRig.frame_for(Vector2.RIGHT, false, false, faster.elapsed), "idle animation defaults to its original pace independently of player speed")
	var saved := model_at(1.25)
	for tick in 20:
		saved.step(1.0 / 60, Vector2.RIGHT)
	var restored := model_at(1.25)
	check(restored.restore(JSON.parse_string(JSON.stringify(saved.snapshot()))), "tuned run restores just before a digging impact")
	saved.spawn_countdown = restored.spawn_countdown
	var frozen := restored.snapshot()
	restored.step(.1, Vector2.RIGHT)
	check(restored.snapshot() == frozen, "pause freezes the scaled animation, motion and clearing")
	restored.paused = false
	for tick in 45:
		saved.step(1.0 / 60, Vector2.RIGHT)
		restored.step(1.0 / 60, Vector2.RIGHT)
	check(saved.player.distance_to(restored.player) < .00001 and saved.snow.cells == restored.snow.cells and absf(saved.shovel_time - restored.shovel_time) < .00001, "continue preserves stroke synchronization")
	var retuned := model_at(2.0)
	check(retuned.restore(saved.snapshot()) and retuned.settings.player_speed_multiplier == 1.25 and retuned.shovel_time == saved.shovel_time, "continued saves preserve their original tuning and stroke phase")
	var report := {"checks":checks,"failures":failures,"default_speed":current.player_speed_multiplier}
	var file := FileAccess.open("res://builds/tuning-test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_idle_tuning() -> void:
	for active_speed in [.5, 1.75, 3.0]:
		for idle_speed in [.5, 1.0, 2.0]:
			var model := model_at(active_speed)
			model.settings.idle_animation_multiplier = idle_speed
			var frames_match := true
			for tick in 240:
				model.step(1.0 / 120, Vector2.ZERO)
				frames_match = frames_match and model.pose_frame() == 30 + int(model.elapsed * idle_speed * 2) % 2
			check(frames_match, "standing animation follows only idle rate %.2f with active rate %.2f" % [idle_speed, active_speed])
	var slow_idle := model_at(1.75)
	var quick_idle := model_at(1.75)
	slow_idle.settings.idle_animation_multiplier = .5
	quick_idle.settings.idle_animation_multiplier = 3.0
	var active_frames_match := true
	for direction in [Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		for tick in 60:
			slow_idle.step(1.0 / 60, direction)
			quick_idle.step(1.0 / 60, direction)
			active_frames_match = active_frames_match and slow_idle.pose_frame() == quick_idle.pose_frame()
	check(active_frames_match and slow_idle.player == quick_idle.player and slow_idle.snow.cells == quick_idle.snow.cells and slow_idle.shovel_time == quick_idle.shovel_time, "changing idle speed preserves active animations, movement and scoops")
	# The locomotion selector stays parked while the independent hit renderer
	# owns the body; held movement must not select a walking/shoveling frame.
	quick_idle.elapsed = .20
	quick_idle.moving = true
	quick_idle.stun = .5
	check(quick_idle.pose_frame() == 31, "locomotion stays parked while the hit reaction owns rendering")
	quick_idle.moving = false
	quick_idle.paused = true
	var paused_frame := quick_idle.pose_frame()
	for tick in 60:
		quick_idle.step(1.0 / 60, Vector2.ZERO)
	check(quick_idle.pose_frame() == paused_frame, "pause freezes the independent idle animation")
