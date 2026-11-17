extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	var valid := true
	for frame in 16:
		var region := IciclePainter.bounds(frame)
		valid = valid and region.has_area() and region.position.x >= 0 and region.position.y >= 0 and region.end.x <= 1 and region.end.y <= 1
		if frame < 12:
			valid = valid and region.has_point(IciclePainter.vector(IciclePainter.data(frame).root)) and region.has_point(IciclePainter.vector(IciclePainter.data(frame).tip)) and float(IciclePainter.data(frame).span) > 0
	check(valid,"all painted bodies, collar and fragments have valid isolated atlas regions and anchors")
	for frame in 12:
		var top := Vector2(638,22)
		var transform := IciclePainter.body_transform(frame,top,Vector2(20,48))
		var root := IciclePainter.vector(IciclePainter.data(frame).root)
		var tip := IciclePainter.vector(IciclePainter.data(frame).tip)
		check((transform * root).distance_to(top) < .001 and (transform * tip).distance_to(top + Vector2(0,48)) < .001,"painted root and tip register exactly in body frame %d" % frame)
	var points := [Vector2(.2,.6),Vector2(.5,.6),Vector2(.4,.8)]
	var reached: Array[int] = []
	var stable := true
	for point in points:
		var values: Array = JSON.parse_string(JSON.stringify([point.x,point.y]))
		stable = stable and IciclePainter.variant_for(point) == IciclePainter.variant_for(Vector2(values[0],values[1]))
		for age in [0,.65,1.2,1.9,2.3]:
			var frame := IciclePainter.frame_at(point,age,2)
			if frame not in reached: reached.append(frame)
	reached.sort()
	check(reached == range(12),"all three variants and four growth stages are reachable; falling keeps the mature frame")
	check(stable,"visual variants survive save round-trips without RNG state")
	var game := GameModel.new()
	game.start(123)
	for point in points:
		for piled in [false,true]:
			if piled: game.snow.add_pile(point,180)
			var target := StairSurface.project(point) - Vector2(0,game.snow.surface_height(point))
			var size := IciclePainter.size_at(2.75,2)
			var frame := IciclePainter.frame_at(point,2.75,2)
			var transform := IciclePainter.body_transform(frame,RoofLine.icicle_top(target,2.75,2,.75,size.y),size)
			check((transform * IciclePainter.vector(IciclePainter.data(frame).tip)).distance_to(target) < .001,"visible painted tip reaches the warned surface, including pile height")
		var attached := true
		for age in [.1,1.0,1.99]:
			var target := StairSurface.project(point)
			var size := IciclePainter.size_at(age,2)
			var frame := IciclePainter.frame_at(point,age,2)
			var transform := IciclePainter.body_transform(frame,RoofLine.icicle_top(target,age,2,.75,size.y),size)
			attached = attached and (transform * IciclePainter.vector(IciclePainter.data(frame).root)).distance_to(RoofLine.anchor(target.x)) < .001
		check(attached,"all growing stages stay fixed to the roof snow")
	check(IciclePainter.size_at(2,2) == Vector2(20,48) and IciclePainter.size_at(0,2) == Vector2(6,3),"the original hazard's growth size is preserved")
	var gentle := true
	for tick in 300:
		gentle = gentle and IciclePainter.glint_strength(tick / 100.0,2,true) == 0
	check(gentle and IciclePainter.glint_strength(1.6,2,false) == 0 and IciclePainter.glint_strength(1.86,2,false) > .8 and IciclePainter.glint_strength(2,2,false) == 0,"a single late-warning glint is disabled by reduced motion and ends at detachment")
	check(IciclePainter.collar_alpha(1.99,2) == 1 and IciclePainter.collar_alpha(2.1,2) > 0 and IciclePainter.collar_alpha(2.23,2) == 0,"the roof collar fades locally after detachment")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/icicle-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
