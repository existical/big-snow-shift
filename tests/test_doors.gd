extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	for openness in [0.0,.1,.25,.5,.75,1.0]:
		var previous := Vector2.ZERO
		for side in 2:
			var hinge := DoorRig.LEFT if side == 0 else DoorRig.RIGHT
			check(DoorRig.project(side,0,DoorRig.SPRING,openness).distance_to(Vector2(hinge,DoorRig.SPRING)) < .00001 and DoorRig.project(side,0,DoorRig.BOTTOM,openness).distance_to(Vector2(hinge,DoorRig.BOTTOM)) < .00001, "hinge axis stays attached side=%d open=%.2f" % [side,openness])
			var surface := DoorRig.surface(side,openness)
			var inside := true
			var valid_uv := true
			for i in surface.vertices.size():
				var point: Vector3 = surface.vertices[i]
				inside = inside and point.x >= DoorRig.LEFT - .0001 and point.x <= DoorRig.RIGHT + .0001 and point.y >= DoorRig.top_at(point.x) - .0001 and point.y <= DoorRig.BOTTOM + .0001
				var uv: Vector2 = surface.uvs[i]
				valid_uv = valid_uv and uv.x >= side * .5 - .0001 and uv.x <= (side + 1) * .5 + .0001 and uv.y >= 0 and uv.y <= 1
			check(inside and valid_uv, "full-height curved leaf stays behind its frame and samples only its own texture side=%d open=%.2f" % [side,openness])
			var free := DoorRig.project(side,DoorRig.HALF_WIDTH,DoorRig.BOTTOM,openness)
			if side == 0: previous = free
			else: check(absf(free.x + previous.x - DoorRig.CENTER * 2) < .00001 and absf(free.y - previous.y) < .00001, "both leaves swing symmetrically at %.2f" % openness)
	var last_gap := -1.0
	var monotonic := true
	for step in 101:
		var openness := step / 100.0
		var left := DoorRig.project(0,DoorRig.HALF_WIDTH,DoorRig.BOTTOM,openness)
		var right := DoorRig.project(1,DoorRig.HALF_WIDTH,DoorRig.BOTTOM,openness)
		var gap := right.x - left.x
		monotonic = monotonic and gap >= last_gap
		last_gap = gap
	check(monotonic and last_gap > 135, "the opening widens smoothly enough for Santa")
	var closed_left := DoorRig.project(0,DoorRig.HALF_WIDTH,DoorRig.TOP,0)
	var closed_right := DoorRig.project(1,DoorRig.HALF_WIDTH,DoorRig.TOP,0)
	check(closed_left == closed_right and closed_left.y == DoorRig.TOP, "closed leaves meet along the full arched top")
	var open_bottom := DoorRig.project(0,DoorRig.HALF_WIDTH,DoorRig.BOTTOM,1)
	check(open_bottom.y < DoorRig.BOTTOM - 10, "the free edge recedes in perspective instead of only squeezing horizontally")
	check(DoorRig.free_edge(0,1)[0].distance_to(DoorRig.free_edge(0,1)[3]) > 1, "an open leaf has visible physical thickness")
	check(RoundEnding.santa_inside(0,1.0) and not RoundEnding.santa_inside(0,1.5), "Santa passes from behind the door to the front at entry")
	check(not RoundEnding.santa_inside(0,4.3) and RoundEnding.santa_inside(0,5.1), "Santa returns behind the panels before they close")
	var opaque := true
	for tick in 600:
		var presence := RoundEnding.santa_presence(0,tick / 100.0)
		opaque = opaque and (presence == 0 or presence == 1)
	check(opaque, "doorway Santa uses opaque visibility rather than cross-fading through the panels")
	check(RoundTimeout.santa_inside(.5) and not RoundTimeout.santa_inside(1.0), "timeout entry uses the same door occlusion before Santa steps out")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/door-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
