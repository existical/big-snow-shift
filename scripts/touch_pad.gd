class_name TouchPad
extends Control

var direction := Vector2.ZERO
var finger := -1
var mouse_held := false
var enabled := true
var opacity := 0.9
const RADIUS := 65.0

func _ready() -> void:
	size = Vector2(166, 166)
	mouse_filter = MOUSE_FILTER_IGNORE

func release() -> void:
	direction = Vector2.ZERO
	finger = -1
	mouse_held = false
	queue_redraw()

func local_point(screen_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_point

func _input(event: InputEvent) -> void:
	# GUI controls need touch-generated mouse events. The pad already owns
	# native touch contacts, so their synthetic mouse duplicates must not grab it.
	if event.device == InputEvent.DEVICE_ID_EMULATION or not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var at := local_point(event.position)
		if event.index == finger and (not event.pressed or event.canceled):
			release()
			get_viewport().set_input_as_handled()
		elif event.pressed and not event.canceled and finger == -1 and not mouse_held and at.distance_to(size / 2) < 80:
			finger = event.index
			update_direction(at)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == finger:
		update_direction(local_point(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var at := local_point(event.position)
		if event.pressed and finger < 0 and at.distance_to(size / 2) < 80:
			mouse_held = true
			update_direction(at)
			get_viewport().set_input_as_handled()
		elif not event.pressed and mouse_held:
			release()
	elif event is InputEventMouseMotion and mouse_held:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			release()
		else:
			update_direction(local_point(event.position))

func update_direction(at: Vector2) -> void:
	var offset := (at - size / 2) / 45
	direction = offset.limit_length(1.0) if offset.length() > 0.16 else Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var center := size / 2
	draw_circle(center + Vector2(0, 5), 77, Color(0.04, 0.14, 0.29, .6))
	draw_circle(center, 77, Color(.1, .44, .74, opacity * .9))
	draw_arc(center, 75, 0, TAU, 64, Color("c4f4ff"), 4, true)
	for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var at: Vector2 = center + axis * 53
		var side: Vector2 = axis.orthogonal() * 5
		draw_polyline(PackedVector2Array([at - axis * 4 + side, at + axis * 3, at - axis * 4 - side]), Color("efffff"), 3.5, true)
	draw_circle(center + direction * 32 + Vector2(0, 3), 27, Color("287e9e"))
	draw_circle(center + direction * 32, 27, Color("70e9e5"))
	draw_arc(center + direction * 32, 26, 0, TAU, 40, Color("ffeb93"), 3, true)
