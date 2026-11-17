class_name ParticleBatch
extends Node2D
## One retained mesh/atlas replaces per-particle polygon, circle and line draws.
const CAPACITY := 520 * 3 + 65
const TILE := 64.0
const UNIT := 12.0
const SHADER = preload("res://assets/art/particle_batch.gdshader")
var mesh := MultiMesh.new()
var buffer := PackedFloat32Array()
var count := 0
var atlas: SubViewport

class AtlasPainter extends Node2D:
	func _draw() -> void:
		var outline := PackedVector2Array([Vector2(-1,-.35),Vector2(-.45,-1),Vector2(.6,-.8),Vector2(1,.25),Vector2(.25,1),Vector2(-.8,.6)])
		for frame in 8:
			var at := Vector2(frame % 4, floori(frame / 4.0)) * TILE + Vector2.ONE * TILE * .5
			match frame:
				0: draw_circle(at, UNIT, Color.WHITE)
				1: draw_line(at - Vector2(UNIT,0), at + Vector2(UNIT,0), Color.WHITE, UNIT, true)
				2:
					draw_circle(at, UNIT, Color(.86,.95,1,.09))
					draw_circle(at, UNIT * .65, Color(.97,.99,1,.16))
				3:
					var points := PackedVector2Array()
					for point in outline: points.append(at + point * UNIT)
					draw_colored_polygon(points, Color.WHITE)
				4,5,6: IciclePainter.draw_fragment(self, at, UNIT, 0, frame - 4, 1)

func _ready() -> void:
	atlas = SubViewport.new()
	atlas.size = Vector2i(256,192)
	atlas.disable_3d = true
	atlas.transparent_bg = true
	atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	atlas.add_child(AtlasPainter.new())
	add_child(atlas)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var half := TILE / (2 * UNIT)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-half,-half,0),Vector3(half,-half,0),Vector3(half,half,0),Vector3(-half,half,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = shape
	mesh.instance_count = CAPACITY
	mesh.visible_instance_count = 0
	buffer.resize(CAPACITY * 16)
	var instances := MultiMeshInstance2D.new()
	instances.multimesh = mesh
	instances.texture = atlas.get_texture()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	instances.material = material
	add_child(instances)

func sprite(at: Vector2, x: Vector2, y: Vector2, tint: Color, frame: int) -> void:
	if count >= CAPACITY: return
	var i := count * 16
	buffer[i] = x.x
	buffer[i+1] = y.x
	buffer[i+3] = at.x
	buffer[i+4] = x.y
	buffer[i+5] = y.y
	buffer[i+7] = at.y
	buffer[i+8] = tint.r
	buffer[i+9] = tint.g
	buffer[i+10] = tint.b
	buffer[i+11] = tint.a
	buffer[i+12] = frame / 16.0
	count += 1

func line(a: Vector2, b: Vector2, width: float, tint: Color) -> void:
	var direction := b - a
	if direction.length_squared() < .00001: return
	sprite((a+b) * .5, direction * .5, direction.normalized().orthogonal() * width, tint, 1)

func update_particles(particles: Array[Dictionary], time: float, reduced_motion: bool) -> void:
	count = 0
	for p in particles:
		var tint: Color = p.color
		tint.a *= minf(1, p.life / .25)
		var size: float = p.size
		var at: Vector2 = p.position
		if p.get("confetti", false):
			var axis := Vector2.from_angle(time * 4 + at.x) * size
			line(at-axis, at+axis, 2, tint)
		elif p.get("kind", "") == "powder":
			var age: float = 1 - p.life / p.max_life
			var radius := size * (1 + age * 1.3)
			sprite(at, Vector2(radius,0), Vector2(0,radius), Color(1,1,1,tint.a * minf(age*10,1)), 2)
		elif p.get("kind", "") in ["ice", "clump", "flake"]:
			var axis := Vector2.from_angle(p.rotation)
			match p.kind:
				"ice": sprite(at, axis * size, axis.orthogonal() * size, Color(1,1,1,tint.a), 4 + posmod(int(p.get("art_variant",0)),3))
				"clump":
					sprite(at, axis * size, axis.orthogonal() * size, Color(.49,.75,.90,tint.a), 3)
					sprite(at+Vector2(-.8,-1), axis * size * .8, axis.orthogonal() * size * .8, tint, 3)
				"flake":
					line(at-axis*size, at+axis*size, 1.5, tint)
					axis = axis.orthogonal()
					line(at-axis*size, at+axis*size, 1.5, tint)
		else:
			if p.has("previous") and not reduced_motion:
				line(p.previous, at, 2, Color(.8,.93,1,tint.a * .35))
			sprite(at, Vector2(size,0), Vector2(0,size), tint, 0)
	for i in (22 if reduced_motion else 65):
		var x := fposmod(i * 137.73 + sin(time*.3+i)*14 + time*6,1280)
		var y := fposmod(i * 57.36 + time*(13+i%12),720)
		var radius := 1 + i%3 * .55
		sprite(Vector2(x,y),Vector2(radius,0),Vector2(0,radius),Color(.9,.96,1,.16+i%4*.08),0)
	mesh.buffer = buffer
	mesh.visible_instance_count = count
