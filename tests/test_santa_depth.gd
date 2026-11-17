extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func scene(stage: int, seconds: float, state: String = "greeting") -> GameModel:
	var game := GameModel.new()
	game.start(123)
	game.begin_round(stage)
	game.snow.brush(Vector2(.5,.5),Vector2.ONE * 2,255)
	game.state = state
	game.ending_time = seconds
	game.player = RoundEnding.DOOR_TARGET
	return game

func _initialize() -> void:
	for stage in 3:
		for fps in [10,60,120]:
			var closed_safe := true
			var joined_safe := true
			var crops_safe := true
			var closing_safe := true
			for tick in int((RoundEnding.duration(stage) + .2) * fps) + 1:
				var seconds := tick / float(fps)
				var present := RoundEnding.santa_presence(stage,seconds) > 0
				var inside := RoundEnding.santa_inside(stage,seconds)
				var opening := RoundEnding.door_open(stage,seconds)
				var joined := EndingAnimator.joined_pose(stage,seconds)
				closed_safe = closed_safe and (opening > .000001 or not present or inside)
				joined_safe = joined_safe and (not joined or (present and not inside and opening >= .999999))
				if seconds >= RoundEnding.exit_time(stage) and opening < .999999:
					closing_safe = closing_safe and (not present or inside)
				if not joined:
					crops_safe = crops_safe and EndingAnimator.caretaker_frame(stage,seconds) in [0,10] and EndingAnimator.santa_frame(stage,seconds) in [2,7,12]
			check(closed_safe,"closed doors never have exterior Santa, stage %d at %d FPS" % [stage,fps])
			check(joined_safe,"shared action sprites only draw outside a fully open door, stage %d at %d FPS" % [stage,fps])
			check(crops_safe,"entry/return/hidden poses use clean actor sources, stage %d at %d FPS" % [stage,fps])
			if stage < 2: check(closing_safe,"doors close only after Santa has moved inside, stage %d at %d FPS" % [stage,fps])
		var exit := RoundEnding.exit_time(stage)
		var boundaries := [.6,1.35,RoundEnding.duration(stage)]
		if stage < 2: boundaries.append_array([exit,exit + .72,exit + .9,exit + 1.5])
		for boundary in boundaries:
			for offset in [-.000001,0.0,.000001]:
				var seconds := clampf(boundary + offset,0,RoundEnding.duration(stage))
				var game := scene(stage,seconds)
				var restored := GameModel.new()
				var valid: bool = restored.restore(JSON.parse_string(JSON.stringify(game.snapshot())))
				check(valid and restored.paused and RoundEnding.santa_inside(stage,restored.ending_time) == RoundEnding.santa_inside(stage,seconds) and EndingAnimator.joined_pose(stage,restored.ending_time) == EndingAnimator.joined_pose(stage,seconds) and is_equal_approx(RoundEnding.door_open(stage,seconds),RoundEnding.door_open(stage,restored.ending_time)),"Continue preserves doorway depth at stage %d phase %.6f" % [stage,seconds])
	check(EndingAnimator.caretaker_frame(0,6) == 0 and EndingAnimator.caretaker_frame(1,6.3) == 10,"closed success scenes retain only a clean caretaker, with the gift in round two")
	check(EndingAnimator.santa_frame(0,1) == 2 and EndingAnimator.santa_frame(1,1) == 7 and EndingAnimator.santa_frame(2,1) == 12,"entry poses retain each round's neutral, gift or wand prop")
	check(EndingAnimator.santa_frame(0,5.2) == 2 and EndingAnimator.santa_frame(1,5.4) == 2,"returning Santa uses the separated neutral pose rather than crossing waving mittens")
	var image := EndingAnimator.ACTORS.get_image()
	if image.is_compressed(): image.decompress()
	var cell := Vector2(image.get_size()) / Vector2(4,4)
	# Source-art invariants: solo pose 0 has no right-hand actor. The gift
	# caretaker's .47 cut lies inside a transparent seam, not through a mitten.
	for setup in [[0,.48,1.0],[10,.46,.49]]:
		var frame: int = setup[0]
		var maximum := 0.0
		for y in range(0,floori(cell.y)):
			for x in range(ceili(setup[1] * cell.x),floori(setup[2] * cell.x)):
				var point := Vector2i(roundi((frame % 4) * image.get_width() / 4.0) + x,roundi(floori(frame / 4.0) * image.get_height() / 4.0) + y)
				maximum = maxf(maximum,image.get_pixelv(point).a)
		check(maximum < .05,"clean caretaker atlas guard band contains no opaque Santa pixels, pose %d" % frame)
	for fps in [10,60,120]:
		var safe := true
		for tick in int(RoundTimeout.DURATION * fps) + 1:
			var seconds := tick / float(fps)
			safe = safe and (RoundTimeout.santa_inside(seconds) or RoundTimeout.door_open(seconds) >= .999999)
		check(safe,"timeout Santa crosses to the foreground only after full opening at %d FPS" % fps)
	var legacy := scene(0,0,"lost")
	check(not legacy.is_timeout_scene(),"legacy lost saves with no fall phase do not draw doorway Santa")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/santa-depth-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
