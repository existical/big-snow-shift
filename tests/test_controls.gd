extends SceneTree

var game: Control
var checks := 0
var failures: Array[String] = []
const PROFILE := "res://builds/controls-test-profile.json"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func pointer(at: Vector2, pressed: bool, touch: bool = false, index: int = 0) -> void:
	var event: InputEvent
	if touch:
		event = InputEventScreenTouch.new()
		event.index = index
		event.pressed = pressed
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
	event.position = game.stage.get_global_transform_with_canvas() * at
	root.push_input(event,true)

func drag(at: Vector2, touch: bool = false, index: int = 0) -> void:
	var event: InputEvent
	if touch:
		event = InputEventScreenDrag.new()
		event.index = index
	else:
		event = InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = game.stage.get_global_transform_with_canvas() * at
	root.push_input(event,true)

func fresh(mode: String = "screen") -> void:
	game.model.begin_round(0)
	game.model.player = Vector2(.5,.5)
	game.model.spawn_countdown = 100
	game.profile.settings.control_mode = mode
	game.resume_game()
	game.apply_settings()

func advance(seconds: float) -> void:
	for tick in roundi(seconds / .05): game._physics_process(.05)

func test_profiles() -> void:
	check(PlayerProfile.new().settings.control_mode == "screen","new profiles default to screen controls")
	for mode in [null,"pad","screen","bad",3,true,[],{}]:
		var file := FileAccess.open(PROFILE,FileAccess.WRITE)
		var settings := {"music":.2,"touch":true}
		if mode != null: settings.control_mode = mode
		file.store_string(JSON.stringify({"version":1,"settings":settings,"run":{"id":"kept"},"scores":[{"name":"Kid","score":123}]}))
		file.close()
		var profile := PlayerProfile.new()
		profile.path = PROFILE
		profile.load_profile()
		check(profile.settings.control_mode == (mode if mode is String and mode in ["screen","pad"] else "screen"),"old or invalid control settings use the default; valid choices persist")
		check(profile.active_run.id == "kept" and profile.scores[0].score == 123 and is_equal_approx(profile.settings.music,.2),"control migration preserves runs, scores and audio settings")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PROFILE + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE + suffix))

func test_aiming() -> void:
	var input := ScreenSteering.new()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var anchor := Vector2(500,450)
	input.begin(event,anchor,anchor)
	check(input.held() and input.direction_at(anchor) == Vector2.ZERO,"pressing the body center is neutral")
	input.release()
	input.begin(event,anchor + Vector2(150,90),anchor)
	check(input.direction_at(anchor) == Vector2.RIGHT,"diagonal press chooses the nearest cardinal direction")
	check(input.direction_at(anchor + Vector2(140,0)) == Vector2.ZERO and input.direction_at(anchor + Vector2(160,0)) == Vector2.ZERO,"catching a stationary pointer stops without reversing or changing stair rows")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	input.track(motion,anchor + Vector2(100,110),anchor)
	check(input.direction_at(anchor) == Vector2.RIGHT,"small changes near the diagonal preserve the previous axis")
	input.track(motion,anchor + Vector2(90,150),anchor)
	check(input.direction_at(anchor) == Vector2.DOWN,"deliberate dragging changes to the other axis")
	motion.button_mask = 0
	input.track(motion,anchor,anchor)
	check(not input.held(),"lost mouse releases recover from a motion with no button held")
	event.button_index = MOUSE_BUTTON_RIGHT
	check(not input.begin(event,anchor + Vector2.RIGHT * 100,anchor),"right clicks do not steer")
	event.button_index = MOUSE_BUTTON_LEFT
	event.device = InputEvent.DEVICE_ID_EMULATION
	check(not input.begin(event,anchor + Vector2.RIGHT * 100,anchor),"emulated mouse events cannot duplicate native touch")

func run() -> void:
	test_profiles()
	test_aiming()
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = PROFILE
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	fresh()
	check(not game.pad.visible and not game.pad.enabled,"default gameplay has no control-pad HUD")
	for touch in [false,true]:
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			fresh()
			var at: Vector2 = game.control_anchor() + direction * 170
			pointer(at,true,touch,3)
			await process_frame
			check(game.movement_input() == direction,"native %s press steers %s" % ["touch" if touch else "mouse",direction])
			var before: Vector2 = game.model.player
			var snow_before: int = game.model.snow.remaining
			advance(.8)
			var delta: Vector2 = game.model.player - before
			check(delta.dot(direction) > .001 and absf(delta.dot(direction.orthogonal())) < .00001 and game.model.snow.remaining < snow_before,"held pointer moves and shovels along one axis through snow")
			pointer(at,false,touch,3)
			await process_frame
			before = game.model.player
			snow_before = game.model.snow.remaining
			advance(.6)
			check(not game.steering.held() and game.model.player == before and game.model.snow.remaining == snow_before and not game.model.shoveling,"release stops travel and clearing with no leftover input")
	fresh()
	var anchor: Vector2 = game.control_anchor()
	pointer(anchor + Vector2.RIGHT * 150,true,true,2)
	pointer(anchor + Vector2.LEFT * 150,true,true,9)
	pointer(anchor + Vector2.LEFT * 150,false,true,9)
	check(game.steering.finger == 2 and game.movement_input() == Vector2.RIGHT,"a second finger cannot hijack or release the steering finger")
	drag(anchor + Vector2.UP * 150,true,2)
	check(game.movement_input() == Vector2.UP,"a held finger can drag to turn")
	var cancel := InputEventScreenTouch.new()
	cancel.index = 2
	cancel.pressed = true
	cancel.canceled = true
	root.push_input(cancel,true)
	check(not game.steering.held(),"touch cancellation releases movement even without a normal up event")
	# Exercise inverse coordinates with the same translation/scale used for
	# letterboxing and Android safe areas; presses in the margins do nothing.
	game.stage.scale = Vector2.ONE * .75
	game.stage.position = Vector2(160,50)
	pointer(game.control_anchor() + Vector2.LEFT * 150,true)
	check(game.movement_input() == Vector2.LEFT,"mouse steering follows a scaled and offset stage")
	drag(Vector2(-15,300))
	check(not game.steering.held(),"dragging out of the fitted game area releases screen steering")
	pointer(Vector2(-15,300),false)
	pointer(Vector2(-15,300),true)
	check(not game.steering.held(),"presses in the letterbox margin do not start movement")
	pointer(Vector2(-15,300),false)
	pointer(game.control_anchor() + Vector2.DOWN * 150,true,true)
	check(game.movement_input() == Vector2.DOWN,"touch steering follows the same scaled and offset stage")
	drag(Vector2(-15,300),true,9)
	check(game.steering.finger == 0 and game.movement_input() == Vector2.DOWN,"a secondary finger outside the game cannot release the steering finger")
	drag(Vector2(-15,300))
	game._notification(Control.NOTIFICATION_WM_MOUSE_EXIT)
	check(game.steering.finger == 0 and game.movement_input() == Vector2.DOWN,"an unrelated mouse motion or exit cannot cancel held native touch")
	drag(Vector2(-15,300),true)
	check(not game.steering.held(),"the steering finger leaving the game does release its hold")
	pointer(game.control_anchor(),false,true)
	game.layout()
	fresh()
	pointer(game.control_anchor() + Vector2.LEFT * 150,true)
	Input.action_press("move_right")
	check(game.movement_input() == Vector2.RIGHT and not game.steering.held(),"keyboard/controller actions take priority over an opposite pointer hold")
	Input.action_release("move_right")
	check(game.movement_input() == Vector2.ZERO,"releasing conventional input does not resume a stale pointer hold")
	pointer(game.control_anchor(),false)
	pointer(game.control_anchor() + Vector2.LEFT * 150,true)
	pointer(Vector2(1218,58),false)
	check(game.view == "playing" and not game.steering.held(),"releasing a gameplay hold over a HUD button stops without clicking it")
	pointer(game.control_anchor() + Vector2.UP * 150,true,true,0)
	pointer(Vector2(1218,58),true,true,1)
	pointer(Vector2(1218,58),false,true,1)
	check(game.view == "pause" and not game.steering.held(),"a second finger can pause without stealing the movement finger")
	game.resume_game()
	pointer(Vector2(1218,58),true)
	check(not game.steering.held(),"the HUD pause button consumes its press before gameplay")
	pointer(Vector2(1218,58),false)
	check(game.view == "pause","clicking the HUD pause button still pauses")
	pointer(Vector2(640,354),true)
	pointer(Vector2(640,354),false)
	check(game.view == "playing" and not game.steering.held(),"the resume button cannot leak its click into gameplay")
	pointer(game.control_anchor() + Vector2.UP * 150,true,true)
	game._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.view == "pause" and not game.steering.held(),"focus loss pauses and releases held touch")
	game.resume_game()
	pointer(game.control_anchor() + Vector2.LEFT * 150,true)
	game.model.apply_hit()
	check(not game.steering.held(),"an icicle hit releases a held pointer")
	pointer(game.control_anchor() + Vector2.UP * 150,true,true)
	check(not game.steering.held(),"presses during hit recovery are not queued")
	game.model.stun = 0
	game.update_controls()
	check(game.movement_input() == Vector2.ZERO,"standing up does not automatically resume pointer movement")
	fresh()
	pointer(game.control_anchor() + Vector2.UP * 150,true)
	game.model.snow.brush(Vector2(.5,.5),Vector2.ONE * 2,255)
	advance(.05)
	check(game.model.state == "returning" and not game.steering.held(),"clearing the stairs releases the hold before the safe return")
	pointer(game.control_anchor() + Vector2.UP * 150,true)
	check(game.movement_input() == Vector2.UP,"a new hold can walk toward Santa after clearing")
	game.model.state = "greeting"
	game.model.ending_started.emit()
	game.update_controls()
	check(not game.steering.held() and not game.pad.visible and not game.screen_controls_available(),"Santa's scene disables both pointer methods")
	fresh()
	pointer(game.control_anchor() + Vector2.RIGHT * 150,true)
	game.layout()
	check(not game.steering.held(),"resizing releases a hold before the coordinate transform changes")
	game.show_settings("pause")
	var choice: Button = game.overlay.find_child("ControlPad",true,false)
	var at: Vector2 = game.stage.get_global_transform_with_canvas().affine_inverse() * choice.get_global_transform_with_canvas() * (choice.size * .5)
	pointer(at,true)
	pointer(at,false)
	check(game.profile.settings.control_mode == "pad" and choice.button_pressed,"settings offers a working control-pad alternative")
	game.close_settings()
	var recovered := PlayerProfile.new()
	recovered.path = PROFILE
	recovered.load_profile()
	check(recovered.settings.control_mode == "pad","the selected control method survives a disk reload")
	game.resume_game()
	check(game.pad.visible and game.pad.enabled and not game.screen_controls_available(),"selecting the pad restores its HUD and disables screen steering")
	for touch in [false,true]:
		fresh("pad")
		pointer(Vector2(136,514),true,touch)
		check(game.pad.direction.y < -.9 and not game.steering.held(),"the original pad still accepts mouse and touch")
		var before: float = game.model.player.y
		advance(.8)
		check(game.model.player.y < before,"the original pad still moves and clears snow")
		pointer(Vector2(136,514),false,touch)
		check(game.pad.direction == Vector2.ZERO,"the original pad releases cleanly")
	game.show_settings("pause")
	choice = game.overlay.find_child("ScreenControls",true,false)
	at = game.stage.get_global_transform_with_canvas().affine_inverse() * choice.get_global_transform_with_canvas() * (choice.size * .5)
	pointer(at,true)
	pointer(at,false)
	game.close_settings()
	game.resume_game()
	check(game.profile.settings.control_mode == "screen" and not game.pad.visible,"switching back hides the pad immediately")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/control-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	game.quit_game(0 if failures.is_empty() else 1)
