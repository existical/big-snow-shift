class_name IciclePainter
extends RefCounted

const ATLAS = preload("res://assets/art/icicle_atlas_v017.png")
const METADATA := "res://assets/art/icicle_atlas_v017.json"
static var frames: Array = []

static func data(frame: int) -> Dictionary:
	if frames.is_empty():
		frames.assign(JSON.parse_string(FileAccess.get_file_as_string(METADATA)).frames)
	return frames[clampi(frame,0,15)]

static func vector(values: Array) -> Vector2:
	return Vector2(values[0],values[1])

static func growth(age: float, warning: float) -> float:
	return clampf(age / maxf(warning,.001),0,1)

static func size_at(age: float, warning: float) -> Vector2:
	var progress := growth(age,warning)
	return Vector2(lerpf(6,20,progress),lerpf(3,48,progress))

static func variant_for(point: Vector2) -> int:
	# A stable visual choice without consuming gameplay or particle RNG.
	return posmod(roundi(point.x * 9973) + roundi(point.y * 17881),3)

static func frame_at(point: Vector2, age: float, warning: float) -> int:
	return variant_for(point) * 4 + mini(3,floori(growth(age,warning) * 4))

static func bounds(frame: int) -> Rect2:
	var values: Array = data(frame).bounds
	var result := Rect2(values[0],values[1],values[2],values[3])
	# Include the soft edge around the measured opaque sprite, sampling only
	# its own atlas cell. The generated PNG itself remains untouched.
	return result.grow(2.0 / (ATLAS.get_width() / 4.0)).intersection(Rect2(0,0,1,1))

static func source(frame: int, region: Rect2) -> Rect2:
	var cell := ATLAS.get_size() / Vector2(4,4)
	return Rect2((Vector2(frame % 4,floori(frame / 4.0)) + region.position) * cell,region.size * cell)

static func body_transform(frame: int, top: Vector2, size: Vector2) -> Transform2D:
	var root := vector(data(frame).root)
	var tip := vector(data(frame).tip)
	var vertical := (tip - root).normalized()
	var across := Vector2(vertical.y,-vertical.x)
	var sx: float = size.x / float(data(frame).span)
	var sy := size.y / tip.distance_to(root)
	var x_axis := Vector2(across.x * sx,vertical.x * sy)
	var y_axis := Vector2(across.y * sx,vertical.y * sy)
	return Transform2D(x_axis,y_axis,top - x_axis * root.x - y_axis * root.y)

static func collar_alpha(age: float, warning: float) -> float:
	return 1.0 - smoothstep(warning,warning + .22,age)

static func glint_strength(age: float, warning: float, reduced_motion: bool) -> float:
	var progress := growth(age,warning)
	if reduced_motion or progress <= .82 or progress >= 1:
		return 0
	return sin((progress - .82) / .18 * PI)

static func draw(canvas: Node2D, point: Vector2, target: Vector2, age: float, warning: float, flight: float, reduced_motion: bool) -> void:
	var size := size_at(age,warning)
	var top := RoofLine.icicle_top(target,age,warning,flight,size.y)
	var frame := frame_at(point,age,warning)
	var region := bounds(frame)
	canvas.draw_set_transform_matrix(body_transform(frame,top,size))
	canvas.draw_texture_rect_region(ATLAS,region,source(frame,region))
	canvas.draw_set_transform(Vector2.ZERO)
	var collar := collar_alpha(age,warning)
	if collar > 0:
		# The snow collar stays on the roof as the ice detaches, then blends
		# back into the painted roof snow instead of travelling with the ice.
		var cap_size := Vector2(size.x + 4,lerpf(3.2,7.5,growth(age,warning)))
		var cap := bounds(12)
		canvas.draw_texture_rect_region(ATLAS,Rect2(RoofLine.anchor(target.x) - cap_size * Vector2(.5,.55),cap_size),source(12,cap),Color(1,1,1,collar))
	var glint := glint_strength(age,warning,reduced_motion)
	if glint > .001:
		var center := top + Vector2(-size.x * .12,size.y * .28)
		var tint := Color(1,1,.98,glint * .9)
		canvas.draw_line(center - Vector2(0,4),center + Vector2(0,4),tint,1.0,true)
		canvas.draw_line(center - Vector2(2.6,0),center + Vector2(2.6,0),tint,1.0,true)
		canvas.draw_circle(center,.8,tint)

static func draw_fragment(canvas: Node2D, at: Vector2, radius: float, angle: float, variant: int, alpha: float) -> void:
	var frame := 13 + posmod(variant,3)
	var region := bounds(frame)
	var size := region.size / maxf(region.size.x,region.size.y) * radius * 2
	canvas.draw_set_transform(at,angle)
	canvas.draw_texture_rect_region(ATLAS,Rect2(-size * .5,size),source(frame,region),Color(1,1,1,alpha))
	canvas.draw_set_transform(Vector2.ZERO)
