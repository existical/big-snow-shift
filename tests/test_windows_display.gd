extends SceneTree
## Geometry/migration checks run headless; --native also exercises real Windows modes.
var checks := 0
var failures: Array[String] = []
const OUTPUT := "res://builds/windows-display/"
var game: Control

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func settle() -> void:
	await create_timer(.15).timeout
	await process_frame

func key(code: int, down: bool, alt: bool = false, echo: bool = false, target: Window = null) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	event.alt_pressed = alt
	event.echo = echo
	event.window_id = root.get_window_id() if target == null else target.get_window_id()
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	check(WindowsDisplay.clean(null) == WindowsDisplay.defaults(), "missing preferences start windowed")
	check(WindowsDisplay.clean({"fullscreen":"true", "rect":[0,0,-3,720]}).size() == 2, "invalid booleans/geometry rejected")
	check(not WindowsDisplay.clean({"rect":[0,0,INF,720]}).has("rect"), "nonfinite geometry rejected")
	var screens: Array[Rect2i] = [Rect2i(0,0,1920,1080),Rect2i(-2560,0,2560,1440)]
	check(WindowsDisplay.find_screen(screens[1],screens,0) == 1, "negative-coordinate monitor restored")
	check(WindowsDisplay.find_screen(screens[1],[screens[0]],0) == 0, "removed monitor falls back to connected display")
	check(WindowsDisplay.find_screen(screens[1],[screens[1],screens[0]],1) == 0, "monitor reorder uses geometry")
	for usable in [Rect2i(0,0,1920,1040),Rect2i(-2560,40,2560,1400),Rect2i(0,0,800,560)]:
		var fitted := WindowsDisplay.fit_rect(Rect2i(8000,-4000,3840,2160),usable)
		check(usable.encloses(fitted), "unplugged/oversized window remains in usable area: " + str(usable))
		check(fitted.position.y >= usable.position.y + 48, "title bar remains reachable")
	var profile := PlayerProfile.new()
	profile.path = OUTPUT + "profile.json"
	var legacy := profile.document()
	legacy.settings.erase("windows_display")
	PlayerProfile.write_document(ProjectSettings.globalize_path(profile.path),legacy)
	profile.load_profile()
	check(profile.settings.windows_display == WindowsDisplay.defaults(), "existing profile migrates without enabling fullscreen")
	profile.settings.windows_display = {"fullscreen":true,"maximized":true,"rect":[40,60,960,540],"screen_rect":[0,0,1920,1080]}
	profile.save()
	var loaded := PlayerProfile.new()
	loaded.path = profile.path
	loaded.load_profile()
	check(loaded.settings.windows_display == profile.settings.windows_display, "all window preferences survive JSON reload")
	profile.shutdown()
	loaded.shutdown()
	if "--native" in OS.get_cmdline_user_args(): await native_checks()
	FileAccess.open(OUTPUT + ("native.json" if "--native" in OS.get_cmdline_user_args() else "rules.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("WINDOWS_DISPLAY_CHECKS ", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func native_checks() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		check(false,"native suite requires Windows graphical renderer")
		return
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.sound.stopped = true
	game.profile.path = OUTPUT + "native-profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(game.profile.path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile.path + suffix))
	root.add_child(game)
	game.set_physics_process(false)
	game.change_language("en",false)
	var display: WindowsDisplay = game.windows_display
	display.configure(game.profile,root,true)
	await settle()
	check(display.enabled and root.mode == Window.MODE_WINDOWED,"new native profile starts in a decorated window")
	root.size = Vector2i(960,540)
	root.position += Vector2i(20,20)
	await settle()
	var original := Rect2i(root.position,root.size)
	var screen := root.current_screen
	game.show_settings("menu")
	await settle()
	var toggle: Button = game.overlay.find_child("FullscreenToggle",true,false)
	check(toggle != null and not toggle.button_pressed,"Windows Settings shows synchronized fullscreen toggle")
	var presses := [0]
	var done: Button
	for child in toggle.get_parent().get_children():
		if child.get_meta("translation_key","") == "settings.done": done = child
	done.pressed.connect(func(): presses[0] += 1)
	done.grab_focus()
	key(KEY_ENTER,true,true)
	key(KEY_ENTER,false) # Alt may be released before Enter.
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN and root.current_screen == screen,"Alt+Enter enters regular fullscreen on current monitor")
	check(toggle.button_pressed and presses[0] == 0 and game.view == "settings","shortcut synchronizes toggle without activating focused button")
	key(KEY_F11,true,false,true)
	key(KEY_F11,false)
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN,"key repeat does not toggle fullscreen")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"fullscreen-settings.png")
	key(KEY_F11,true)
	key(KEY_F11,false)
	await settle()
	check(root.mode == Window.MODE_WINDOWED and not root.borderless,"F11 restores decorated window")
	check(Rect2i(root.position,root.size) == original,"previous size and position restored exactly")
	check(not toggle.button_pressed,"F11 updates visible toggle")
	var language: OptionButton = game.overlay.find_child("LanguageChoice",true,false)
	language.show_popup()
	await settle()
	key(KEY_F11,true,false,false,language.get_popup())
	key(KEY_F11,false)
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN and not language.get_popup().visible,"fullscreen shortcut closes focused language popup safely")
	await display.set_fullscreen(false)
	# Exercise the actual GUI toggle signal as well as shortcuts.
	toggle.pressed.emit()
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN,"Settings toggle enters fullscreen")
	toggle.pressed.emit()
	await settle()
	root.mode = Window.MODE_MAXIMIZED
	await settle()
	await display.set_fullscreen(true)
	await display.set_fullscreen(false)
	check(root.mode == Window.MODE_MAXIMIZED,"maximized window restored after fullscreen")
	root.mode = Window.MODE_WINDOWED
	await settle()
	check(Rect2i(root.position,root.size) == original,"unmaximizing recovers normal window geometry")
	display.flush()
	game.profile.flush_pending()
	var writes: int = game.profile._writes
	await create_timer(.8).timeout
	check(game.profile._writes == writes,"stable window does not repeatedly write profile")
	root.mode = Window.MODE_MINIMIZED
	await create_timer(.3).timeout
	check(not display.state.maximized and not display.state.fullscreen and WindowsDisplay.unpack(display.state.rect) == original,"minimizing does not overwrite saved window state")
	root.mode = Window.MODE_WINDOWED
	await settle()
	# A text field must not submit its form on Alt+Enter.
	var edit := LineEdit.new()
	game.ui.add_child(edit)
	edit.text_submitted.connect(func(_text: String): presses[0] += 1)
	edit.grab_focus()
	key(KEY_ENTER,true,true)
	key(KEY_ENTER,false)
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN and presses[0] == 0,"Alt+Enter works with text focus without submitting")
	edit.queue_free()
	display.flush()
	game.profile.flush_pending()
	var reopened := PlayerProfile.new()
	reopened.path = game.profile.path
	reopened.load_profile()
	check(reopened.settings.windows_display.fullscreen,"fullscreen choice persisted to disk immediately")
	display.enabled = false
	display.set_process(false)
	root.mode = Window.MODE_WINDOWED
	var restored := WindowsDisplay.new()
	root.add_child(restored)
	restored.configure(reopened,root,true)
	await settle()
	check(root.mode == Window.MODE_FULLSCREEN,"fresh controller restores fullscreen from disk")
	await restored.set_fullscreen(false)
	restored.enabled = false
	restored.set_process(false)
	reopened.shutdown()
	restored.queue_free()
	display.enabled = true
	display.set_process(true)
	game.start_night()
	# Switching must release held steering; focus loss still pauses gameplay.
	game.steering.mouse_held = true
	await display.set_fullscreen(true)
	check(not game.steering.held(),"display transition releases held movement")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.view == "pause" and game.model.paused,"focus loss still pauses gameplay")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game.view == "pause","focus return does not resume gameplay automatically")
	game.show_settings("pause")
	check(game.overlay.find_child("FullscreenToggle",true,false).button_pressed,"pause Settings reflects actual mode")
	game.last_back_request = -1000
	game.handle_back_request()
	check(game.view == "pause" and root.mode == Window.MODE_FULLSCREEN,"Back leaves Settings without exiting fullscreen")
	await display.set_fullscreen(false)
	game.show_settings("menu")
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"windowed-settings.png")
	var system_info := {"screens":DisplayServer.get_screen_count(),"screen_size":str(DisplayServer.screen_get_size()),"dpi":DisplayServer.screen_get_dpi(),"scale":DisplayServer.screen_get_scale()}
	FileAccess.open(OUTPUT+"display.json",FileAccess.WRITE).store_string(JSON.stringify(system_info,"\t"))
	for dimensions in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1440),Vector2(3840,2160),Vector2(1024,768),Vector2(2560,1080)]:
		game.size = dimensions
		game.layout()
		var rect := Rect2(game.stage.position,game.stage.size*game.stage.scale)
		check(is_equal_approx(rect.size.x/rect.size.y,16.0/9.0) and Rect2(Vector2.ZERO,dimensions).encloses(rect),"uncropped 16:9 layout fits " + str(dimensions))
	display.flush()
	display.enabled = false
	game.profile.shutdown()
	game.sound.shutdown()
	game.queue_free()
	await process_frame
