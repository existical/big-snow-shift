class_name WindowsDisplay
extends Node
## Owns only the native Windows window. Gameplay and Android never depend on it.

signal changed
signal before_switch

var profile: PlayerProfile
var window: Window
var enabled := false
var switching := false
var state: Dictionary = {}
var _normal := Rect2i()
var _poll_time := 0.0
var _stable_time := 0.0
var _dirty := false
var _shortcut_down := 0

static func defaults() -> Dictionary:
	return {"fullscreen":false, "maximized":false}

static func clean(value: Variant) -> Dictionary:
	var result := defaults()
	if not value is Dictionary: return result
	for key in ["fullscreen", "maximized"]:
		if value.get(key) is bool: result[key] = value[key]
	for key in ["rect", "screen_rect"]:
		var rect: Variant = value.get(key)
		if not rect is Array or rect.size() != 4: continue
		var valid := true
		for number in rect:
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 100000 or float(number) != floorf(float(number)):
				valid = false
		if valid and rect[2] >= 200 and rect[3] >= 150:
			result[key] = [int(rect[0]),int(rect[1]),int(rect[2]),int(rect[3])]
	return result

static func pack(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

static func unpack(rect: Array) -> Rect2i:
	return Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))

static func fit_rect(rect: Rect2i, usable: Rect2i) -> Rect2i:
	# Leave room for the title bar and window frame, including on small displays.
	var margin := Vector2i(16, 48)
	var available := Vector2i(maxi(200, usable.size.x - margin.x * 2), maxi(150, usable.size.y - margin.y * 2))
	var fitted := Rect2i(rect.position, Vector2i(clampi(rect.size.x, 200, available.x), clampi(rect.size.y, 150, available.y)))
	fitted.position.x = clampi(fitted.position.x, usable.position.x + margin.x, usable.end.x - margin.x - fitted.size.x)
	fitted.position.y = clampi(fitted.position.y, usable.position.y + margin.y, usable.end.y - margin.y - fitted.size.y)
	return fitted

static func find_screen(saved: Rect2i, screens: Array[Rect2i], fallback: int) -> int:
	# Monitor indices can change after undocking; geometry is a better identity.
	var best := clampi(fallback, 0, maxi(0, screens.size() - 1))
	var overlap := 0
	for i in screens.size():
		if screens[i] == saved: return i
		var area := screens[i].intersection(saved).get_area()
		if area > overlap:
			overlap = area
			best = i
	return best

func configure(owner_profile: PlayerProfile, native_window: Window, manage: bool) -> void:
	profile = owner_profile
	window = native_window
	state = clean(profile.settings.get("windows_display"))
	enabled = manage and OS.get_name() == "Windows" and DisplayServer.get_name() != "headless" and not window.is_embedded()
	set_process(enabled)
	if enabled: _restore.call_deferred()

func is_fullscreen() -> bool:
	if enabled:
		return window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	return bool(state.get("fullscreen", false))

func _screens() -> Array[Rect2i]:
	var screens: Array[Rect2i] = []
	for i in DisplayServer.get_screen_count():
		screens.append(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))
	return screens

func _restore() -> void:
	switching = true
	var target := window.current_screen
	if state.has("screen_rect"): target = find_screen(unpack(state.screen_rect), _screens(), target)
	window.mode = Window.MODE_WINDOWED
	window.borderless = false
	window.current_screen = target
	_normal = Rect2i(window.position, window.size)
	if state.has("rect"): _normal = unpack(state.rect)
	_normal = fit_rect(_normal, DisplayServer.screen_get_usable_rect(target))
	window.size = _normal.size
	window.position = _normal.position
	await get_tree().process_frame
	if state.fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	elif state.maximized:
		window.mode = Window.MODE_MAXIMIZED
	await get_tree().process_frame
	await get_tree().process_frame
	switching = false
	_capture()
	changed.emit()

func handle_shortcut(event: InputEvent) -> bool:
	if not enabled or not event is InputEventKey: return false
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if not event.pressed and key == _shortcut_down:
		_shortcut_down = 0
		return true
	var shortcut: bool = key == KEY_F11 or (key in [KEY_ENTER, KEY_KP_ENTER] and event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed)
	if not shortcut: return false
	if event.pressed:
		_shortcut_down = key
		if not event.echo: set_fullscreen(not is_fullscreen())
	return true

func set_fullscreen(value: bool) -> void:
	if not enabled or switching or value == is_fullscreen(): return
	_capture()
	switching = true
	before_switch.emit()
	var target := window.current_screen
	if value:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.borderless = false
		window.current_screen = target
		_normal = fit_rect(_normal, DisplayServer.screen_get_usable_rect(target))
		window.size = _normal.size
		window.position = _normal.position
		if state.maximized: window.mode = Window.MODE_MAXIMIZED
	await get_tree().process_frame
	await get_tree().process_frame
	switching = false
	_capture()
	flush()
	changed.emit()

func _capture() -> void:
	if not enabled or switching or window.mode == Window.MODE_MINIMIZED: return
	var previous := state.duplicate(true)
	state.fullscreen = is_fullscreen()
	if not state.fullscreen:
		state.maximized = window.mode == Window.MODE_MAXIMIZED
		if window.mode == Window.MODE_WINDOWED: _normal = Rect2i(window.position, window.size)
	state.rect = pack(_normal)
	state.screen_rect = pack(_screens()[window.current_screen])
	if previous != state:
		_dirty = true
		_stable_time = 0.0
		changed.emit()

func _process(delta: float) -> void:
	_poll_time += delta
	_stable_time += delta
	if _poll_time >= .25:
		_poll_time = 0.0
		_capture()
	if _dirty and _stable_time >= .5: flush()

func flush() -> void:
	if not enabled: return
	_capture()
	if _dirty:
		profile.settings.windows_display = state.duplicate(true)
		profile.save_async()
		_dirty = false
