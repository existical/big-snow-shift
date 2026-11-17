extends SceneTree
## Pixel regression for doorway snow, independent of the caretaker's depth.
const OUTPUT := "res://builds/door-snow/"
const THRESHOLD := Rect2i(580,332,120,32)
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var world: WinterWorld
var model: GameModel
var cached_snow: Image

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func picture(y: float) -> Image:
	model.player = Vector2(.04,y)
	world._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func opaque_snow_at(point: Vector2i) -> bool:
	var at := Vector2i((Vector2(point) - SnowCache.ORIGIN) / SnowCache.EXTENT * Vector2(SnowCache.SIZE))
	for dy in range(-1,2):
		for dx in range(-1,2):
			var p := at + Vector2i(dx,dy)
			if not Rect2i(Vector2i.ZERO,cached_snow.get_size()).has_point(p) or cached_snow.get_pixelv(p).a < .999: return false
	return true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = WinterWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	model = GameModel.new(GameSettings.new())
	model.start(731,"hard")
	model.paused = true
	world.set_model(model)
	var bottom := await picture(.93)
	var top := await picture(.025)
	bottom.save_png(OUTPUT+"caretaker-below.png")
	top.save_png(OUTPUT+"caretaker-top.png")
	cached_snow = world.snow_cache.color_view.get_texture().get_image()
	var opaque_points: Array[Vector2i] = []
	for y in range(THRESHOLD.position.y,THRESHOLD.end.y):
		for x in range(THRESHOLD.position.x,THRESHOLD.end.x):
			var point := Vector2i(x,y)
			if opaque_snow_at(point): opaque_points.append(point)
	check(opaque_points.size() > 100,"fixture has opaque snow overlapping the door bottom")
	for position in [.025,.09,.3,.6,.93]:
		var current := await picture(position)
		var changed := 0
		for point in opaque_points:
			if top.get_pixelv(point) != current.get_pixelv(point): changed += 1
		check(changed == 0,"opaque threshold snow unchanged at caretaker depth %.3f (%d changed pixels)" % [position,changed])
	# During a timeout the player-dependent snow pass is hidden. The doorway
	# must still stay behind snow while the panels open and Santa comes out.
	model.state = "timeout"
	model.time_left = 0
	for seconds in [0.0,.3,.6,.89,1.2]:
		model.failure_time = seconds
		var current := await picture(.93)
		var changed := 0
		for point in opaque_points:
			if top.get_pixelv(point) != current.get_pixelv(point): changed += 1
		if seconds < .9:
			check(changed == 0,"snow covers doorway during timeout opening at %.2f" % seconds)
		else:
			check(changed > 100,"Santa is drawn in front of snow after stepping outside")
		if seconds == .6: current.save_png(OUTPUT+"timeout-opening.png")
	# Clearing the snow exposes the genuine threshold, rather than a fixed
	# snowy patch painted over the doors.
	model.state = "playing"
	model.failure_time = 0
	model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,765)
	world.set_model(model)
	var clear_bottom := await picture(.93)
	var clear_top := await picture(.025)
	check(clear_bottom.get_region(THRESHOLD).get_data() == clear_top.get_region(THRESHOLD).get_data(),"cleared doorway is independent of caretaker depth")
	check(clear_bottom.get_region(THRESHOLD).get_data() != bottom.get_region(THRESHOLD).get_data(),"cleared snow reveals the real door threshold")
	clear_bottom.save_png(OUTPUT+"cleared-threshold.png")
	# Short Custom runs must draw the same doors/actors/tree as the equivalent
	# standard ending, even though their gameplay stage index is different.
	for count in [1,2]:
		for index in count:
			var mapped: int = [[2],[1,2]][count-1][index]
			for seconds in [0.0,.9,2.5,4.0,RoundEnding.duration(mapped)]:
				model.start(731,"hard")
				model.begin_round(mapped)
				model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,765)
				model.state = "greeting"
				model.ending_time = seconds
				model.time_left = 100
				world.set_model(model)
				var standard := await picture(.025)
				model.start(731,"hard",{"no_time_limit":false,"no_icicles":false},"custom",{},count)
				model.begin_round(index)
				model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,765)
				model.state = "greeting"
				model.ending_time = seconds
				model.time_left = 100
				world.set_model(model)
				var custom := await picture(.025)
				check(custom.get_data() == standard.get_data(),"Custom %d rounds, stage %d, phase %.2f preserves the original ending's pixels and depth" % [count,index,seconds])
				if seconds == 4.0: custom.save_png(OUTPUT+"custom-%d-stage-%d.png" % [count,index])
	var result := {"checks":checks,"failures":failures,"opaque_snow_pixels":opaque_points.size()}
	FileAccess.open(OUTPUT+"tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	world.free()
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
