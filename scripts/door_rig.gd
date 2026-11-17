class_name DoorRig
extends RefCounted

# Inside the fixed painted jamb, traced in the house's 1280x720 coordinates.
const LEFT := 562.0
const RIGHT := 716.0
const CENTER := (LEFT + RIGHT) * .5
const TOP := 185.0
const SPRING := 222.0
const BOTTOM := 356.0
const HALF_WIDTH := (RIGHT - LEFT) * .5
const EYE_Y := 275.0
const FOCAL := 420.0
const MAX_ANGLE := 95.0 * PI / 180.0
const THICKNESS := 3.0
const COLUMNS := 16
const ROWS := 6
const DECORATION := Rect2(572,205,60,68)

static func top_at(x: float) -> float:
	return SPRING - (SPRING - TOP) * sqrt(maxf(0, 1.0 - pow((x - CENTER) / HALF_WIDTH, 2)))

static func aperture() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(LEFT,BOTTOM), Vector2(RIGHT,BOTTOM), Vector2(RIGHT,SPRING)])
	for i in range(1,33):
		var angle := i * PI / 32
		points.append(Vector2(CENTER + HALF_WIDTH * cos(angle), SPRING - (SPRING - TOP) * sin(angle)))
	return points

static func project(side: int, distance: float, y: float, openness: float, back: bool = false) -> Vector2:
	var angle := clampf(openness,0,1) * MAX_ANGLE
	var direction := 1.0 if side == 0 else -1.0
	var hinge := LEFT if side == 0 else RIGHT
	var depth := distance * sin(angle) + (THICKNESS * cos(angle) if back else 0.0)
	var x := hinge + direction * (distance * cos(angle) - (THICKNESS * sin(angle) if back else 0.0))
	var perspective := FOCAL / (FOCAL + depth)
	return Vector2(CENTER + (x - CENTER) * perspective, EYE_Y + (y - EYE_Y) * perspective)

static func surface(side: int, openness: float) -> Dictionary:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var direction := 1.0 if side == 0 else -1.0
	var hinge := LEFT if side == 0 else RIGHT
	var angle := clampf(openness,0,1) * MAX_ANGLE
	for column in COLUMNS + 1:
		var distance := HALF_WIDTH * column / COLUMNS
		var x := hinge + direction * distance
		var perspective := FOCAL / (FOCAL + distance * sin(angle))
		var screen_x := project(side,distance,SPRING,openness).x
		# The leaf swings behind the arched frame. Clip each vertical column
		# to that fixed silhouette, preserving its source UV and hinge axis.
		var minimum_y := maxf(top_at(x), EYE_Y + (top_at(screen_x) - EYE_Y) / perspective)
		for row in ROWS + 1:
			var y := lerpf(minimum_y,BOTTOM,row / float(ROWS))
			var point := project(side,distance,y,openness)
			vertices.append(Vector3(point.x,point.y,0))
			uvs.append(Vector2((x - LEFT) / (RIGHT - LEFT),(y - TOP) / (BOTTOM - TOP)))
	for column in COLUMNS:
		for row in ROWS:
			var a := column * (ROWS + 1) + row
			var b := a + ROWS + 1
			indices.append_array(PackedInt32Array([a,b,b+1,a,b+1,a+1]))
	return {"vertices":vertices,"uvs":uvs,"indices":indices}

static func free_edge(side: int, openness: float) -> PackedVector2Array:
	var front_top := project(side,HALF_WIDTH,TOP,openness)
	var back_top := project(side,HALF_WIDTH,TOP,openness,true)
	front_top.y = maxf(front_top.y,top_at(front_top.x))
	back_top.y = maxf(back_top.y,top_at(back_top.x))
	return PackedVector2Array([front_top,project(side,HALF_WIDTH,BOTTOM,openness),project(side,HALF_WIDTH,BOTTOM,openness,true),back_top])

static func decoration_rect(side: int) -> Rect2:
	if side == 0:
		return DECORATION
	return Rect2(Vector2(CENTER * 2 - DECORATION.end.x,DECORATION.position.y),DECORATION.size)

static func decoration_surface(side: int, openness: float) -> Dictionary:
	# Each leaf carries the same independent sprite at matching height. Keep
	# the artwork upright on both leaves while projecting around its own hinge.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var attachment := decoration_rect(side)
	var hinge := LEFT if side == 0 else RIGHT
	var direction := 1.0 if side == 0 else -1.0
	const COLUMNS_SPRITE := 8
	const ROWS_SPRITE := 8
	for column in COLUMNS_SPRITE + 1:
		for row in ROWS_SPRITE + 1:
			var uv := Vector2(column / float(COLUMNS_SPRITE),row / float(ROWS_SPRITE))
			var local := attachment.position + uv * attachment.size
			var point := project(side,(local.x - hinge) * direction,local.y,openness)
			vertices.append(Vector3(point.x,point.y,0))
			uvs.append(uv)
	for column in COLUMNS_SPRITE:
		for row in ROWS_SPRITE:
			var a := column * (ROWS_SPRITE + 1) + row
			var b := a + ROWS_SPRITE + 1
			indices.append_array(PackedInt32Array([a,b,b+1,a,b+1,a+1]))
	return {"vertices":vertices,"uvs":uvs,"indices":indices}
