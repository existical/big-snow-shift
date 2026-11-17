extends SceneTree

const REFERENCE = preload("res://tests/reference_snow.gdshader")
const OUTPUT := "res://builds/performance/optimized/"
var checks := 0
var failures: Array[String] = []
var cache: SnowCache
var reference: SubViewport
var quad: ColorRect
var field := SnowField.new()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func rendered() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

func compare(a: Image, b: Image, name: String, allowance: int = 80) -> void:
	var aa := a.get_data()
	var bb := b.get_data()
	var different := 0
	var max_delta := 0
	for i in aa.size():
		var delta := absi(int(aa[i]) - int(bb[i]))
		max_delta = maxi(delta, max_delta)
		if delta > 2: different += 1
	check(different <= allowance and max_delta <= 5, "%s differs in %d channels (max %d)" % [name, different, max_delta])
	print("SNOW_COMPARE ", name, " different=", different, " max=", max_delta)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: snow cache validation requires a graphical renderer")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	field.generate(1, rng)
	cache = SnowCache.new()
	root.add_child(cache)
	cache.bind(field)
	reference = SubViewport.new()
	reference.size = SnowCache.SIZE
	reference.disable_3d = true
	reference.transparent_bg = true
	reference.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	quad = ColorRect.new()
	quad.size = Vector2(SnowCache.SIZE)
	var material := ShaderMaterial.new()
	material.shader = REFERENCE
	SnowCache.configure(material)
	material.set_shader_parameter("snow_mask", cache.mask_texture)
	quad.material = material
	reference.add_child(quad)
	root.add_child(reference)
	await rendered()
	compare(cache.color_view.get_texture().get_image(), reference.get_texture().get_image(), "initial colour")
	cache.color_view.get_texture().get_image().save_png(OUTPUT + "cache-full.png")
	reference.get_texture().get_image().save_png(OUTPUT + "reference-full.png")
	check(RenderingServer.viewport_get_update_mode(cache.color_view.get_viewport_rid()) == RenderingServer.VIEWPORT_UPDATE_DISABLED, "cache stops rendering when unchanged")
	for operation in 6:
		match operation:
			0: field.brush(Vector2(.5,.65), Vector2(.28,.15), 255)
			1:
				for i in 4: field.add_pile(Vector2(.5,.65), 180, 1.5)
			2: field.box(Rect2(.0,.40,.25,.40), true)
			3:
				field.add_pile(Vector2(.05,.9), 180)
				cache.refresh(field)
				field.add_pile(Vector2(.95,.9), 180)
			4: field.tread_strip(15, 200, 1200, true)
			5: field.brush(Vector2(.5,.5), Vector2(2,2), 765)
		cache.refresh(field)
		await rendered()
		compare(cache.color_view.get_texture().get_image(), reference.get_texture().get_image(), "incremental colour %d" % operation)
		var partial := cache.color_view.get_texture().get_image()
		if operation < 5:
			check(cache.last_region.size.x < SnowCache.SIZE.x or cache.last_region.size.y < SnowCache.SIZE.y, "local change updates a partial rectangle")
		cache.invalidate(SnowField.ALL_CELLS)
		await rendered()
		compare(partial, cache.color_view.get_texture().get_image(), "partial equals complete rebuild %d" % operation)
	# Reset and test the first-hit depth against the old actor-dependent pass.
	field.generate(1, rng)
	field.brush(Vector2(.5,.55), Vector2(.2,.1), 255)
	field.add_pile(Vector2(.5,.65), 510)
	cache.bind(field)
	material.set_shader_parameter("snow_mask", cache.mask_texture)
	material.set_shader_parameter("foreground_only", true)
	var display := SubViewport.new()
	display.size = SnowCache.SIZE
	display.transparent_bg = true
	display.disable_3d = true
	display.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cached := ColorRect.new()
	cached.size = Vector2(SnowCache.SIZE)
	var cheap := ShaderMaterial.new()
	cheap.shader = preload("res://assets/art/cached_snow.gdshader")
	cheap.set_shader_parameter("snow_color", cache.color_view.get_texture())
	cheap.set_shader_parameter("snow_depth", cache.depth_view.get_texture())
	cheap.set_shader_parameter("stair_top", StairSurface.TOP)
	cheap.set_shader_parameter("stair_height", StairSurface.BOTTOM - StairSurface.TOP)
	cheap.set_shader_parameter("foreground_only", true)
	cached.material = cheap
	display.add_child(cached)
	root.add_child(display)
	for cutoff in [390.0, 487.5, 552.0, 635.25, 680.0]:
		material.set_shader_parameter("depth_cutoff", cutoff)
		cheap.set_shader_parameter("depth_cutoff", cutoff)
		await rendered()
		# RG16 quantization can affect only the sub-pixel cutoff boundary.
		compare(display.get_texture().get_image(), reference.get_texture().get_image(), "foreground %.2f" % cutoff, 400)
	cache.color_view.get_texture().get_image().save_png(OUTPUT + "cache-piles.png")
	FileAccess.open(OUTPUT + "snow-cache-tests.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	print(JSON.stringify({"snow_cache_checks":checks,"failures":failures}))
	reference.free()
	display.free()
	cache.free()
	quit(0 if failures.is_empty() else 1)
