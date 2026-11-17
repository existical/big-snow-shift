class_name DoorRenderer
extends RefCounted

const LEAVES = preload("res://assets/art/door_plain_v014.png")
const WREATH = preload("res://assets/art/door_wreath_v014.png")
const INTERIOR = preload("res://assets/art/cottage_interior_v012.png")
# WinterWorld shares this full cottage texture. Sample only the restored
# doors for the moving leaves; the interior hides the painted closed doors.
const LEAF_SOURCE := Rect2(Vector2(DoorRig.LEFT,DoorRig.TOP) / Vector2(1280,720),Vector2(DoorRig.RIGHT - DoorRig.LEFT,DoorRig.BOTTOM - DoorRig.TOP) / Vector2(1280,720))
static var cached_open := -1.0
static var meshes: Array[ArrayMesh] = []
static var wreath_meshes: Array[ArrayMesh] = []

static func draw_background(canvas: Node2D) -> void:
	var shape := DoorRig.aperture()
	var uvs := PackedVector2Array()
	for point in shape:
		uvs.append(Vector2((point.x - DoorRig.LEFT) / (DoorRig.RIGHT - DoorRig.LEFT),(point.y - DoorRig.TOP) / (DoorRig.BOTTOM - DoorRig.TOP)))
	canvas.draw_polygon(shape,PackedColorArray([Color.WHITE]),uvs,INTERIOR)

static func make_mesh(data: Dictionary, source: Rect2 = Rect2(0,0,1,1)) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	var uvs: PackedVector2Array = data.uvs.duplicate()
	for i in uvs.size():
		uvs[i] = source.position + uvs[i] * source.size
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func draw_panels(canvas: Node2D, openness: float, decoration_visible: bool = true) -> void:
	openness = clampf(openness,0,1)
	if meshes.size() != 2 or wreath_meshes.size() != 2 or absf(openness - cached_open) > .000001:
		meshes.clear()
		wreath_meshes.clear()
		for side in 2:
			meshes.append(make_mesh(DoorRig.surface(side,openness),LEAF_SOURCE))
			wreath_meshes.append(make_mesh(DoorRig.decoration_surface(side,openness)))
		cached_open = openness
	var shade := lerpf(1.0,.76,sin(openness * DoorRig.MAX_ANGLE))
	for side in 2:
		canvas.draw_mesh(meshes[side],LEAVES,Transform2D.IDENTITY,Color(shade,shade,shade))
		if decoration_visible:
			canvas.draw_mesh(wreath_meshes[side],WREATH,Transform2D.IDENTITY,Color(shade,shade,shade))
		if openness > .001:
			var edge := DoorRig.free_edge(side,openness)
			canvas.draw_colored_polygon(edge,Color("173b33"))
			canvas.draw_line(edge[0],edge[1],Color(.48,.48,.29,.85),.8,true)

static func draw_inside(canvas: Node2D, texture: Texture2D, destination: Rect2, source: Rect2, openness: float) -> void:
	if openness <= .000001:
		return
	# Clip the opaque actor to the doorway, then let the hinged leaves occlude
	# it. This reveals Santa through the gap instead of fading through wood.
	var box := PackedVector2Array([destination.position,Vector2(destination.end.x,destination.position.y),destination.end,Vector2(destination.position.x,destination.end.y)])
	for polygon in Geometry2D.intersect_polygons(box,DoorRig.aperture()):
		var uvs := PackedVector2Array()
		for point in polygon:
			uvs.append((source.position + (point - destination.position) / destination.size * source.size) / texture.get_size())
		canvas.draw_polygon(polygon,PackedColorArray([Color.WHITE]),uvs,texture)
