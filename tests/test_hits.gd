extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func fixture(speed: float = 1.75, recovery: float = 6.0) -> GameModel:
	var settings := GameSettings.new()
	settings.player_speed_multiplier = speed
	settings.hit_recovery_seconds = recovery
	var game := GameModel.new(settings)
	game.start(123)
	game.player = Vector2(.45,.6)
	game.snow.brush(Vector2(.5,.6),Vector2(.40,.30),255)
	game.spawn_countdown = 100
	return game

func advance(game: GameModel, seconds: float, direction: Vector2 = Vector2.ZERO) -> void:
	var left := seconds
	while left > .0000001:
		var delta := minf(left,.05)
		game.step(delta,direction)
		left -= delta

func _initialize() -> void:
	var impact := fixture()
	impact.shoveling = true
	impact.moving = true
	impact.shovel_time = .2
	impact.hazards.assign([{"x":impact.player.x,"y":impact.player.y,"age":2.0,"warning":1.0,"flight":.5}])
	var hits: Array[int] = []
	impact.hit.connect(func(): hits.append(1))
	var before := impact.snow.remaining
	var before_cells := impact.snow.cells.duplicate()
	var before_piles := impact.snow.piles.duplicate()
	var landed: Array[Vector2] = []
	impact.ice_landed.connect(func(point: Vector2): landed.append(point))
	impact.step(.01,Vector2.ZERO)
	check(impact.stun == 6 and impact.hit_duration == 6 and hits.size() == 1, "a real icicle collision starts the six-second reaction once")
	check(not impact.moving and not impact.shoveling and impact.shovel_time == 0, "impact immediately cancels movement and the interrupted scoop")
	check(is_equal_approx(impact.time_left,419.99) and impact.round_hits == 1 and impact.total_hits == 1, "a hit records the collision without an extra clock penalty")
	check(impact.snow.remaining == before and impact.snow.cells == before_cells and impact.snow.piles == before_piles and landed.is_empty(), "a character hit leaves both snow layers unchanged and emits no stair-impact burst")
	var seated_start := impact.stun
	before = impact.snow.remaining
	impact.hazards.assign([{"x":impact.player.x,"y":impact.player.y,"age":2.0,"warning":1.0,"flight":.5}])
	impact.step(.01,Vector2.RIGHT)
	check(hits.size() == 1 and is_equal_approx(impact.stun,seated_start - .01) and impact.snow.remaining == before and landed.is_empty(), "protected character hits add no snow and do not restart recovery")

	for stage in 3:
		for surface in ["bare","snow","pile"]:
			for protected in [false,true]:
				var game := fixture()
				game.begin_round(stage)
				game.player = Vector2(.5,.6)
				game.spawn_countdown = 100
				if surface == "bare": game.snow.brush(game.player,Vector2(.2,.2),255)
				if surface == "pile": game.snow.add_pile(game.player,180)
				if protected: game.immunity = 1.8
				var cells := game.snow.cells.duplicate()
				var piles := game.snow.piles.duplicate()
				var mass := game.snow.remaining
				var landings: Array[Vector2] = []
				game.ice_landed.connect(func(point: Vector2): landings.append(point))
				game.hazards.assign([{"x":.5,"y":.6,"age":2.0,"warning":1.0,"flight":.5}])
				game.step(.01,Vector2.ZERO)
				check(game.snow.cells == cells and game.snow.piles == piles and game.snow.remaining == mass and landings.is_empty() and game.hazards.is_empty() and game.round_hits == (0 if protected else 1) and is_equal_approx(game.time_left,float(game.stage().seconds)-.01), "body collision preserves %s and only normal countdown elapses in round %d, protected=%s" % [surface,stage + 1,str(protected)])
				var stair := Vector2(.8,.25)
				var height := game.snow.surface_height(stair)
				game.hazards.assign([{"x":stair.x,"y":stair.y,"age":2.0,"warning":1.0,"flight":.5}])
				game.step(.01,Vector2.ZERO)
				check(game.snow.remaining > mass and game.snow.surface_height(stair) > height and landings == [stair] and game.hazards.is_empty(), "a direct stair landing still adds a pile while the player is protected")

	for speed in [.25,1.0,1.75,3.0]:
		for fps in [10,60,120]:
			var game := fixture(speed)
			game.apply_hit()
			var start := game.player
			var cells := game.snow.cells.duplicate()
			var locked := true
			for tick in int(6 * fps):
				game.step(1.0 / fps,Vector2.RIGHT)
				locked = locked and game.player == start and game.snow.cells == cells and not game.moving and not game.shoveling
			check(locked and game.stun == 0 and is_equal_approx(game.time_left,414), "recovery costs exactly six elapsed seconds at speed %.2f and %d FPS" % [speed,fps])
			check(game.immunity > 1.79, "protection lasts through recovery plus a standing grace interval")
			game.step(.05,Vector2.RIGHT)
			check(game.player.x > start.x and game.moving, "held movement resumes after standing up")
			game.apply_hit()
			check(game.round_hits == 1 and game.stun == 0, "grace protection prevents an immediate second knockdown")
			advance(game,1.8)
			game.apply_hit()
			check(game.round_hits == 2 and game.stun == 6, "a later hit can start a new reaction after grace expires")

	# Source-table samples, independent of the runtime FRAMES array.
	for setup in [[Vector2.RIGHT,1],[Vector2.LEFT,1],[Vector2.UP,2],[Vector2.DOWN,0]]:
		check(HitReaction.frame_at(.05,6,setup[0]) == setup[1], "impact pose matches the incoming facing %s" % setup[0])
		var samples := [[.22,3],[.40,4],[.58,5],[.90,6],[1.4,5],[2.0,4],[2.6,5],[3.1,6],[3.7,5],[4.2,4],[4.8,5],[5.4,6],[5.75,7],[5.95,8]]
		var sequence_matches := true
		for sample in samples:
			sequence_matches = sequence_matches and HitReaction.frame_at(sample[0],6,setup[0]) == sample[1]
		check(sequence_matches, "the source seated-repeat, turn and rise order is preserved")
	check(HitReaction.frame_at(.1,6,Vector2.UP,true) == 4 and HitReaction.frame_at(4.2,6,Vector2.RIGHT,true) == 4 and HitReaction.frame_at(5.95,6,Vector2.DOWN,true) == 8, "reduced motion uses a stable seated body and still stands up")
	check(HitReaction.flip_for(Vector2.LEFT,1) == -1 and HitReaction.flip_for(Vector2.LEFT,4) == 1, "only the left-facing impact is mirrored, matching the original shared seated sequence")

	for seconds in [.1,.4,1.1,4.2,5.75,5.92]:
		var game := fixture()
		game.apply_hit()
		advance(game,seconds)
		var settings := GameSettings.new()
		settings.hit_recovery_seconds = 2.0 # Applies to the next hit only.
		var resumed := GameModel.new(settings)
		check(resumed.restore(JSON.parse_string(JSON.stringify(game.snapshot()))), "hit snapshot restores")
		check(resumed.paused and is_equal_approx(resumed.stun,game.stun) and resumed.hit_duration == 6 and is_equal_approx(resumed.immunity,game.immunity), "Continue preserves the active hit's duration and remaining phase after a tuning change")
		var saved := resumed.snapshot()
		resumed.step(.1,Vector2.RIGHT)
		check(resumed.snapshot() == saved, "pause freezes recovery, immunity, clock, position and snow")
		resumed.paused = false
		advance(game,.11)
		advance(resumed,.11)
		check(is_equal_approx(resumed.stun,game.stun) and resumed.player == game.player and resumed.snow.cells == game.snow.cells, "resumed recovery advances identically")

	var legacy := fixture().snapshot()
	legacy.erase("hit_duration")
	legacy.stun = .6
	legacy.immunity = 2.4
	var restored := fixture()
	check(restored.restore(legacy) and restored.stun == .6 and restored.hit_duration == 1, "legacy one-second stuns finish their remaining duration")
	for value in [0,-1,11,"six",null,INF,NAN]:
		var bad := fixture().snapshot()
		bad.hit_duration = value
		check(not restored.restore(bad), "invalid saved reaction duration rejected: %s" % str(value))
	var game := fixture()
	game.time_left = 2.0
	game.apply_hit()
	check(game.time_left == 2.0 and game.state == "playing" and game.stun == 6, "a hit near the deadline does not instantly expire the round")
	advance(game,1.0,Vector2.RIGHT)
	check(is_equal_approx(game.time_left,1.0) and is_equal_approx(game.stun,5.0) and game.state == "playing", "the seated caretaker loses time only through the normal countdown")
	advance(game,1.01,Vector2.RIGHT)
	check(game.state == "timeout" and game.stun == 0 and game.hazards.is_empty(), "timeout interrupts a hit safely and starts Santa's fall")
	game = fixture()
	game.apply_hit()
	game.snow.brush(Vector2(.5,.5),Vector2.ONE * 2,255)
	game.step(.01,Vector2.RIGHT)
	check(game.state == "returning" and game.stun == 0, "cleared stairs secure the round and cancel recovery")
	game.apply_hit()
	check(game.state == "returning" and game.stun == 0 and game.round_hits == 1, "safe return cannot receive a new knockdown")
	game.begin_round(1)
	check(game.stun == 0 and game.immunity == 0 and game.round_hits == 0, "new rounds reset the reaction")
	game = fixture()
	game.apply_hit()
	game.stun = .03
	game.immunity = 1.83
	var start := game.player
	game.step(.1,Vector2.RIGHT)
	var expected := GameModel.movement_target(start,Vector2.RIGHT,.07 * game.settings.player_speed_multiplier,GameModel.SIDE_WALK_SPEED)
	check(game.stun == 0 and game.player.distance_to(expected) < .00001, "a tick crossing recovery end grants only its remaining movement time")

	var report := {"checks":checks,"failures":failures,"recovery_seconds":6.0}
	var file := FileAccess.open("res://builds/hit-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
