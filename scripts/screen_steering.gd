class_name ScreenSteering
extends RefCounted

# All positions are in the fitted 1280 x 720 game stage, not physical pixels.
const DEAD_ZONE := 18.0
const TURN_BIAS := 1.20
const DRAG_THRESHOLD := 6.0
var point := Vector2.ZERO
var aim_point := Vector2.ZERO
var heading := Vector2.ZERO
var finger := -1
var mouse_held := false

func held() -> bool:
	return mouse_held or finger >= 0

func release() -> void:
	finger = -1
	mouse_held = false
	heading = Vector2.ZERO

func owns_motion(event: InputEvent) -> bool:
	return event.device != InputEvent.DEVICE_ID_EMULATION and ((event is InputEventScreenDrag and finger >= 0 and event.index == finger) or (event is InputEventMouseMotion and mouse_held))

func begin(event: InputEvent, at: Vector2, anchor: Vector2) -> bool:
	if held() or event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		finger = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		mouse_held = true
	else:
		return false
	point = at
	aim_point = at
	choose_heading(anchor)
	return true

func track(event: InputEvent, at: Vector2, anchor: Vector2) -> bool:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventScreenTouch and finger >= 0 and event.index == finger and (not event.pressed or event.canceled):
		release()
		return true
	if event is InputEventMouseButton and mouse_held and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		release()
		return true
	if owns_motion(event):
		if event is InputEventMouseMotion and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			release() # Recover even if a release outside the window was missed.
			return true
		point = at
		if point.distance_to(aim_point) >= DRAG_THRESHOLD:
			aim_point = point
			choose_heading(anchor)
		return true
	return false

func choose_heading(anchor: Vector2) -> void:
	var offset := point - anchor
	if offset.length() <= DEAD_ZONE:
		heading = Vector2.ZERO
	elif heading.x != 0 and absf(offset.x) * TURN_BIAS >= absf(offset.y):
		heading = Vector2(signf(offset.x),0)
	elif heading.y != 0 and absf(offset.y) * TURN_BIAS >= absf(offset.x):
		heading = Vector2(0,signf(offset.y))
	else:
		heading = Vector2(signf(offset.x),0) if absf(offset.x) >= absf(offset.y) else Vector2(0,signf(offset.y))

func direction_at(anchor: Vector2) -> Vector2:
	if not held() or heading == Vector2.ZERO:
		return Vector2.ZERO
	# Keep the selected stair level until the pointer is deliberately dragged.
	# Stop near the held point's axis rather than reversing or changing rows
	# as the character catches up with a stationary mouse/finger.
	return heading if (point - anchor).dot(heading) > DEAD_ZONE else Vector2.ZERO
