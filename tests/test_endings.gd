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

func cleared(round_index: int) -> GameModel:
	var game := GameModel.new()
	game.start(221)
	game.begin_round(round_index)
	game.snow.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
	return game

func run() -> void:
	for round_index in 3:
		var game := cleared(round_index)
		var completed: Array[bool] = []
		var magic: Array[bool] = []
		var on_complete := func(last: bool): completed.append(last)
		var on_magic := func(): magic.append(true)
		game.round_completed.connect(on_complete)
		game.tree_revealed.connect(on_magic)
		game.hazards.assign([{"x":game.player.x,"y":game.player.y,"age":3.0,"warning":1.0,"flight":.5}])
		game.stun = .8
		game.time_left = .001
		game.step(.1, Vector2.ZERO)
		check(game.state == "returning" and game.hazards.is_empty() and game.stun == 0 and game.score == 0 and completed.is_empty(), "clearance stops hazards and stun without awarding the result, round %d" % round_index)
		var clock := game.time_left
		var rng_state := game.rng.state
		for tick in 150:
			game.step(.1, Vector2.ZERO)
		check(game.state == "returning" and game.time_left == clock and game.hazards.is_empty() and game.snow.remaining == 0 and game.rng.state == rng_state, "waiting for the door cannot expire, spawn ice or create snow")
		var restored := GameModel.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(game.snapshot()))) and restored.state == "returning" and restored.paused, "safe return saves and restores paused")
		game.player = Vector2(.95,.025)
		game.step(.01, Vector2.ZERO)
		check(game.state == "returning", "reaching a side rail does not start the door scene")
		game.player = Vector2(.5,.1)
		for tick in 30:
			game.step(1.0 / 60, Vector2.UP)
			if game.state == "greeting": break
		check(game.state == "greeting" and completed.is_empty(), "walking onto the central top landing starts Santa's scene")
		for tick in 23:
			game.step(.1, Vector2.LEFT)
		check(game.state == "greeting" and game.player.distance_to(RoundEnding.DOOR_TARGET) < .00001 and game.score == 0, "scene aligns the caretaker and ignores input without ending early")
		game.paused = true
		var snapshot := game.snapshot()
		game.step(.1, Vector2.RIGHT)
		check(game.snapshot() == snapshot, "pause freezes the ending's pose and progress")
		check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))) and absf(restored.ending_time - game.ending_time) < .00001, "mid-scene saves retain the animation phase")
		game.paused = false
		restored.paused = false
		var synchronized := true
		for tick in 100:
			game.step(.1, Vector2.LEFT)
			restored.step(.1, Vector2.RIGHT)
			synchronized = synchronized and game.state == restored.state and absf(game.ending_time - restored.ending_time) < .00001 and game.player.distance_to(restored.player) < .00001
		check(synchronized and game.score == restored.score, "resuming an ending preserves its action and awards exactly the same score")
		check(game.state == ("won" if round_index == 2 else "celebrating") and completed == [round_index == 2], "round completes once, after the full Santa scene")
		check(game.time_left == clock and game.score == int(game.stage().reward) + 10 + 300 and game.round_hits == 0, "return and scene preserve the earned clock and no-hit reward")
		check(magic.size() == (1 if round_index == 2 else 0), "only the third scene triggers the tree reveal once")
		var score := game.score
		game.finish_round()
		game.step(.1, Vector2.UP)
		check(game.score == score and completed.size() == 1, "terminal input cannot repeat the reward")
		game.round_completed.disconnect(on_complete)
		game.tree_revealed.disconnect(on_magic)
		for fps in [10, 60, 120]:
			var timed := cleared(round_index)
			timed.step(.01, Vector2.ZERO)
			timed.player = Vector2(.5,.025)
			timed.step(.01, Vector2.ZERO)
			var ticks := 0
			while timed.state == "greeting" and ticks < fps * 10:
				timed.step(1.0 / fps, Vector2.ZERO)
				ticks += 1
			check(absf(ticks / float(fps) - RoundEnding.duration(round_index)) <= 1.0 / fps + .00001, "ending uses real seconds at %d fps, round %d" % [fps,round_index])
	# Reject damaged animation phases and keep pre-ending saves compatible.
	var game := cleared(0)
	var old := game.snapshot()
	old.erase("ending_time")
	old.erase("ending_start_player")
	var restored := GameModel.new()
	check(restored.restore(old) and restored.ending_time == 0, "older gameplay saves remain compatible")
	for invalid in [-1, 100, "invalid"]:
		var corrupt := game.snapshot()
		corrupt.ending_time = invalid
		check(not restored.restore(corrupt), "invalid scene clock is rejected: %s" % str(invalid))
	var seen: Array[int] = []
	for stage in 3:
		for tick in 750:
			var frame := RoundEnding.frame_at(stage, tick / 100.0)
			if frame not in seen: seen.append(frame)
	seen.sort()
	check(seen == [0,2,3,4,5,6,7,8,9,10,11,12,13,14,15], "all interaction poses are used; clean transition poses are selected separately")
	check(RoundEnding.tree_reveal(2.8) == 0 and RoundEnding.tree_reveal(4.2) == 1, "tree appears only after the raised wand")
	check(RoundEnding.santa_presence(0,6) == 0 and RoundEnding.door_open(0,6) == 0, "Santa returns indoors and closes the door after the handshake")
	check(RoundEnding.santa_presence(1,6.3) == 0 and RoundEnding.door_open(1,6.3) == 0, "Santa returns indoors after handing over the present")
	check(RoundEnding.santa_presence(2,7.2) == 1 and RoundEnding.door_open(2,7.2) == 1, "Santa remains in the doorway for the final tree celebration")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/ending-test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
