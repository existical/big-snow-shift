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

func expired(stage: int = 0, speed: float = 1.75) -> GameModel:
	var settings := GameSettings.new()
	settings.player_speed_multiplier = speed
	var game := GameModel.new(settings)
	game.start(123)
	game.begin_round(stage)
	game.score = 1234
	game.time_left = .001
	game.hazards.assign([{"x":.5,"y":.5,"age":0.0,"warning":10.0,"flight":.5}])
	game.step(.01, Vector2.ZERO)
	return game

func run() -> void:
	for stage in 3:
		for fps in [10,60,120]:
			var game := expired(stage)
			check(game.state == "timeout" and game.is_active() and game.controls_locked() and game.time_left == 0, "expiration enters an active, locked scene, stage %d at %d fps" % [stage,fps])
			check(game.hazards.is_empty() and not game.shoveling and game.stun == 0, "timeout stops ice and caretaker work")
			var player := game.player
			var cells := game.snow.cells.duplicate()
			var piles := game.snow.piles.duplicate()
			var hits := game.total_hits
			var rng_state := game.rng.state
			var cues: Array[String] = []
			var rewards: Array[bool] = []
			var on_slip := func(): cues.append("slip")
			var on_land := func(): cues.append("land")
			var on_complete := func(last: bool): rewards.append(last)
			game.santa_slipped.connect(on_slip)
			game.santa_landed.connect(on_land)
			game.round_completed.connect(on_complete)
			var ticks := 0
			var locked := true
			while game.state == "timeout" and ticks < 9 * fps:
				game.step(1.0 / fps, Vector2.RIGHT)
				ticks += 1
				locked = locked and game.player == player and game.score == 1234 and game.time_left == 0 and game.snow.cells == cells and game.snow.piles == piles and game.hazards.is_empty()
			check(locked and game.rng.state == rng_state and game.total_hits == hits, "fall is cinematic: input, snow, scores, RNG and hits stay unchanged")
			check(game.state == "lost" and absf(ticks / float(fps) - RoundTimeout.DURATION) <= 1.0 / fps + .00001, "retry waits for the real-time fall duration")
			check(cues == ["slip","land"] and rewards.is_empty() and game.last_reward == 0, "fall emits its two cues once and never awards a round")
			game.step(.1, Vector2.UP)
			check(cues.size() == 2 and game.score == 1234 and game.failure_time == RoundTimeout.DURATION, "terminal input cannot replay the fall or change points")
			game.santa_slipped.disconnect(on_slip)
			game.santa_landed.disconnect(on_land)
			game.round_completed.disconnect(on_complete)
			game.begin_round(stage)
			check(game.state == "playing" and game.failure_time == 0 and game.score == 1234 and game.snow.remaining > 0, "retry resets the scene and keeps earlier points")

	for phase in [.9,2.8,5.3]:
		var game := expired()
		for tick in roundi(phase * 10): game.step(.1,Vector2.ZERO)
		game.paused = true
		var saved := game.snapshot()
		game.step(.1,Vector2.RIGHT)
		check(game.snapshot() == saved, "pause freezes a fall at phase %.1f" % phase)
		var restored := GameModel.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.state == "timeout" and restored.paused and absf(restored.failure_time - game.failure_time) < .00001, "saved fall restores paused at phase %.1f" % phase)
		game.paused = false
		restored.paused = false
		var synchronized := true
		for tick in 80:
			game.step(.1,Vector2.LEFT)
			restored.step(.1,Vector2.UP)
			synchronized = synchronized and game.state == restored.state and absf(game.failure_time - restored.failure_time) < .00001
		check(synchronized and restored.state == "lost" and restored.score == 1234, "continued fall reaches the same result without rewards")

	for speed in [.5,3.0]:
		var game := expired(0,speed)
		for tick in 72: game.step(.1,Vector2.ZERO)
		check(game.state == "lost", "gameplay multiplier %.1f does not accelerate the timeout scene" % speed)
	var game := expired()
	for invalid in [-1,100,"broken"]:
		var broken := game.snapshot()
		broken.failure_time = invalid
		check(not GameModel.new().restore(broken), "invalid fall phase rejected: %s" % str(invalid))
	var old := game.snapshot()
	old.state = "lost"
	old.erase("failure_time")
	var restored := GameModel.new()
	check(restored.restore(old) and restored.state == "lost" and restored.failure_time == 0, "older lost saves remain terminal without replaying an invented fall")
	var frames: Array[int] = []
	var gentle := true
	for tick in 720:
		var seconds := tick / 100.0
		var frame := RoundTimeout.frame_at(seconds)
		if frame not in frames: frames.append(frame)
		gentle = gentle and RoundTimeout.frame_at(seconds,true) not in [8,9,10,11]
	frames.sort()
	check(frames == range(16), "all 16 new poses are reachable in their sequence")
	check(gentle, "reduced motion replaces repeated tumbling with a seated slide")
	check(RoundTimeout.position_at(2.65).y < RoundTimeout.position_at(4).y and RoundTimeout.position_at(4).y < RoundTimeout.position_at(5.1).y and RoundTimeout.position_at(7.2).y > 820, "Santa travels from the door to the bottom and out of view")
	# Last-scoop precedence must still select the successful door ending.
	game = GameModel.new()
	game.start(1)
	game.snow.brush(Vector2(.5,.5),Vector2.ONE * 2,255)
	game.time_left = .001
	game.step(.1,Vector2.ZERO)
	check(game.state == "returning" and game.failure_time == 0, "a completed field still wins over a simultaneous deadline")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/timeout-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
