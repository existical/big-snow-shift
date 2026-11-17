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

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 45
	var field := SnowField.new()
	field.generate(1, rng)
	field.brush(Vector2(.5,.5), Vector2.ONE * 2, -255)
	var center := Vector2(.5,.6)
	var index := floori(center.y * SnowField.HEIGHT) * SnowField.WIDTH + floori(center.x * SnowField.WIDTH)
	var base := field.cells.duplicate()
	var initial_height := field.surface_height(center)
	var before := field.remaining
	var added := field.add_pile(center, 160)
	check(added > 0 and field.remaining == before + added, "impact adds accounted snow mass")
	check(field.cells[index] > 255 and field.piles[index] > 0, "full-depth snow can accumulate an impact above the old byte ceiling")
	check(field.surface_height(center) > initial_height + 10, "impact raises existing snow visibly")
	var first_height := field.surface_height(center)
	field.add_pile(center, 160)
	check(field.surface_height(center) > first_height + 3, "a second impact raises the same mound again")
	var preserved := true
	var total := 0
	for i in field.cells.size():
		preserved = preserved and field.cells[i] - field.piles[i] == base[i]
		total += field.cells[i]
	check(preserved and total == field.remaining, "stacking preserves the base layer and exact total")
	for hit in 20:
		field.add_pile(center, 180)
	check(field.piles[index] <= SnowField.MAX_PILE_DEPTH and field.surface_height(center) < SnowField.RENDER_PAD, "extreme repeated impacts stay within storage and rendering bounds")
	var restored := SnowField.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(field.snapshot()))), "new pile snapshot restores")
	check(restored.cells == field.cells and restored.piles == field.piles and restored.remaining == field.remaining, "pile depth and mass survive JSON save/restore exactly")
	var old := SnowField.new()
	old.generate(.7, rng)
	var legacy := {"cells":Marshalls.raw_to_base64(PackedByteArray(Array(old.cells))), "initial":old.initial}
	check(restored.restore(legacy) and restored.cells == old.cells and not restored.has_visible_piles(), "pre-0.8 byte-depth saves upgrade without inventing piles")
	var broken := field.snapshot()
	broken.piles = "AAAA"
	check(not restored.restore(broken), "truncated pile data is rejected")
	var invalid := field.piles.duplicate()
	invalid[index] = SnowField.MAX_PILE_DEPTH + 1
	broken = field.snapshot()
	broken.piles = Marshalls.raw_to_base64(invalid.to_byte_array())
	check(not restored.restore(broken), "out-of-range pile data is rejected")
	field.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
	check(field.remaining == 0 and not field.has_visible_piles(), "full clearing removes base and piled snow together")
	field.add_pile(center, 160, 1.5)
	var distinct: Array[int] = []
	for depth in field.piles:
		if depth > 0 and depth not in distinct:
			distinct.append(depth)
	check(distinct.size() > 8 and field.piles[index] > 70, "mound has a graded dome instead of a flat cylinder")
	var rim := index + 5
	check(field.piles[rim] < field.piles[index] * .4, "mound height tapers toward its edge")
	var mask := field.image()
	var pixel := mask.get_pixel(floori(center.x * mask.get_width()), floori(center.y * mask.get_height()))
	check(pixel.r < .01 and pixel.g > .95 and pixel.b > .1, "bare-stone mound uses opaque coverage and the separate height channel")
	for edge in [Vector2.ZERO, Vector2.ONE, Vector2(0,.5), Vector2(1,.5)]:
		before = field.remaining
		check(field.add_pile(edge, 160) > 0 and field.remaining > before, "edge impact stays inside the stair field %s" % edge)
	var model := baseline_model()
	for stage in 3:
		model.start(46)
		model.begin_round(stage)
		before = model.snow.remaining
		var height := model.snow.surface_height(center)
		model.hazards.assign([{"x":center.x,"y":center.y,"age":3.0,"warning":1.0,"flight":.5}])
		model.step(.01, Vector2.ZERO)
		check(model.snow.remaining > before and model.snow.surface_height(center) > height, "falling icicle builds a pile in round %d" % (stage + 1))
	model.start(46)
	model.snow.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
	model.snow.add_pile(center, 140)
	model.step(.01, Vector2.ZERO)
	check(model.state == "playing", "a small visible mound must be cleaned even below the residue mass threshold")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		model.start(46)
		model.player = Vector2(.5,.55)
		model.spawn_countdown = 999
		var contact := StairSurface.unproject(GameModel.horizontal_contact(model.player, direction)) if direction.x != 0 else GameModel.vertical_contact(model.player, direction)
		for hit in 3:
			model.snow.add_pile(contact, 160)
		index = floori(contact.y * SnowField.HEIGHT) * SnowField.WIDTH + floori(contact.x * SnowField.WIDTH)
		var depth := model.snow.piles[index]
		var total_depth := model.snow.cells[index]
		for tick in 18:
			model.step(1.0 / 60, direction)
		check(model.snow.piles[index] == depth, "preparation leaves piled snow intact %s" % direction)
		for tick in 24:
			model.step(1.0 / 60, direction)
		check(model.snow.piles[index] == maxi(0, depth - 255) and model.snow.cells[index] == total_depth - 255, "first scoop removes only one layer of a deep pile %s" % direction)
		for tick in 108:
			model.step(1.0 / 60, direction)
		check(model.snow.piles[index] == 0 and model.snow.cells[index] == 0, "repeated scoops remove the stacked pile and its base %s" % direction)
	var world := WinterWorld.new()
	root.add_child(world)
	world.set_process(false)
	model.start(46)
	world.set_model(model)
	var simulation_rng := model.rng.state
	var cells := model.snow.cells.duplicate()
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		world.particles.clear()
		model.facing = direction
		model.moving = true
		model.shoveling = true
		model.shovel_time = ShovelStroke.impact_time(direction)
		world.shovel_burst(6000)
		check(world.particles.size() >= 42, "digging produces a rich snow burst %s" % direction)
		var origin := ShovelRig.contact_world(model.player, direction, model.pose_frame())
		if direction.y < 0:
			origin = StairSurface.project(model.player) + Vector2(0, -ShovelRig.size_at(model.player) * .20)
		var at_tool := world.particles.all(func(p: Dictionary): return p.position.distance_to(origin) < 7)
		check(at_tool, "snow debris originates at the digging tool %s" % direction)
		if direction.x != 0:
			check(world.particles.all(func(p: Dictionary): return signf(p.velocity.x) == direction.x), "sideways snow spray follows the facing direction %s" % direction)
	check(model.rng.state == simulation_rng and model.snow.cells == cells, "visual debris cannot change gameplay snow or RNG")
	world.particles.clear()
	world.shovel_burst(250)
	var small_load := world.particles.size()
	world.particles.clear()
	world.shovel_burst(6000)
	check(world.particles.size() > small_load * 2, "snow spray responds to the amount actually lifted")
	model.paused = true
	var frozen := world.particles.duplicate(true)
	world._process(.1)
	check(world.particles == frozen, "pause freezes emitted snow debris")
	world.advance_particles(2)
	check(world.particles.is_empty(), "snow debris expires instead of accumulating indefinitely")
	world.reduced_motion = true
	world.shovel_burst(6000)
	check(world.particles.size() == 12, "reduced-motion mode limits snow spray")
	world.reduced_motion = false
	for burst in 20:
		world.shovel_burst(12000)
	check(world.particles.size() <= WinterWorld.MAX_PARTICLES, "repeated impacts and scoops respect the particle budget")
	world.queue_free()
	await process_frame
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/pile-test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func baseline_model() -> GameModel:
	# Geometry/timing fixtures use v0.8 player-time units. Full-night runs and
	# tuning tests separately exercise the configured development speed.
	var tuning := GameSettings.new()
	tuning.player_speed_multiplier = 1.0
	return GameModel.new(tuning)
