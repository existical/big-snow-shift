extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	# Contract recovered from the DOS animation table, including every unique frame.
	var sampled: Array[int] = []
	for setup in [[Vector2.RIGHT, false, 0, 7], [Vector2.RIGHT, true, 8, 13], [Vector2.UP, false, 14, 16], [Vector2.UP, true, 17, 21], [Vector2.DOWN, false, 22, 24], [Vector2.DOWN, true, 25, 29]]:
		var seen: Array[int] = []
		for tick in 180:
			var frame := ShovelRig.frame_for(setup[0], true, setup[1], tick / 60.0)
			if frame not in seen:
				seen.append(frame)
			if frame not in sampled:
				sampled.append(frame)
		seen.sort()
		check(seen == range(setup[2], setup[3] + 1), "original animation range %d..%d is complete" % [setup[2], setup[3]])
	for tick in 60:
		var frame := ShovelRig.frame_for(Vector2.ZERO, false, false, tick / 60.0)
		if frame not in sampled:
			sampled.append(frame)
	check(sampled.size() == 32, "all 32 source-matched character poses are reachable")
	for facing in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var contact_game := baseline_model()
		contact_game.start(18)
		contact_game.player = Vector2(.40, .55)
		var old_cells := contact_game.snow.cells.duplicate()
		for tick in 39:
			contact_game.step(1.0 / 60, facing)
		var foot := contact_game.player
		var foot_index := clampi(int(foot.y * SnowField.HEIGHT), 0, SnowField.HEIGHT - 1) * SnowField.WIDTH + clampi(int(foot.x * SnowField.WIDTH), 0, SnowField.WIDTH - 1)
		if absf(facing.y) < .55:
			check(contact_game.snow.cells[foot_index] == old_cells[foot_index], "sideways work leaves snow under the boots intact %s" % facing)
		else:
			check(absf(contact_game.last_cut_point.x - StairSurface.project(foot).x) < ShovelRig.size_at(foot) * .45, "vertical work stays near the character footprint %s" % facing)
		var cut := StairSurface.unproject(contact_game.last_cut_point)
		var cut_index := clampi(int(cut.y * SnowField.HEIGHT), 0, SnowField.HEIGHT - 1) * SnowField.WIDTH + clampi(int(cut.x * SnowField.WIDTH), 0, SnowField.WIDTH - 1)
		check(contact_game.snow.cells[cut_index] < old_cells[cut_index], "snow disappears at the scoop when pushing %s" % facing)
		var expected := GameModel.horizontal_contact(contact_game.player, facing) if absf(facing.y) < .55 else StairSurface.project(GameModel.vertical_contact(contact_game.player, facing))
		check(expected.distance_to(contact_game.last_cut_point) < ShovelRig.size_at(foot) * .17, "last chunk stays within shovel reach after digging %s" % facing)
	var fixed_length := -1.0
	for frame in range(14):
		var pose := ShovelRig.side_transform(142, frame)
		var butt := pose * (Vector2(ShovelRig.SHAFT_START, 0) * 142)
		var tip := pose * (Vector2(ShovelRig.TIP, 0) * 142)
		var length := butt.distance_to(tip)
		if fixed_length < 0:
			fixed_length = length
		check(absf(length - fixed_length) < .001, "complete side shovel retains rigid dimensions in pose %d" % frame)
	# Snow disappears once per digging stroke, with no erasure during recovery.
	var stroke_game := baseline_model()
	stroke_game.start(31)
	var untouched := stroke_game.snow.remaining
	stroke_game.step(.1, Vector2.RIGHT)
	check(stroke_game.snow.remaining == untouched, "preparation does not erase snow")
	for i in 7:
		stroke_game.step(.1, Vector2.RIGHT)
	check(stroke_game.snow.remaining < untouched, "the push phase removes snow")
	var after_push := stroke_game.snow.remaining
	stroke_game.step(.1, Vector2.RIGHT)
	stroke_game.step(.1, Vector2.RIGHT)
	check(stroke_game.snow.remaining == after_push, "lift and return leave the snow unchanged")
	check(stroke_game.player.x < .70, "movement takes more than five seconds to cross the stairs")
	test_horizontal_strips()
	test_vertical_scoops()
	var contact_fine := 0.0
	for i in 60:
		contact_fine += ShovelStroke.contact_seconds(i / 60.0, 1.0 / 60)
	check(absf(contact_fine - ShovelStroke.contact_seconds(0, 1)) < .00001, "stroke cutting time is independent of simulation tick size")
	check(StairSurface.project(Vector2(0,.01)).x > 480 and StairSurface.project(Vector2(1,.01)).x < 790, "top snow edge fits between the painted door posts")
	check(StairSurface.project(Vector2(0,1)).x > 285 and StairSurface.project(Vector2(1,1)).x < 988, "bottom snow edge fits inside the stone rails")
	var coverage_game := baseline_model()
	coverage_game.start(731)
	for stage_index in 3:
		coverage_game.begin_round(stage_index)
		var fully_covered := true
		for amount in coverage_game.snow.cells:
			if amount == 0:
				fully_covered = false
		check(fully_covered, "fresh snowfall covers every tread edge-to-edge in round %d" % (stage_index + 1))
	check(RoofLine.anchor(350).distance_to(Vector2(350,178)) < 2, "left eave attaches below the painted roof snow")
	check(RoofLine.anchor(638).distance_to(Vector2(638,22)) < 2, "central gable is used instead of a floating horizontal spawn line")
	var landing := StairSurface.project(Vector2(.7,.8))
	check(RoofLine.icicle_top(landing, .1, 1.7, .75, 8) == RoofLine.icicle_top(landing, 1.6, 1.7, .75, 46), "growing icicle root remains fixed on the roof")
	check((RoofLine.icicle_top(landing, 2.45, 1.7, .75, 48) + Vector2(0,48)).distance_to(landing) < .001, "falling icicle tip reaches the warned landing point")
	for point in [Vector2.ZERO, Vector2.ONE, Vector2(0.23, 0.71), Vector2(0.5, 0.025)]:
		check(StairSurface.unproject(StairSurface.project(point)).distance_to(point) < 0.00001, "stair projection round trip")
	var game := baseline_model()
	game.start(42)
	var initial := game.snow.remaining
	game.paused = true
	game.step(0.1, Vector2.UP)
	check(game.time_left == float(game.stage().seconds) and game.snow.remaining == initial and game.player == Vector2(0.5, 0.93), "pause freezes simulation")
	game.paused = false
	for i in 180:
		game.step(1.0 / 60, Vector2.UP)
	check(game.snow.remaining < initial and game.player.y >= 0.025, "movement clears snow and remains inside stairs")
	var restored := baseline_model()
	check(restored.restore(JSON.parse_string(JSON.stringify(game.snapshot()))), "JSON run snapshot restores")
	check(restored.paused and restored.snow.cells == game.snow.cells and restored.player == game.player and restored.rng.state == game.rng.state, "restored state matches including snow and RNG")
	restored.paused = false
	for i in 240:
		game.step(1.0 / 60, Vector2.RIGHT)
		restored.step(1.0 / 60, Vector2.RIGHT)
	check(game.snow.cells == restored.snow.cells and game.player == restored.player and game.hazards == restored.hazards and game.rng.state == restored.rng.state and is_equal_approx(game.time_left, restored.time_left), "restored simulation matches through movement and hazard spawns")
	var legacy := game.snapshot()
	legacy.erase("shovel_time")
	legacy.erase("shoveling")
	check(restored.restore(legacy) and restored.shovel_time == 0 and not restored.shoveling, "older saves without a stroke clock remain compatible")
	check(not restored.restore({"stage": 99}), "malformed stage rejected")
	var corrupted := game.snapshot()
	corrupted.snow.cells = "AAAA"
	check(not restored.restore(corrupted), "truncated snow data rejected")
	game.start(1)
	game.hazards = [{"x": 0.5, "y": 0.93, "age": 2.0, "warning": 1.0, "flight": 0.5}]
	game.step(0.01, Vector2.ZERO)
	check(game.round_hits == 1 and game.stun > 0 and is_equal_approx(game.time_left, float(game.stage().seconds) - .01), "ice landing stuns without subtracting extra time")
	game.hazards = [{"x": 0.5, "y": 0.93, "age": 2.0, "warning": 1.0, "flight": 0.5}]
	game.step(0.01, Vector2.ZERO)
	check(game.round_hits == 1, "temporary immunity prevents chained hits")
	game.start(2)
	game.snow.brush(Vector2(0.5, 0.5), Vector2.ONE * 2, 255)
	game.time_left = 0.001
	game.step(0.1, Vector2.ZERO)
	check(game.state == "returning" and game.score == 0 and game.time_left > 0, "last patch secures a safe return before the deadline")
	var residue_game := baseline_model()
	residue_game.start(2)
	residue_game.snow.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
	residue_game.snow.brush(Vector2(.5,.5), Vector2(.01,.01), -8)
	residue_game.step(1.0 / 60, Vector2.ZERO)
	check(residue_game.state == "returning" and residue_game.snow.remaining == 0, "invisible residual snow cannot block the return to Santa")
	for tick in 900:
		if game.state == "returning":
			game.step(1.0 / 60, steer_toward(game, Vector2(.5,.025)))
		else:
			game.step(1.0 / 60, Vector2.ZERO)
	game.next_round()
	check(game.stage_index == 1 and game.state == "playing" and game.score > 0, "next round preserves score")
	game.time_left = 0.001
	game.step(0.1, Vector2.ZERO)
	check(game.state == "timeout" and game.controls_locked(), "deadline starts Santa's slippery-stairs scene")
	for tick in 73:
		game.step(.1, Vector2.ZERO)
	check(game.state == "lost", "retry becomes available after Santa's fall")
	game = GameModel.new() # Full nights use the actual settings file.
	var attempts: Array = []
	for seed_value in [7, 31, 92]:
		game.start(seed_value)
		for round_index in 3:
			play_round(game)
			if game.state == "lost":
				var failed_run := FileAccess.open("res://builds/logs/failed-sweep-%d-%d.json" % [seed_value, round_index], FileAccess.WRITE)
				failed_run.store_string(JSON.stringify(game.snapshot()))
				failed_run.close()
			attempts.append({"seed": seed_value, "round": round_index + 1, "state": game.state, "seconds": snappedf(game.elapsed, 0.01), "hits": game.round_hits})
			check(game.state == ("won" if round_index == 2 else "celebrating"), "sweeping player can complete round %d seed %d; remaining %d" % [round_index + 1, seed_value, game.snow.remaining])
			if game.state == "celebrating":
				game.next_round()
			elif game.state == "lost" and round_index < 2:
				game.begin_round(round_index + 1)
	check(attempts.all(func(attempt: Dictionary): return float(attempt.seconds) >= 75.0), "full round sweeps retain a deliberate pace instead of the old sub-minute clearing")
	var report := {"checks": checks, "failures": failures, "playthroughs": attempts}
	var output := FileAccess.open("res://builds/test-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_horizontal_strips() -> void:
	# Exhaustive across the painted treads, both directions, all six starting
	# animation poses and 10/30/60/120 Hz. Chunks may only vanish on impact.
	for row in 16:
		for direction in [Vector2.LEFT, Vector2.RIGHT]:
			for fps in [10, 30, 60, 120]:
				for phase in 6:
					var model := baseline_model()
					model.start(31)
					model.player = Vector2(.5, clampf(StairSurface.tread_center(row), .025, .975))
					model.spawn_countdown = 999
					model.facing = direction
					model.shoveling = true
					model.shovel_time = phase * ShovelStroke.DURATION / 6
					var initial_cells := model.snow.cells.duplicate()
					var initial_y := model.player.y
					var start := GameModel.horizontal_contact(model.player, direction)
					var start_feet := StairSurface.project(model.player)
					var impacts := 0
					var synchronized := true
					for tick in fps * 2:
						var before := model.snow.remaining
						model.step(1.0 / fps, direction)
						if model.snow.remaining < before:
							impacts += 1
							synchronized = synchronized and model.pose_frame() == 11
					var finish := GameModel.horizontal_contact(model.player, direction)
					var valid := model.player.y == initial_y and start.y == finish.y and synchronized and impacts >= 2 and impacts <= 3
					var distance := absf(StairSurface.project(model.player).x - start_feet.x)
					valid = valid and distance <= GameModel.SIDE_SNOW_SPEED * 2 + .01 and distance > 20
					var trailing_offset: float = direction.x * (ShovelRig.size_at(model.player) * .17 - 1.0)
					start.x -= trailing_offset
					finish.x -= trailing_offset
					for y in SnowField.HEIGHT:
						for x in SnowField.WIDTH:
							var index := y * SnowField.WIDTH + x
							var uv := Vector2((x + .5) / SnowField.WIDTH, (y + .5) / SnowField.HEIGHT)
							if StairSurface.tread_at(uv.y) != row:
								valid = valid and model.snow.cells[index] == initial_cells[index]
							else:
								var world_x := StairSurface.project(uv).x
								if world_x >= minf(start.x, finish.x) and world_x <= maxf(start.x, finish.x):
									valid = valid and model.snow.cells[index] == 0
					check(valid, "synchronized gap-free chunks row=%d direction=%s fps=%d phase=%d" % [row, direction, fps, phase])
	# Every complete pass must reach both rail seams without residue.
	for row in 16:
		var rail_game := baseline_model()
		rail_game.start(22)
		rail_game.player = Vector2(.5, clampf(StairSurface.tread_center(row), .025, .975))
		rail_game.spawn_countdown = 999
		for direction in [Vector2.LEFT, Vector2.RIGHT]:
			for tick in 900:
				rail_game.step(1.0 / 30, direction)
				if (direction.x < 0 and rail_game.player.x <= .02501) or (direction.x > 0 and rail_game.player.x >= .97499):
					break
		check(rail_game.snow.tread_strip(row, 0, 1280) == 0, "complete rail-to-rail pass leaves no snow on tread %d" % row)
	# A small diagonal thumbstick deviation cannot change the active tread.
	var diagonal := baseline_model()
	diagonal.start(8)
	var original_y := diagonal.player.y
	for tick in 60:
		diagonal.step(1.0 / 60, Vector2(1, .2))
	check(diagonal.player.y == original_y, "sideways thumbstick movement locks to one stair level")
	for direction in [Vector2.LEFT, Vector2.RIGHT]:
		var slow := baseline_model()
		slow.start(17)
		slow.player = Vector2(.5, .7)
		for tick in 40:
			slow.step(1.0 / 60, direction * .11)
		var offset := slow.last_cut_point.x - StairSurface.project(slow.player).x
		check(signf(offset) == direction.x, "gentle analog movement clears on the facing side %s" % direction)
	# Facing reversal must not connect opposite blade positions through the body.
	var turning := baseline_model()
	turning.start(8)
	turning.player = Vector2(.5, .6)
	for tick in 40:
		turning.step(1.0 / 60, Vector2.RIGHT)
	for tick in 40:
		turning.step(1.0 / 60, Vector2.LEFT)
	var foot := turning.player
	var index := floori(foot.y * SnowField.HEIGHT) * SnowField.WIDTH + floori(foot.x * SnowField.WIDTH)
	check(turning.snow.cells[index] > 0, "turning does not erase a bridge between the two blade positions")

func test_vertical_scoops() -> void:
	var returning := baseline_model()
	returning.start(91)
	returning.spawn_countdown = 999
	returning.player = Vector2(.5,.85)
	for tick in 360:
		returning.step(1.0 / 60, Vector2.UP)
	var turn_at := returning.player.y
	for tick in 90:
		returning.step(1.0 / 60, Vector2.DOWN)
	check((returning.player.y - turn_at) * (StairSurface.BOTTOM - StairSurface.TOP) > GameModel.VERTICAL_SNOW_SPEED * 1.5 * 2, "return trip down a cleared vertical lane is faster than digging")
	for direction in [Vector2.UP, Vector2.DOWN]:
		for fps in [10, 30, 60, 120]:
			for x in [.2, .5, .8]:
				var model := baseline_model()
				model.start(88)
				model.spawn_countdown = 999
				model.player = Vector2(x, .93 if direction.y < 0 else .07)
				var initial_position := model.player
				var original_cells := model.snow.cells.duplicate()
				var synchronized := true
				var safe_travel := true
				var cuts := 0
				for tick in fps * 15:
					var previous := model.player
					var before := model.snow.remaining
					model.step(1.0 / fps, direction)
					if model.snow.remaining < before:
						cuts += 1
						synchronized = synchronized and model.pose_frame() == (19 if direction.y < 0 else 27)
					if previous.distance_to(model.player) > .000001:
						safe_travel = safe_travel and not model.movement_blocked(previous, model.player, direction)
				var distance := absf(model.player.y - initial_position.y) * (StairSurface.BOTTOM - StairSurface.TOP)
				check(synchronized and cuts >= 15 and cuts <= 17, "vertical chunks follow digging frames direction=%s fps=%d lane=%.1f" % [direction, fps, x])
				check(safe_travel and distance <= GameModel.VERTICAL_SNOW_SPEED * 15 + .01 and distance > 150, "vertical movement stays within cleared snow at work speed direction=%s fps=%d lane=%.1f" % [direction, fps, x])
				# The central travelled corridor must contain no untouched islands.
				var gap_free := true
				for i in model.snow.cells.size():
					var uv := Vector2((i % SnowField.WIDTH + .5) / SnowField.WIDTH, (floori(float(i) / SnowField.WIDTH) + .5) / SnowField.HEIGHT)
					if uv.y < minf(initial_position.y, model.player.y) + .04 or uv.y > maxf(initial_position.y, model.player.y) - .04:
						continue
					var contact := GameModel.vertical_contact(Vector2(x, uv.y), direction)
					if absf(uv.x - contact.x) < .018:
						gap_free = gap_free and model.snow.cells[i] == 0
				check(gap_free and original_cells != model.snow.cells, "vertical pass leaves a continuous cleared lane direction=%s fps=%d lane=%.1f" % [direction, fps, x])
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var snowy := baseline_model()
		snowy.start(91)
		snowy.player = Vector2(.5, .5)
		var bare := baseline_model()
		bare.start(91)
		bare.player = snowy.player
		bare.snow.brush(Vector2(.5,.5), Vector2(.45,.45), 255)
		var start := snowy.player
		for tick in 60:
			snowy.step(1.0 / 60, direction)
			bare.step(1.0 / 60, direction)
		check(bare.player.distance_to(start) > snowy.player.distance_to(start) * 2, "cleared stone permits faster movement %s" % direction)
		# The last piece of a small deposit must not impose slow travel for the
		# remainder of the lift animation once the surrounding lane is bare.
		bare.start(91)
		bare.player = Vector2(.5,.5)
		bare.snow.brush(Vector2(.5,.5), Vector2(.45,.45), 255)
		var point := StairSurface.unproject(GameModel.horizontal_contact(bare.player, direction)) if direction.x != 0 else GameModel.vertical_contact(bare.player, direction)
		bare.snow.brush(point, Vector2(.015,.012), -30)
		for tick in (5 if direction.x != 0 else 4):
			bare.step(.1, direction)
		var before := StairSurface.project(bare.player)
		bare.step(.1, direction)
		var work_speed := GameModel.SIDE_SNOW_SPEED if direction.x != 0 else GameModel.VERTICAL_SNOW_SPEED
		check(before.distance_to(StairSurface.project(bare.player)) > work_speed * .2 and bare.shoveling, "cleared deposit restores walking speed during the lift %s" % direction)
		# Saving immediately before contact must neither skip nor duplicate a scoop.
		snowy.start(91)
		snowy.player = Vector2(.5,.5)
		for tick in 3:
			snowy.step(.1, direction)
		var saved := baseline_model()
		saved.restore(JSON.parse_string(JSON.stringify(snowy.snapshot())))
		saved.paused = false
		for tick in 120:
			snowy.step(1.0 / 60, direction)
			saved.step(1.0 / 60, direction)
		check(saved.snow.cells == snowy.snow.cells and saved.player == snowy.player and is_equal_approx(saved.shovel_time, snowy.shovel_time), "stroke and movement resume identically after saving %s" % direction)

func feet_for_snow(target: Vector2, direction: Vector2) -> Vector2:
	var feet := target
	if direction.x != 0:
		feet.y = clampf(StairSurface.tread_center(StairSurface.tread_at(target.y)), .025, .975)
	var target_world := StairSurface.project(target)
	for i in 4:
		var contact := GameModel.horizontal_contact(feet, direction) if direction.x != 0 else StairSurface.project(GameModel.vertical_contact(feet, direction))
		var offset := target_world - contact
		if direction.x != 0:
			offset.y = 0
		feet = StairSurface.unproject(StairSurface.project(feet) + offset)
	return StairSurface.constrain(feet)

func play_round(game: GameModel) -> void:
	# Alternate rail-to-rail passes. Enter each new tread one tool-length in
	# from the rail, clean the entry edge outward, then sweep the entire tread.
	# This also clears the snow behind the initial blade position. No teleports.
	var targets: Array[Vector2] = []
	var previous_y := game.player.y
	for row in range(15, -1, -1):
		var y := clampf(StairSurface.tread_center(row), .025, .975)
		var left_entry := row % 2 == 1
		var edge := .025 if left_entry else .975
		var feet := Vector2(edge, y)
		var reach := absf(GameModel.horizontal_contact(feet, Vector2.RIGHT).x - StairSurface.project(feet).x)
		var entry_world := StairSurface.project(feet) + Vector2((reach * 2 + 8) * (1 if left_entry else -1), 0)
		var entry := StairSurface.constrain(StairSurface.unproject(entry_world))
		targets.append(Vector2(entry.x, previous_y))
		targets.append(entry)
		targets.append(Vector2(edge, y))
		targets.append(Vector2(1.0 - edge, y))
		previous_y = y
	var target_index := 0
	var snow_target := -1
	var aim := Vector2.RIGHT
	var dwell := 0.0
	var destination := Vector2.ZERO
	for tick in ceili(float(game.stage().seconds) * 60) + 1024:
		if game.state == "returning":
			game.step(1.0 / 60, steer_toward(game, Vector2(.5,.025)))
			continue
		if game.state in ["greeting", "timeout"]:
			game.step(1.0 / 60, Vector2.ZERO)
			continue
		if game.state != "playing":
			return
		if target_index < targets.size():
			destination = targets[target_index]
			if (game.player - destination).abs().x < .002 and (game.player - destination).abs().y < .002:
				target_index += 1
				if target_index % 4 == 0:
					print("SWEEP round=", game.stage_index + 1, " row=", 16 - target_index / 4, " time=", snappedf(game.elapsed, .1), " remaining=", game.snow.remaining)
				continue
			game.step(1.0 / 60, steer_toward(game, destination))
			continue
		if snow_target < 0 or game.snow.cells[snow_target] == 0:
			var best := INF
			dwell = 0.0
			snow_target = -1
			var candidates: Array[Vector2] = []
			for i in game.snow.cells.size():
				if game.snow.cells[i] > 0:
					# Aim at a mound's center, as a player can see it, rather than
					# repeatedly shaving its one-unit peripheral cells first.
					if game.snow.piles[i] > 0 and game.snow.cells[i] == game.snow.piles[i]:
						var peak := true
						for offset in [-SnowField.WIDTH, -1, 1, SnowField.WIDTH]:
							var neighbor: int = i + offset
							if neighbor >= 0 and neighbor < game.snow.piles.size() and abs((neighbor % SnowField.WIDTH) - (i % SnowField.WIDTH)) <= 1 and game.snow.piles[neighbor] > game.snow.piles[i]:
								peak = false
						if not peak:
							continue
					var uv := Vector2((i % SnowField.WIDTH + .5) / SnowField.WIDTH, (floori(float(i) / SnowField.WIDTH) + .5) / SnowField.HEIGHT)
					candidates.append(Vector2(uv.distance_squared_to(game.player), i))
			candidates.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
			var examined := 0
			for candidate in candidates:
				if examined >= 32 and best < INF:
					break
				examined += 1
				var i := int(candidate.y)
				var target := Vector2((i % SnowField.WIDTH + .5) / SnowField.WIDTH, (floori(float(i) / SnowField.WIDTH) + .5) / SnowField.HEIGHT)
				for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
					var feet := feet_for_snow(target, direction)
					var contact := GameModel.horizontal_contact(feet, direction) if direction.x != 0 else StairSurface.project(GameModel.vertical_contact(feet, direction))
					var miss := absf(contact.x - StairSurface.project(target).x) if direction.x != 0 else contact.distance_to(StairSurface.project(target))
					if miss > 9:
						continue
					var cost := feet.distance_to(game.player)
					if cost < best:
						best = cost
						destination = feet
						aim = direction
						snow_target = i
			if snow_target < 0:
				game.step(1.0 / 60, Vector2.ZERO)
				return
		var difference := destination - game.player
		if (absf(difference.x) >= .002 or absf(difference.y) >= .002) and dwell <= 0:
			game.step(1.0 / 60, steer_toward(game, destination))
		else:
			if dwell <= 0:
				dwell = 1.1
			game.step(1.0 / 60, aim * .11)
			dwell -= 1.0 / 60

func steer_toward(game: GameModel, target: Vector2) -> Vector2:
	# Release the stick as a waypoint approaches; full-speed cardinal input
	# overshoots sub-pixel goals and can alternate directions without arriving.
	var difference := target - game.player
	if absf(difference.y) >= .002:
		var distance := absf(difference.y) * (StairSurface.BOTTOM - StairSurface.TOP)
		return Vector2(0, signf(difference.y)) * clampf(distance * 60 / (GameModel.VERTICAL_WALK_SPEED * game.settings.player_speed_multiplier), .11, 1)
	var distance := absf(StairSurface.project(Vector2(target.x, game.player.y)).x - StairSurface.project(game.player).x)
	return Vector2(signf(difference.x), 0) * clampf(distance * 60 / (GameModel.SIDE_WALK_SPEED * game.settings.player_speed_multiplier), .11, 1)

func baseline_model() -> GameModel:
	# Geometry/timing fixtures use v0.8 player-time units. Full-night runs and
	# tuning tests separately exercise the configured development speed.
	var tuning := GameSettings.new()
	tuning.player_speed_multiplier = 1.0
	return GameModel.new(tuning)
