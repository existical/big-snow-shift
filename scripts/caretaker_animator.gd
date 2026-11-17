class_name CaretakerAnimator
extends RefCounted

const BODY = preload("res://assets/art/caretaker_32_v05.png")
const PIVOT = ShovelRig.PIVOT
const GRIPS = ShovelRig.GRIPS

static func frame_for(direction: Vector2, moving: bool, working: bool, elapsed: float, stunned: bool = false, stroke_time: float = -1.0) -> int:
	return ShovelRig.frame_for(direction, moving, working, elapsed, stunned, stroke_time)

static func draw(canvas: Node2D, feet: Vector2, size: float, frame: int, flip: float, sway: float, tint: Color, _grounded: bool = false, _vertical: float = 0.0) -> void:
	var pose := Transform2D(sway, Vector2(flip, 1), 0, feet)
	var cell := BODY.get_size() / Vector2(4, 8)
	var source := Rect2(Vector2(frame % 4, floori(frame / 4.0)) * cell, cell)
	canvas.draw_set_transform_matrix(pose)
	canvas.draw_texture_rect_region(BODY, Rect2(-PIVOT * size, Vector2.ONE * size), source, tint)
	# In MAN14..21 the original tool is hidden behind the torso.
	if not ShovelRig.is_back(frame):
		draw_tool(canvas, pose, size, frame, tint)
		canvas.draw_set_transform_matrix(pose)
		for hand in (1 if frame >= 30 else 2):
			var grip: Vector2 = GRIPS[frame][hand]
			var patch := Rect2(grip - Vector2(.065,.060), Vector2(.13,.12))
			canvas.draw_texture_rect_region(BODY, Rect2((patch.position - PIVOT) * size, patch.size * size), Rect2(source.position + patch.position * cell, patch.size * cell), tint)
	elif frame in [19, 21]:
		# The source rear frames reveal the tossed snow, while hiding the tool.
		var shoulder := Vector2(.27 if frame == 21 else .68, .34)
		for i in 4:
			canvas.draw_circle((shoulder - PIVOT + Vector2(sin(i * 2.3) * .035, -i * .045)) * size, size * (.014 - i * .002), Color("effbff") * tint)
	canvas.draw_set_transform(Vector2.ZERO)

static func draw_tool(canvas: Node2D, pose: Transform2D, size: float, frame: int, tint: Color) -> void:
	var transform := pose * ShovelRig.tool_transform(size, frame)
	transform = transform.scaled_local(ShovelRig.projection(frame) * size)
	canvas.draw_set_transform_matrix(transform)
	# All tool parts, including the grain, share one fixed geometry and transform.
	canvas.draw_line(Vector2(ShovelRig.SHAFT_START, 0), Vector2(.49, 0), Color("754021") * tint, .030, true)
	canvas.draw_line(Vector2(ShovelRig.SHAFT_START, -.004), Vector2(.49, -.004), Color("e5ae60") * tint, .018, true)
	canvas.draw_line(Vector2(-.08, -.009), Vector2(.47, -.009), Color("ffe1a1") * tint, .005, true)
	var profile := ShovelRig.is_side(frame)
	var half_width := .042 if profile else .065
	if frame >= 30:
		half_width = .04
	elif frame == 26:
		half_width = .05
	elif frame in [27, 28]:
		half_width = .023
	var blade := PackedVector2Array([Vector2(.45,-half_width), Vector2(.68,-half_width + .007), Vector2(.69,half_width), Vector2(.45,half_width + .01)])
	canvas.draw_colored_polygon(blade, Color("bc7732") * tint)
	var face := PackedVector2Array([Vector2(.466,-half_width + .01), Vector2(.671,-half_width + .016), Vector2(.676,half_width - .012), Vector2(.466,half_width - .005)])
	canvas.draw_colored_polygon(face, Color("f0bd6e") * tint)
	canvas.draw_line(Vector2(.47,-half_width + .011), Vector2(.67,-half_width + .017), Color("ffdfa0") * tint, .011, true)
	canvas.draw_line(Vector2(.683,-half_width + .012), Vector2(.69,half_width), Color("ffe5ae") * tint, .013, true)
	for stripe in (2 if profile else 4):
		var y := lerpf(-half_width * .6, half_width * .6, stripe / float(1 if profile else 3))
		canvas.draw_line(Vector2(.49,y), Vector2(.66,y + .004), Color("d69b4c") * tint, .004, true)
	canvas.draw_line(Vector2(.46,-half_width), Vector2(.46,half_width + .01), Color("925423") * tint, .021, true)
	if frame in [11, 12, 13, 27, 28, 29]:
		for i in 4:
			var mound := Vector2(.49 + i * .05, -half_width - .004)
			canvas.draw_circle(mound, .032, Color("bbddec") * tint)
			canvas.draw_circle(mound + Vector2(-.004,-.012), .027, Color("f5fcff") * tint)
		if frame in [13, 29]:
			for i in 5:
				canvas.draw_circle(Vector2(.62 + sin(i * 2.4) * .06, -.10 - i * .055), .016 - i * .002, Color("effbff") * tint)
