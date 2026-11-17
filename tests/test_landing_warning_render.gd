extends SceneTree

class HazardCanvas:
	extends Node2D
	var world: WinterWorld
	var hazard: Dictionary
	var whole_scene := false
	func _draw() -> void:
		if whole_scene: world.paint(self)
		else: world.paint_hazard(self,hazard)

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func _initialize() -> void:
	run.call_deferred()

func capture(canvas: Node2D, viewport: SubViewport) -> Image:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WinterWorld.new()
	world.model = GameModel.new(GameSettings.new())
	world.model.start(1,"extreme")
	var canvas := HazardCanvas.new()
	canvas.world = world
	canvas.hazard = {"x":.35,"y":.8,"age":1.6,"warning":2.0,"flight":1.0}
	viewport.add_child(canvas)
	for age in [1.6,2.4]:
		canvas.hazard.age = age
		world.model.landing_warnings = true
		var visible := await capture(canvas,viewport)
		world.model.landing_warnings = false
		var hidden := await capture(canvas,viewport)
		var point := Vector2(canvas.hazard.x,canvas.hazard.y)
		var target := StairSurface.project(point) - Vector2(0,world.model.snow.surface_height(point))
		var area := Rect2i(Vector2i(target)-Vector2i(32,17),Vector2i(64,34))
		check(visible.get_region(area).get_data() != hidden.get_region(area).get_data(),"stair marker removed at age "+str(age))
		check(hidden.get_region(area).is_invisible(),"no circle or arc remains at the impact location")
		var roof_and_fall := Rect2i(0,0,1280,area.position.y)
		check(not hidden.get_region(roof_and_fall).is_invisible(),"icicle remains visible while growing and falling")
		check(visible.get_region(roof_and_fall).get_data() == hidden.get_region(roof_and_fall).get_data(),"roof and falling sprite pixels unchanged")
	canvas.whole_scene = true
	world.model.landing_warnings = true
	world.menu_pose = true
	var menu_clear := await capture(canvas,viewport)
	world.model.hazards.append(canvas.hazard)
	var menu_storm := await capture(canvas,viewport)
	check(menu_clear.get_data() == menu_storm.get_data(),"title pose hides the icicle and its landing mark")
	world.menu_pose = false
	var playing_storm := await capture(canvas,viewport)
	world.model.hazards.clear()
	var playing_clear := await capture(canvas,viewport)
	check(playing_storm.get_data() != playing_clear.get_data(),"leaving the title restores hazard rendering")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/landing-warnings"))
	var output := "res://builds/landing-warnings/render-tests.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print(JSON.stringify({"checks":checks,"failures":failures}))
	world.free()
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
