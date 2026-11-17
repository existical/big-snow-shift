extends SceneTree

var checks := 0
var failures: Array[String] = []
const DIRECTIONS := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func prepared(depth: int, strength: int = 255, speed: float = 1.75) -> GameModel:
	var tuning := GameSettings.new()
	tuning.player_speed_multiplier = speed
	tuning.snow_per_scoop = strength
	var model := GameModel.new(tuning)
	model.start(84)
	model.player = Vector2(.5,.55)
	model.spawn_countdown = 999
	model.snow.cells.fill(depth)
	model.snow.piles.fill(maxi(0, depth - 255))
	model.snow.remaining = depth * SnowField.WIDTH * SnowField.HEIGHT
	return model

func contact_at(model: GameModel, direction: Vector2) -> Vector2:
	return StairSurface.unproject(GameModel.horizontal_contact(model.player, direction)) if direction.x != 0 else GameModel.vertical_contact(model.player, direction)

func index_at(point: Vector2) -> int:
	return floori(point.y * SnowField.HEIGHT) * SnowField.WIDTH + floori(point.x * SnowField.WIDTH)

func run() -> void:
	for direction in DIRECTIONS:
		for strength in [128, 255, 510]:
			var model := prepared(765, strength)
			var contact := contact_at(model, direction)
			var index := index_at(contact)
			var scoops := 0
			while model.snow.cells[index] > 0 and scoops < 8:
				var before := model.snow.cells.duplicate()
				var previous_height := model.snow.surface_height(contact)
				var previous_mass := model.snow.remaining
				check(model.scoop_amount(model.player, direction) > 0 and model.snow.cells == before, "probing a pile never changes its depth")
				var removed := model.scoop_amount(model.player, direction, true)
				var expected := maxi(0, before[index] - strength)
				check(model.snow.cells[index] == expected and model.snow.piles[index] == maxi(0, expected - 255), "scoop removes upper snow first direction=%s strength=%d" % [direction, strength])
				var correct_mass := previous_mass - model.snow.remaining == removed
				var actual_mass := 0
				var bounded := true
				for i in before.size():
					var difference := before[i] - model.snow.cells[i]
					bounded = bounded and difference >= 0 and difference <= strength
					actual_mass += model.snow.cells[i]
				check(correct_mass and bounded and actual_mass == model.snow.remaining, "partial removal preserves exact mass and never exceeds scoop depth")
				check(model.snow.surface_height(contact) < previous_height and model.snow.dirty, "each scoop visibly lowers the affected snow surface")
				if expected > 0:
					var mask := model.snow.image()
					var pixel := mask.get_pixel(floori(contact.x * mask.get_width()), floori(contact.y * mask.get_height()))
					check(pixel.g > .95, "remaining snow stays opaque after a partial scoop")
				scoops += 1
			check(scoops == ceili(765.0 / strength), "configured strength determines the number of scoops")

	# Ordinary depth clears once; uniform deep lanes require repeated impacts.
	# Use the real step clock and movement gate at both coarse and normal rates.
	for speed in [1.0, 1.75, 3.0]:
		for fps in [10, 60]:
			for direction in DIRECTIONS:
				var model := prepared(765, 255, speed)
				var contact := contact_at(model, direction)
				var index := index_at(contact)
				var snapshots: Array[Dictionary] = []
				var record := func(amount: int): snapshots.append({"depth":model.snow.cells[index],"phase":model.shovel_time,"pose":model.pose_frame(),"amount":amount})
				model.snow_cleared.connect(record)
				var safe := true
				for tick in ceili(3.0 * fps / speed):
					var before := model.player
					model.step(1.0 / fps, direction)
					safe = safe and (before == model.player or not model.movement_blocked(before, model.player, direction))
				var expected_pose := 11 if direction.x != 0 else (19 if direction.y < 0 else 27)
				check(snapshots.size() >= 3 and snapshots[0].depth == 510 and snapshots[1].depth == 255 and snapshots[2].depth == 0, "deep lane takes three scoops speed=%.2f fps=%d direction=%s" % [speed,fps,direction])
				check(safe and snapshots.all(func(sample: Dictionary): return sample.pose == expected_pose and absf(sample.phase - ShovelStroke.impact_time(direction)) < .00001 and sample.amount > 0), "deep clearing remains gated and synchronized at every impact")
				model.snow_cleared.disconnect(record)
				var ordinary := prepared(255, 255, speed)
				index = index_at(contact_at(ordinary, direction))
				for tick in ceili((ShovelStroke.impact_time(direction) / speed + .01) * fps):
					ordinary.step(1.0 / fps, direction)
				check(ordinary.snow.cells[index] == 0, "ordinary snow takes one scoop at every tested pace")

	var model := prepared(765)
	var contact := contact_at(model, Vector2.RIGHT)
	model.step(.1, Vector2.RIGHT)
	model.step(.1, Vector2.RIGHT)
	model.step(.1, Vector2.RIGHT)
	check(model.snow.cells[index_at(contact)] == 510, "fixture is saved after exactly one partial scoop")
	var saved := model.snapshot()
	var restored := prepared(255)
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))), "partly dug piles restore from the existing save format")
	model.spawn_countdown = restored.spawn_countdown
	restored.paused = false
	for tick in 70:
		model.step(1.0 / 60, Vector2.RIGHT)
		restored.step(1.0 / 60, Vector2.RIGHT)
	check(model.snow.cells == restored.snow.cells and model.snow.piles == restored.snow.piles and model.player.distance_to(restored.player) < .00001, "continued partial piles clear identically without an extra or missing scoop")
	var retuned := prepared(255, 128)
	check(retuned.restore(saved) and retuned.settings.snow_per_scoop == 255, "continued saves preserve their saved scoop strength")
	var report := {"checks":checks,"failures":failures,"speed":GameSettings.new().player_speed_multiplier,"snow_per_scoop":GameSettings.new().snow_per_scoop}
	var file := FileAccess.open("res://builds/depth-test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
