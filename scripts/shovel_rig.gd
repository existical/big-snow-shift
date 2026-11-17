class_name ShovelRig
extends RefCounted

# IDs match MAN0..MAN31. EXE range table at DS:008a: idle 30..31;
# side walk 0..7/work 8..13; back 14..16/17..21; front 22..24/25..29.
const PIVOT := Vector2(.43, .95)
const GRIPS := [
	[Vector2(.49,.62), Vector2(.70,.62)], [Vector2(.44,.63), Vector2(.71,.54)],
	[Vector2(.47,.61), Vector2(.75,.49)], [Vector2(.47,.57), Vector2(.80,.57)],
	[Vector2(.49,.58), Vector2(.74,.42)], [Vector2(.45,.59), Vector2(.76,.52)],
	[Vector2(.45,.63), Vector2(.75,.65)], [Vector2(.50,.56), Vector2(.77,.62)],
	[Vector2(.45,.58), Vector2(.76,.44)], [Vector2(.49,.55), Vector2(.75,.56)],
	[Vector2(.48,.53), Vector2(.73,.58)], [Vector2(.50,.69), Vector2(.72,.83)],
	[Vector2(.49,.66), Vector2(.74,.72)], [Vector2(.47,.59), Vector2(.75,.48)],
	[Vector2(.55,.60), Vector2(.52,.72)], [Vector2(.55,.60), Vector2(.52,.72)],
	[Vector2(.55,.60), Vector2(.52,.72)], [Vector2(.55,.60), Vector2(.52,.72)],
	[Vector2(.55,.60), Vector2(.52,.72)], [Vector2(.55,.60), Vector2(.52,.72)],
	[Vector2(.55,.60), Vector2(.52,.72)], [Vector2(.55,.60), Vector2(.52,.72)],
	[Vector2(.35,.57), Vector2(.61,.43)], [Vector2(.34,.54), Vector2(.59,.42)],
	[Vector2(.29,.58), Vector2(.58,.45)], [Vector2(.31,.61), Vector2(.57,.45)],
	[Vector2(.27,.29), Vector2(.41,.57)], [Vector2(.30,.57), Vector2(.55,.80)],
	[Vector2(.26,.61), Vector2(.57,.81)], [Vector2(.32,.64), Vector2(.61,.47)],
	[Vector2(.27,.40), Vector2(.27,.65)], [Vector2(.27,.40), Vector2(.27,.65)]]

# Small wooden blade: ~14 original pixels against a 43px body (VGA aspect 1.2).
const SHAFT_START := -.10
const SOCKET := .46
const TIP := .69
const BLADE_CENTER := Vector2(.575, .025)

static func is_side(frame: int) -> bool:
	return frame < 14

static func is_back(frame: int) -> bool:
	return frame >= 14 and frame <= 21

static func frame_for(direction: Vector2, moving: bool, working: bool, elapsed: float, stunned: bool = false, stroke_time: float = -1.0) -> int:
	if not moving or stunned:
		return 30 + int(elapsed * 2) % 2
	var stroke := stroke_time if stroke_time >= 0 else elapsed
	var phase := fposmod(stroke, ShovelStroke.DURATION) / ShovelStroke.DURATION
	if direction.y < -.55:
		return 17 + mini(4, int(phase * 5)) if working else 14 + int(elapsed * 6) % 3
	if direction.y > .55:
		return 25 + mini(4, int(phase * 5)) if working else 22 + int(elapsed * 6) % 3
	return 8 + mini(5, int(phase * 6)) if working else int(elapsed * 8) % 8

static func size_at(player: Vector2) -> float:
	return lerpf(105, 142, player.y)

static func flip_for(direction: Vector2, frame: int) -> float:
	return -1.0 if direction.x < -.4 and is_side(frame) else 1.0

static func tool_transform(size: float, frame: int) -> Transform2D:
	var rear: Vector2 = (GRIPS[frame][0] - PIVOT) * size
	var front: Vector2 = (GRIPS[frame][1] - PIVOT) * size
	return Transform2D((front - rear).angle(), rear)

static func side_transform(size: float, frame: int) -> Transform2D:
	return tool_transform(size, frame)

static func projection(frame: int) -> Vector2:
	if frame in [22, 23, 24, 25, 29]:
		return Vector2(.64, 1.0)
	if frame >= 30:
		return Vector2(.75, 1.0)
	return Vector2.ONE

static func blade_center(size: float, frame: int, _grounded: bool = true, _vertical: float = 0.0) -> Vector2:
	if is_back(frame):
		return Vector2(0, -.045) * size
	return tool_transform(size, frame) * (BLADE_CENTER * projection(frame) * size)

static func contact_world(player: Vector2, direction: Vector2, frame: int) -> Vector2:
	var point := blade_center(size_at(player), frame)
	point.x *= flip_for(direction, frame)
	return StairSurface.project(player) + point

static func contact_uv(player: Vector2, direction: Vector2, frame: int) -> Vector2:
	return StairSurface.unproject(contact_world(player, direction, frame))

static func brush_radius(player: Vector2, contact: Vector2) -> Vector2:
	var size := size_at(player)
	var bounds := StairSurface.bounds_at(StairSurface.project(contact).y)
	return Vector2(size * .17 / (bounds.y - bounds.x), size * .075 / (StairSurface.BOTTOM - StairSurface.TOP))
