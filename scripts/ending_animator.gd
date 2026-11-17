class_name EndingAnimator
extends RefCounted

const ACTORS = preload("res://assets/art/endings_16_v011.png")
const FEET := Vector2(640, 365)
const SIZE := 160.0
const PIVOT := Vector2(.5, .945)
const SANTA_PART := Rect2(.49,0,.51,1)
const CARETAKER_PART := Rect2(0,0,.48,1)
const GIFT_CARETAKER_PART := Rect2(0,0,.47,1)

static func draw_region(canvas: Node2D, frame: int, part: Rect2 = Rect2(0,0,1,1), offset: Vector2 = Vector2.ZERO, inside: bool = false, openness: float = 1.0) -> void:
	var cell := ACTORS.get_size() / Vector2(4,4)
	var source := Rect2((Vector2(frame % 4, floori(frame / 4.0)) + part.position) * cell, part.size * cell)
	var destination := Rect2(FEET + (part.position - PIVOT) * SIZE + offset, part.size * SIZE)
	if inside:
		DoorRenderer.draw_inside(canvas,ACTORS,destination,source,openness)
	else:
		canvas.draw_texture_rect_region(ACTORS, destination, source)

static func santa_offset(round_index: int, seconds: float) -> Vector2:
	var progress := 1.0 - smoothstep(.9,RoundEnding.OPEN_TIME,seconds) if seconds < RoundEnding.OPEN_TIME else smoothstep(RoundEnding.exit_time(round_index),RoundEnding.exit_time(round_index) + .9,seconds)
	return Vector2(-35,-11) * progress

static func joined_pose(round_index: int, seconds: float) -> bool:
	return seconds >= RoundEnding.OPEN_TIME and seconds < RoundEnding.exit_time(round_index) and not RoundEnding.santa_inside(round_index,seconds) and RoundEnding.santa_presence(round_index,seconds) > 0

static func caretaker_frame(round_index: int, seconds: float) -> int:
	# Pose 0 contains only the caretaker. Pose 10 has a wide transparent gap
	# between his present and Santa. Waving poses 6/11 do not: their Santa
	# gloves cross the old .49 split and must never supply a foreground crop.
	return 10 if round_index == 1 and seconds >= 2.8 else 0

static func santa_frame(round_index: int, seconds: float) -> int:
	# These neutral/prop-carrying poses have fully separated actors. Pose 1's
	# mitten crosses .49, while the waving poses leak parts into the left half.
	if seconds < RoundEnding.OPEN_TIME:
		return [2,7,12][clampi(round_index,0,2)]
	return 2

static func draw_inside_santa(canvas: Node2D, round_index: int, seconds: float) -> void:
	if RoundEnding.santa_presence(round_index,seconds) > 0 and RoundEnding.santa_inside(round_index,seconds):
		draw_region(canvas,santa_frame(round_index,seconds),SANTA_PART,santa_offset(round_index,seconds),true,RoundEnding.door_open(round_index,seconds))

static func draw(canvas: Node2D, round_index: int, seconds: float, santa_visible: bool = true) -> void:
	if joined_pose(round_index,seconds) and santa_visible:
		# Keep joined mittens and the single present intact only while both
		# actors are outside. Interior/hidden Santa never shares a front sprite.
		draw_region(canvas,RoundEnding.frame_at(round_index,seconds))
		return
	var frame := caretaker_frame(round_index,seconds)
	draw_region(canvas,frame,GIFT_CARETAKER_PART if frame == 10 else CARETAKER_PART)
	if santa_visible and RoundEnding.santa_presence(round_index,seconds) > 0 and not RoundEnding.santa_inside(round_index,seconds):
		draw_region(canvas,santa_frame(round_index,seconds),SANTA_PART,santa_offset(round_index,seconds))
