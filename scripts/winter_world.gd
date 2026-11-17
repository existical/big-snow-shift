class_name WinterWorld
extends Node2D

# The full cottage painting also supplies the animated door panels.
const HOUSE = DoorRenderer.LEAVES
const FESTIVE = preload("res://assets/art/celebration_atlas.png")
const SNOW_SHADER = preload("res://assets/art/cached_snow.gdshader")
const SnowCacheClass = preload("res://scripts/snow_cache.gd")
const ParticleBatchClass = preload("res://scripts/particle_batch.gd")
const MAX_PARTICLES := 520
var chunk_outline := PackedVector2Array([Vector2(-1,-.35), Vector2(-.45,-1), Vector2(.6,-.8), Vector2(1,.25), Vector2(.25,1), Vector2(-.8,.6)])
var model: GameModel
var reduced_motion := false
var time := 0.0
var visual_rng := RandomNumberGenerator.new()
var particles: Array[Dictionary] = []
var snow_texture: ImageTexture
var snow_material: ShaderMaterial
var snow_panel: ColorRect
var foreground_snow: ColorRect
var foreground_material: ShaderMaterial
var paint_layer: PaintLayer
var doorway_layer: DoorwayLayer
var upload_timer := 0.0
var menu_pose := false
@export var door_decoration_visible := true
var santa_visible := true
var animation_time := 0.0
var snow_cache: SnowCacheClass
var particle_batch: ParticleBatchClass

class PaintLayer:
	extends Node2D
	var world: WinterWorld
	func _draw() -> void:
		world.paint(self)

class DoorwayLayer:
	extends Node2D
	var world: WinterWorld
	func _draw() -> void:
		world.paint_doorway(self)

func _ready() -> void:
	visual_rng.seed = 7301
	var background := Sprite2D.new()
	background.texture = HOUSE
	background.centered = false
	background.scale = Vector2(1280.0 / HOUSE.get_width(), 720.0 / HOUSE.get_height())
	add_child(background)
	# Architecture and Santa while indoors sit behind ALL stair snow. The
	# later foreground snow pass is only for actors standing on the stairs.
	doorway_layer = DoorwayLayer.new()
	doorway_layer.world = self
	add_child(doorway_layer)
	snow_cache = SnowCacheClass.new()
	add_child(snow_cache)
	snow_panel = ColorRect.new()
	snow_panel.position = Vector2(StairSurface.CENTER - StairSurface.BOTTOM_WIDTH / 2, StairSurface.TOP - SnowField.RENDER_PAD)
	snow_panel.size = Vector2(StairSurface.BOTTOM_WIDTH, StairSurface.BOTTOM - StairSurface.TOP + SnowField.RENDER_PAD)
	snow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snow_material = ShaderMaterial.new()
	snow_material.shader = SNOW_SHADER
	snow_material.set_shader_parameter("stair_top", StairSurface.TOP)
	snow_material.set_shader_parameter("stair_height", StairSurface.BOTTOM - StairSurface.TOP)
	snow_material.set_shader_parameter("snow_color", snow_cache.color_view.get_texture())
	snow_material.set_shader_parameter("snow_depth", snow_cache.depth_view.get_texture())
	snow_panel.material = snow_material
	add_child(snow_panel)
	paint_layer = PaintLayer.new()
	paint_layer.world = self
	add_child(paint_layer)
	particle_batch = ParticleBatchClass.new()
	add_child(particle_batch)
	foreground_snow = ColorRect.new()
	foreground_snow.position = snow_panel.position
	foreground_snow.size = snow_panel.size
	foreground_snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground_material = snow_material.duplicate()
	foreground_material.set_shader_parameter("foreground_only", true)
	foreground_snow.material = foreground_material
	add_child(foreground_snow)

func set_model(value: GameModel) -> void:
	model = value
	animation_time = 0
	particles.clear()
	upload_timer = 0.0
	if is_instance_valid(model):
		snow_cache.bind(model.snow)
		snow_texture = snow_cache.mask_texture

func _process(delta: float) -> void:
	time += delta
	if not model:
		return
	foreground_snow.visible = not menu_pose and not model.is_timeout_scene()
	foreground_material.set_shader_parameter("depth_cutoff", StairSurface.project(model.player).y - 2.0)
	if not model.paused:
		animation_time += delta
	upload_timer -= delta
	if model.snow.dirty and upload_timer <= 0.0:
		snow_cache.refresh(model.snow)
		upload_timer = 1.0 / 24.0
	if not model.paused:
		advance_particles(delta)
	particle_batch.update_particles(particles, time, reduced_motion)
	redraw_layers()

func redraw_layers() -> void:
	doorway_layer.queue_redraw()
	paint_layer.queue_redraw()

func advance_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0:
			particles.remove_at(i)
			continue
		p.previous = p.position
		p.velocity.y += float(p.get("gravity", 125)) * delta
		p.velocity.x *= exp(-float(p.get("drag", 0.0)) * delta)
		p.position += p.velocity * delta
		p.rotation = float(p.get("rotation", 0.0)) + float(p.get("spin", 0.0)) * delta
		if p.has("floor") and p.velocity.y > 0 and p.position.y >= p.floor:
			p.position.y = p.floor
			if not p.get("bounced", false):
				p.velocity = Vector2(p.velocity.x * .48, -p.velocity.y * .22)
				p.bounced = true
				p.life = minf(p.life, .30)
			else:
				p.life = minf(p.life, .08)

func burst(at: Vector2, count: int, tint: Color, duration: float = 0.8) -> void:
	if reduced_motion:
		count = mini(count, 4)
	for _i in maxi(0, mini(count, MAX_PARTICLES - particles.size())):
		particles.append({"position": at, "velocity": Vector2(visual_rng.randf_range(-90, 90), visual_rng.randf_range(-110, -15)),
			"life": duration, "max_life": duration, "size": visual_rng.randf_range(2, 5), "color": tint})

func shovel_burst(amount: int) -> void:
	if not model or amount <= 0:
		return
	# Use the visible digging pose at the moment the model removes its chunk.
	var origin := ShovelRig.contact_world(model.player, model.facing, model.pose_frame())
	if model.facing.y < 0:
		origin = StairSurface.project(model.player) + Vector2(0, -ShovelRig.size_at(model.player) * .20)
	# Small finishing scoops throw less snow; full loads keep the rich spray.
	var load_ratio := sqrt(amount / 6000.0)
	var count := clampi(roundi(12 * load_ratio), 3, 12) if reduced_motion else clampi(roundi(58 * load_ratio), 6, 76)
	emit_snow(origin, model.facing, count, false)
	upload_timer = 0.0

func ice_burst(point: Vector2) -> void:
	var origin := StairSurface.project(point) - Vector2(0, model.snow.surface_height(point))
	emit_snow(origin, Vector2.ZERO, 12 if reduced_motion else 48, true)
	upload_timer = 0.0

func emit_snow(origin: Vector2, direction: Vector2, count: int, icy: bool) -> void:
	for i in maxi(0, mini(count, MAX_PARTICLES - particles.size())):
		var kind := "clump" if i % 5 == 0 else ("powder" if i % 5 == 1 else ("flake" if i % 5 == 2 else "grain"))
		if icy and i % 3 == 0:
			kind = "ice"
		var side := direction.x if direction.x != 0 else (-1.0 if i % 2 == 0 else 1.0)
		var velocity := Vector2(side * visual_rng.randf_range(65, 215), -visual_rng.randf_range(100, 235))
		if direction.y > 0:
			velocity.x *= .72
			velocity.y *= .72
		if reduced_motion:
			velocity *= .55
		var lifetime := visual_rng.randf_range(.65, 1.05)
		var size := visual_rng.randf_range(3.8, 7.0) if kind in ["clump", "ice"] else visual_rng.randf_range(1.5, 3.2)
		if kind == "powder":
			size = visual_rng.randf_range(6, 12)
			velocity *= .35
			lifetime = .5
		var at := origin + Vector2(visual_rng.randf_range(-5, 5), visual_rng.randf_range(-3, 3))
		var p := {"kind":kind, "position":at, "previous":at, "velocity":velocity, "life":lifetime, "max_life":lifetime,
			"size":size, "color":Color("f6fcff"), "rotation":visual_rng.randf_range(0, TAU), "spin":visual_rng.randf_range(-8, 8),
			"gravity":360.0 if kind != "powder" else 45.0, "drag":.35 if kind != "powder" else 2.0}
		if kind == "ice": p.art_variant = floori(i / 3.0) % 3
		if kind in ["clump", "ice", "grain"]:
			p.floor = origin.y + visual_rng.randf_range(12, 30)
		particles.append(p)

func celebrate() -> void:
	var colors := [Color("ffdc5c"), Color("7ff2db"), Color("ff7a93"), Color("ffffff")]
	for i in mini(12 if reduced_motion else 55, MAX_PARTICLES - particles.size()):
		particles.append({"position":Vector2(visual_rng.randf_range(430, 900), visual_rng.randf_range(165, 330)),
			"velocity":Vector2(visual_rng.randf_range(-35,35), visual_rng.randf_range(-65,-15)),
			"life":2.6, "max_life":2.6, "size":visual_rng.randf_range(2,4), "color":colors[i % colors.size()], "confetti":true})

func paint_doorway(canvas: Node2D) -> void:
	if not model:
		return
	paint_clock(canvas)
	var ending_visible := model.state in ["greeting", "celebrating", "won"] and not menu_pose
	var timeout_visible := model.is_timeout_scene() and not menu_pose
	var ending := model.ending_index()
	var scene_time := model.ending_time if model.state == "greeting" else RoundEnding.duration(ending)
	var openness := RoundEnding.door_open(ending,scene_time) if ending_visible else (RoundTimeout.door_open(model.failure_time) if timeout_visible else 0.0)
	DoorRenderer.draw_background(canvas)
	if santa_visible and ending_visible and scene_time >= RoundEnding.ALIGN_TIME:
		EndingAnimator.draw_inside_santa(canvas,ending,scene_time)
	elif santa_visible and timeout_visible and RoundTimeout.santa_inside(model.failure_time):
		TimeoutAnimator.draw(canvas,model.failure_time,reduced_motion,true)
	DoorRenderer.draw_panels(canvas,openness,door_decoration_visible)

func paint(canvas: Node2D) -> void:
	if not model:
		return
	var ending_visible := model.state in ["greeting", "celebrating", "won"] and not menu_pose
	var timeout_visible := model.is_timeout_scene() and not menu_pose
	var ending := model.ending_index()
	var scene_time := model.ending_time if model.state == "greeting" else RoundEnding.duration(ending)
	if model.state == "returning" and not menu_pose:
		var pulse := .65 + sin(time * 4) * .15
		canvas.draw_arc(Vector2(638, 293), 69, PI, TAU, 40, Color(1,.84,.34,pulse), 3, true)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(625, 379), Vector2(651,379), Vector2(638,364)]), Color(1,.86,.36,pulse))
	if not menu_pose:
		for hazard in model.hazards:
			paint_hazard(canvas, hazard)
	if ending_visible and scene_time >= RoundEnding.ALIGN_TIME:
		EndingAnimator.draw(canvas, ending, scene_time,santa_visible)
	else:
		paint_player(canvas, 1.0 - smoothstep(0,.65,model.failure_time) if timeout_visible else 1.0)
	if santa_visible and timeout_visible and not RoundTimeout.santa_inside(model.failure_time):
		TimeoutAnimator.draw(canvas, model.failure_time, reduced_motion)
	if ending_visible and ending == 2:
		var reveal := RoundEnding.tree_reveal(scene_time)
		if reveal > 0:
			paint_festive(canvas, true, Vector2(775, 619), 260.0 * (1.0 if reduced_motion else reveal))
			if reveal > .99 and not reduced_motion:
				for i in 7:
					var at := Vector2(775 + sin(i * 13.1) * (25 + i * 9), 398 + i * 28)
					canvas.draw_circle(at, 1.6 + sin(time * 3 + i) * .7, Color("fff2a1"))

func paint_player(canvas: Node2D, alpha: float = 1.0) -> void:
	if alpha <= 0:
		return
	var at := StairSurface.project(model.player)
	if model.stun > 0 and not menu_pose:
		HitAnimator.draw(canvas,at,ShovelRig.size_at(model.player),model.hit_duration - model.stun,model.hit_duration,model.facing,reduced_motion,alpha)
		return
	if menu_pose:
		at = Vector2(1018, 665)
	canvas.draw_set_transform(at + Vector2(2, -2), 0.0, Vector2(1, 0.32))
	canvas.draw_circle(Vector2.ZERO, 62 if menu_pose else 29, Color(0.02, 0.05, 0.08, 0.3 * alpha))
	canvas.draw_set_transform(Vector2.ZERO)
	var walking := model.moving and not model.paused
	var frame := model.pose_frame()
	var size := lerpf(105.0, 142.0, model.player.y)
	var sway := 0.0
	var hop := sin(time * 2) * 0.7 if not reduced_motion and not walking else 0.0
	var flip := ShovelRig.flip_for(model.facing, frame)
	if menu_pose:
		frame = 30
		size = 252
		flip = 1
		sway = sin(time * 1.7) * .012 if not reduced_motion else 0.0
	var tint := Color.WHITE
	if model.immunity > 0 and sin(model.elapsed * 20) > 0 and not menu_pose and not reduced_motion:
		tint = Color(1, 0.8, 0.7, 0.72)
	tint.a *= alpha
	var grounded := model.shoveling and ShovelStroke.contact_seconds(model.shovel_time, .0001, model.facing) > 0 and not menu_pose
	CaretakerAnimator.draw(canvas, at + Vector2(0, -hop), size, frame, flip, sway, tint, grounded, model.facing.y if not menu_pose else 0.0)

func player_hit() -> void:
	var feet := StairSurface.project(model.player)
	var first := particles.size()
	emit_snow(feet - Vector2(0,ShovelRig.size_at(model.player) * .78),Vector2.ZERO,6 if reduced_motion else 22,true)
	for i in range(first,particles.size()):
		if particles[i].has("floor"): particles[i].floor = feet.y + 4

func paint_hazard(canvas: Node2D, hazard: Dictionary) -> void:
	var point := Vector2(hazard.x, hazard.y)
	var target := StairSurface.project(point) - Vector2(0, model.snow.surface_height(point))
	var age: float = hazard.age
	var warning: float = hazard.warning
	var flight: float = hazard.flight
	if model.landing_warnings:
		var landing := minf(age / warning, 1.0)
		canvas.draw_set_transform(target, 0, Vector2(1, 0.48))
		canvas.draw_circle(Vector2.ZERO, 25 + sin(time * 9) * 2, Color(0.98, 0.44, 0.24, 0.16 + landing * 0.17))
		canvas.draw_arc(Vector2.ZERO, 27, -PI / 2, -PI / 2 + TAU * landing, 40, Color("ffd38c"), 2.5, true)
		canvas.draw_set_transform(Vector2.ZERO)
	IciclePainter.draw(canvas,point,target,age,warning,flight,reduced_motion)

func paint_clock(canvas: Node2D) -> void:
	var center := Vector2(1067, 203)
	for i in 12:
		var a := i * TAU / 12 - PI / 2
		canvas.draw_line(center + Vector2.from_angle(a) * 39, center + Vector2.from_angle(a) * 43, Color("76552e"), 2, true)
	# The round ends at midnight. Use the same remaining seconds as the HUD,
	# so pause, early completion and timeout also freeze these hands correctly.
	var remaining := maxf(0.0, model.time_left)
	# Relaxed play keeps the illustrated clock at 11:50 until the job is done.
	if model.assists.no_time_limit: remaining = 600.0 if model.state in ["playing","timeout","lost"] else 0.0
	var minute_angle := -PI / 2 - remaining * TAU / 3600.0
	var hour_angle := -PI / 2 - remaining * TAU / 43200.0
	var second_angle := -PI / 2 - remaining * TAU / 60.0
	canvas.draw_line(center, center + Vector2.from_angle(minute_angle) * 35, Color("433225"), 3, true)
	canvas.draw_line(center, center + Vector2.from_angle(hour_angle) * 22, Color("433225"), 4, true)
	var second_direction := Vector2.from_angle(second_angle)
	canvas.draw_line(center - second_direction * 6, center + second_direction * 38, Color("b9483f"), 1.4, true)
	canvas.draw_circle(center, 4, Color("ac7737"))

func paint_festive(canvas: Node2D, tree: bool, at: Vector2, size: float) -> void:
	var cell := Vector2(FESTIVE.get_width() / 2.0, FESTIVE.get_height())
	var source := Rect2(Vector2(cell.x if tree else 0.0, 0), cell)
	canvas.draw_texture_rect_region(FESTIVE, Rect2(at - Vector2(size * 0.5, size), Vector2.ONE * size), source)
