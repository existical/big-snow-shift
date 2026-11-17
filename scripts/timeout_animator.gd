class_name TimeoutAnimator
extends RefCounted

const SANTA = preload("res://assets/art/santa_fall_16_v012.png")

static func draw(canvas: Node2D, seconds: float, reduced_motion: bool, inside: bool = false) -> void:
	var position := RoundTimeout.position_at(seconds, reduced_motion)
	var size := RoundTimeout.size_at(seconds)
	var frame := RoundTimeout.frame_at(seconds, reduced_motion)
	var cell := SANTA.get_size() / Vector2(4,4)
	var source := Rect2(Vector2(frame % 4, floori(frame / 4.0)) * cell, cell)
	var destination := Rect2(position - Vector2.ONE * size * .5, Vector2.ONE * size)
	if inside:
		DoorRenderer.draw_inside(canvas,SANTA,destination,source,RoundTimeout.door_open(seconds))
	else:
		canvas.draw_set_transform(position + Vector2(0,size * .42), 0, Vector2(1,.18))
		canvas.draw_circle(Vector2.ZERO, size * .23, Color(.05,.10,.15,.12))
		canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_texture_rect_region(SANTA,destination,source)
