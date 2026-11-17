extends Control

const BODY = preload("res://assets/fonts/Nunito.ttf")
const TITLE = preload("res://assets/art/title_logo_big_snow_shift_v0301.png")
const PAUSE_ICON = preload("res://assets/art/hud_pause.svg")
const RESUME_ICON = preload("res://assets/art/hud_resume.svg")
const SCORE_ICON = preload("res://assets/art/hud_score.svg")
const TIME_ICON = preload("res://assets/art/hud_clock.svg")
const CREAM := Color("fff4d8")
const MUTED := Color("d4f5ff")
const GOLD := Color("ffdc5c")
const CORNER_BUTTON_POSITION := Vector2(1174, 14)
const CORNER_BUTTON_SIZE := Vector2(88, 88)
const HUD_LABEL_SIZE := 24
const HUD_VALUE_SIZE := 34
const HUD_PAUSE_GAP := 20.0
const HUD_STAT_GAP := 24.0
var profile := PlayerProfile.new()
var windows_display := WindowsDisplay.new()
var localization := GameLocalization.new()
var model := GameModel.new()
var world := WinterWorld.new()
var sound := GameAudio.new()
var stage := Control.new()
var ui := Control.new()
var pad := TouchPad.new()
var steering := ScreenSteering.new()
var hud := Control.new()
var overlay := Control.new()
var toast_label: Label
var round_label: Label
var time_icon: TextureRect
var score_icon: TextureRect
var time_label: Label
var score_label: Label
var progress_label: Label
var progress_bar: Panel
var progress_fill: Panel
var pause_button: Button
var name_edit: LineEdit
var view := "menu"
var settings_return := "menu"
var save_timer := 0.0
var shovel_audio_timer := 0.0
var toast_time := 0.0
var active_run := false
var capture_path := ""
var qa_mode := false
var last_storage_warning := false
var pause_status: Label
var body_font := FontVariation.new()
var display_font := FontVariation.new()
var secondary_font := FontVariation.new()
var language_font := FontVariation.new()
var toast_key := ""
var toast_variables: Dictionary = {}
var last_back_request := -1000
var hud_cache: Array = []
var hud_score_digits := 0
var hud_digit_width := 0.0
var hud_timer_width := 0.0
var language_font_complete := false
var quitting := false
var selected_difficulty := "easy"
var selected_assists := {"no_time_limit":false,"no_icicles":false}
var selected_game_mode := "standard"
var selected_custom_parameters: Dictionary = {}
var selected_round_count := DifficultyRules.ROUND_COUNT
var custom_rows: Dictionary = {}
var custom_rounds: Array = []
var custom_player: Dictionary = {}
var standard_draft := "easy"
var difficulty_buttons: Array[Button] = []
var scores_tab := ""
var displayed_result: Dictionary = {}
var score_feedback: Dictionary = {}
var custom_advanced := false

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	for control in [stage, ui, hud, overlay]:
		control.layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().auto_accept_quit = false
	body_font.base_font = BODY
	body_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
	profile.load_profile()
	localization.initialize(profile.settings.language)
	profile.settings.language = localization.preference
	configure_localized_fonts()
	configure_input()
	var background := ColorRect.new()
	background.color = Color("071823")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	stage.size = Vector2(1280, 720)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.add_child(world)
	ui.size = Vector2(1280, 720)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Theme.new()
	ui.theme.default_font = body_font
	stage.add_child(ui)
	add_child(sound)
	ui.add_child(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.size = Vector2(1280, 720)
	build_hud()
	pad.position = Vector2(53, 491)
	ui.add_child(pad)
	ui.add_child(overlay)
	overlay.size = Vector2(1280, 720)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = label(ui, "", Vector2(350, 681), Vector2(580, 30), 18, CREAM)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast_label.add_theme_constant_override("shadow_offset_x", 1)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	model.hit.connect(on_hit)
	model.snow_cleared.connect(on_snow_cleared)
	model.ice_landed.connect(func(point: Vector2): world.ice_burst(point))
	model.round_completed.connect(on_round_completed)
	model.round_failed.connect(func(): sound.play_outcome("lose"))
	model.stairs_cleared.connect(func(): sound.play("chime"); release_controls(); toast("messages.clear", 8); store_run())
	model.ending_started.connect(func(): release_controls(); toast(["messages.handshake", "messages.present", "messages.magic"][model.ending_index()], 6); store_run())
	model.tree_revealed.connect(func(): sound.play("chime"); world.burst(Vector2(765, 510), 45, GOLD, 1.4))
	model.timeout_started.connect(func(): release_controls(); toast("messages.timeout", 6); store_run())
	model.santa_slipped.connect(func(): sound.play("hit"); world.burst(Vector2(640, 391), 14, Color("effaff"), .8))
	model.santa_landed.connect(func(): world.burst(Vector2(658, 677), 24, Color("effaff"), 1.0))
	model.start(731)
	model.paused = true
	world.set_model(model)
	apply_settings()
	resized.connect(layout)
	layout()
	if profile.pending_results.is_empty(): show_menu()
	else: show_result(profile.pending_results[0])
	localization.language_changed.connect(refresh_language)
	refresh_language(localization.active_code)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
			qa_mode = true
		if argument == "--auto-start":
			qa_mode = true
			start_night()
		if argument.begins_with("--language="):
			change_language(argument.trim_prefix("--language="), false)
	add_child(windows_display)
	windows_display.before_switch.connect(func():
		release_controls()
		var language: OptionButton = overlay.find_child("LanguageChoice",true,false)
		if language: language.get_popup().hide())
	windows_display.changed.connect(sync_fullscreen_button)
	windows_display.configure(profile, get_window(), not qa_mode and get_viewport() == get_tree().root)
	print("BIG_SNOW_SHIFT_GAME_READY version=%s landscape=true" % ProjectSettings.get_setting("application/config/version"))
	print("BIG_SNOW_SHIFT_PLAYER_SPEED multiplier=%.3f idle=%.3f scoop=%d recovery=%.3f" % [model.settings.player_speed_multiplier, model.settings.idle_animation_multiplier, model.settings.snow_per_scoop, model.settings.hit_recovery_seconds])
	if not capture_path.is_empty():
		capture.call_deferred()

func layout() -> void:
	release_controls()
	var available := size
	var origin := Vector2.ZERO
	if OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var window := Vector2(DisplayServer.window_get_size())
		if safe.size.x > 0 and safe.size.y > 0 and window.x > 0 and window.y > 0:
			var ratio := size / window
			origin = Vector2(safe.position) * ratio
			available = Vector2(safe.size) * ratio
	var fit := minf(available.x / 1280.0, available.y / 720.0)
	stage.scale = Vector2.ONE * fit
	stage.position = origin + (available - Vector2(1280, 720) * fit) * 0.5

func configure_input() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "pause_game": [KEY_ESCAPE, KEY_P]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for item in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0], ["move_up", JOY_AXIS_LEFT_Y, -1.0], ["move_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = item[1]
		event.axis_value = item[2]
		InputMap.action_add_event(item[0], event)
	for item in [["move_left", JOY_BUTTON_DPAD_LEFT], ["move_right", JOY_BUTTON_DPAD_RIGHT], ["move_up", JOY_BUTTON_DPAD_UP], ["move_down", JOY_BUTTON_DPAD_DOWN], ["pause_game", JOY_BUTTON_START]]:
		var event := InputEventJoypadButton.new()
		event.button_index = item[1]
		InputMap.action_add_event(item[0], event)

func _physics_process(delta: float) -> void:
	if quitting: return
	update_score_keyboard_layout()
	var was_ok := profile.storage_ok
	if not profile.poll_save():
		warn_storage_failure()
	else:
		last_storage_warning = false
	if view == "pause" and was_ok != profile.storage_ok: update_pause_status()
	shovel_audio_timer -= delta
	toast_time -= delta
	if toast_time <= 0:
		toast_label.text = ""
		toast_key = ""
	if view == "playing":
		model.step(delta, movement_input())
		refresh_hud()
		update_controls()
		if not model.is_active():
			store_run()
			show_result()
		else:
			save_timer += delta
			if save_timer >= 5:
				save_timer = 0
				store_run()

func release_controls() -> void:
	pad.release()
	steering.release()

func update_controls() -> void:
	var available := view == "playing" and not model.controls_locked()
	pad.visible = available and profile.settings.control_mode == "pad"
	pad.enabled = pad.visible and model.stun <= 0
	if not pad.enabled:
		pad.release()
	if not screen_controls_available():
		steering.release()

func screen_controls_available() -> bool:
	return view == "playing" and not model.controls_locked() and model.stun <= 0 and profile.settings.control_mode == "screen"

func control_anchor() -> Vector2:
	# Aim around the visible body center, above the ground-contact pivot.
	return StairSurface.project(model.player) - Vector2(0,ShovelRig.size_at(model.player) * .45)

func movement_input() -> Vector2:
	var conventional := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if conventional.length() > .1:
		# Do not add opposite inputs together or resume a stale pointer hold
		# when the child switches back from a keyboard/controller.
		release_controls()
		return conventional
	if screen_controls_available():
		return steering.direction_at(control_anchor())
	return pad.direction if pad.enabled else Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Handle display shortcuts before focused buttons/text fields consume Enter.
	if windows_display.handle_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	# An owned drag/release must arrive even over HUD buttons. New presses
	# start only in _unhandled_input, after the GUI has had first refusal.
	if not steering.held():
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		var at: Vector2 = stage.get_global_transform_with_canvas().affine_inverse() * event.position
		if steering.owns_motion(event) and not Rect2(Vector2.ZERO,stage.size).has_point(at):
			steering.release()
			get_viewport().set_input_as_handled()
			return
		if steering.track(event,at,control_anchor()):
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		handle_back_request()
		get_viewport().set_input_as_handled()
	elif screen_controls_available() and (event is InputEventMouseButton or event is InputEventScreenTouch):
		var at: Vector2 = stage.get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO,stage.size).has_point(at) and steering.begin(event,at,control_anchor()):
			get_viewport().set_input_as_handled()

func handle_back_request() -> void:
	# Android can report the same Back press as both Escape and a window notification.
	var now := Time.get_ticks_msec()
	if now - last_back_request < 350:
		return
	last_back_request = now
	if view == "settings":
		var language: OptionButton = overlay.find_child("LanguageChoice", true, false)
		if language and language.get_popup().visible:
			language.get_popup().hide()
			return
	if view == "playing":
		show_pause()
	elif view == "pause":
		resume_game()
	elif view == "settings":
		close_settings()
	elif view == "scores" or (view == "result" and not displayed_result.is_empty()):
		show_menu()
	elif view in ["credits", "privacy"]:
		show_settings(settings_return)
	elif view == "licenses":
		show_credits()
	elif view == "confirm":
		show_difficulty(false)
	elif view == "difficulty":
		difficulty_back()

func _notification(what: int) -> void:
	if quitting or not is_instance_valid(toast_label):
		return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		sound.set_suspended(true)
		release_controls()
		if view == "playing":
			show_pause()
		else:
			store_run(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back_request()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		sound.set_suspended(false)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		store_run()
		quit_game()
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		if steering.mouse_held:
			steering.release()
		if pad.mouse_held:
			pad.release()

func quit_game(code: int = 0) -> void:
	if quitting: return
	quitting = true
	model.paused = true
	windows_display.flush()
	var saved := profile.shutdown()
	if not saved:
		warn_storage_failure()
	sound.shutdown()
	# Allow the audio thread to release active playback before engine teardown.
	# Give an actual storage failure time to remain readable before closing.
	await get_tree().create_timer(.12 if saved else 2.0).timeout
	get_tree().quit(code)

func box(fill: Color, radius: int = 18, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func panel(parent: Node, at: Vector2, dimensions: Vector2, compact: bool = false) -> Panel:
	var node := Panel.new()
	node.layout_direction = Control.LAYOUT_DIRECTION_LTR
	node.position = at
	node.set_meta("layout_position", at)
	node.size = dimensions
	var style := box(Color("286cb1"), 23, Color("94dff7"))
	style.set_border_width_all(4)
	style.shadow_color = Color(0.025, 0.09, 0.24, .65)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 7)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	var trim := FestiveTrim.new()
	trim.layout_direction = Control.LAYOUT_DIRECTION_LTR
	trim.size = dimensions
	trim.compact = compact
	node.add_child(trim)
	return node

func label(parent: Node, text_value: String, at: Vector2, dimensions: Vector2, font_size: int = 20, color: Color = CREAM, display: bool = false) -> Label:
	var node := Label.new()
	node.layout_direction = Control.LAYOUT_DIRECTION_LTR
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.text = localization.text(text_value) if localization.english.has(text_value) else text_value
	if localization.english.has(text_value):
		node.set_meta("translation_key", text_value)
	node.position = at
	node.set_meta("layout_position", at)
	node.size = dimensions
	node.set_meta("translation_size", dimensions)
	node.clip_text = true
	if dimensions.y >= font_size * 1.8:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", (secondary_font if font_size <= 25 else display_font) if display else body_font)
	node.add_theme_font_size_override("font_size", font_size)
	node.set_meta("translation_font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if display:
		node.add_theme_color_override("font_outline_color", Color("17365a"))
		node.add_theme_constant_override("outline_size", 3 if font_size <= 25 else 4)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	fit_localized_text(node)
	return node

func button(parent: Node, text_value: String, at: Vector2, dimensions: Vector2, callback: Callable, primary: bool = false, fill_override: Color = Color.TRANSPARENT) -> Button:
	var node := Button.new()
	node.layout_direction = Control.LAYOUT_DIRECTION_LTR
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.clip_text = true
	node.text = localization.text(text_value) if localization.english.has(text_value) else text_value
	if localization.english.has(text_value):
		node.set_meta("translation_key", text_value)
	node.position = at
	node.set_meta("layout_position", at)
	node.size = dimensions
	node.set_meta("translation_size", dimensions)
	node.add_theme_font_override("font", display_font if primary else secondary_font)
	node.add_theme_font_size_override("font_size", 26 if dimensions.x > 260 else 21)
	node.set_meta("translation_font_size", 26 if dimensions.x > 260 else 21)
	if MenuIcons.ACTIONS.has(text_value):
		node.icon = MenuIcons.ACTIONS[text_value]
		node.expand_icon = true
		node.autowrap_mode = TextServer.AUTOWRAP_WORD
		node.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		node.add_theme_constant_override("icon_max_width", 44)
		node.add_theme_constant_override("h_separation", 14)
	var fill := Color("36ae58") if primary else Color("1e9dc7")
	if text_value in ["common.settings", "common.credits"]:
		fill = Color("8554c8")
	elif text_value == "common.scores" and not primary:
		fill = Color("e78a23")
	if fill_override.a > 0:
		fill = fill_override
	var ink := Color.WHITE
	for state_name in ["normal", "hover", "pressed"]:
		var color := fill.lightened(.12) if state_name == "hover" else (fill.darkened(.08) if state_name == "pressed" else fill)
		var style := box(color, 17, fill.lightened(.43))
		style.set_border_width_all(3)
		style.shadow_color = fill.darkened(.5)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 2 if state_name == "pressed" else 6)
		node.add_theme_stylebox_override(state_name, style)
	var focus := box(Color.TRANSPARENT, 18, GOLD)
	focus.set_border_width_all(3)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 8
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_color_override("font_outline_color", fill.darkened(.6))
	node.add_theme_constant_override("outline_size", 3)
	for color_type in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(color_type, ink)
	for color_type in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		node.add_theme_color_override(color_type, ink)
	node.add_theme_color_override("font_hover_pressed_color", ink)
	node.pressed.connect(func(): sound.play("click"); callback.call())
	parent.add_child(node)
	fit_localized_text(node)
	return node

func clear_overlay(next_view: String) -> void:
	if next_view != "scores": score_feedback = {}
	if next_view != "result": displayed_result = {}
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	# Build every language in the same authored screen coordinates.
	overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	overlay.position = Vector2.ZERO
	view = next_view
	world.menu_pose = next_view == "menu"
	if OS.is_debug_build():
		print("BIG_SNOW_SHIFT_VIEW ", view)
	model.paused = next_view != "playing"
	model.moving = false
	release_controls()
	update_controls()
	hud.visible = next_view in ["playing", "pause", "result"] or (next_view == "settings" and settings_return == "pause")
	update_pause_button()
	toast_label.text = ""
	toast_key = ""
	sync_audio()

func sync_audio() -> void:
	var game_view := view in ["playing","pause","result"] or (view in ["settings","credits","licenses","privacy"] and settings_return == "pause")
	if game_view and (model.state in ["won","lost"] or (view == "result" and not displayed_result.is_empty())):
		sound.set_context("quiet")
	elif game_view:
		sound.set_context("game",view in ["pause","settings","credits","licenses","privacy","difficulty"])
	else:
		sound.set_context("menu")

func show_menu() -> void:
	if active_run:
		store_run(true)
	clear_overlay("menu")
	var logo := TextureRect.new()
	logo.layout_direction = Control.LAYOUT_DIRECTION_LTR
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.texture = TITLE
	logo.accessibility_name = "Big Snow Shift — with Uncle Bolyus"
	logo.position = Vector2(24, 30)
	logo.size = Vector2(624, 278)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(logo)
	label(overlay, "menu.tagline", Vector2(54, 302), Vector2(490, 32), 22, GOLD, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var has_save := not profile.active_run.is_empty()
	var card := panel(overlay, Vector2(40, 347), Vector2(624, 360 if has_save else 284))
	var menu_hint := label(card, "menu.instructions", Vector2(28, 18), Vector2(568, 46), 23, CREAM, true)
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if has_save:
		var saved_rules: Dictionary = profile.active_run.rules if profile.active_run.get("rules") is Dictionary else {}
		var saved_mode := String(saved_rules.get("difficulty",""))
		var previous_game: bool = (profile.active_run.get("legacy_run",false) or saved_rules.is_empty()) and not profile.active_run.get("adjusted_run",false)
		var mode_text := mode_caption(saved_mode,GameModel.saved_mode(profile.active_run),previous_game)
		var saved_round := int(profile.active_run.stage) if DifficultyRules.number(profile.active_run.get("stage"),0,2) else 0
		bind_text(menu_hint,"difficulty.saved",{"round":saved_round+1,"difficulty":mode_text})
	var pending := not profile.pending_results.is_empty()
	if pending:
		button(card,"result.save",Vector2(320,80),Vector2(276,80),func(): show_result(profile.pending_results[0]))
	var primary := button(card, "menu.continue" if has_save else "menu.play", Vector2(28, 80), Vector2(276 if pending else 568, 80), continue_night if has_save else func(): show_difficulty(), true)
	primary.add_theme_font_size_override("font_size", 36)
	primary.set_meta("translation_font_size", 36)
	primary.add_theme_constant_override("icon_max_width", 56)
	fit_localized_text(primary, true)
	if has_save:
		button(card, "menu.newGame", Vector2(28, 176), Vector2(568, 64), func(): show_difficulty())
		button(card, "common.scores", Vector2(28, 256), Vector2(276, 80), show_scores)
		button(card, "common.settings", Vector2(320, 256), Vector2(276, 80), func(): show_settings("menu"))
	else:
		button(card, "common.scores", Vector2(28, 180), Vector2(276, 80), show_scores)
		button(card, "common.settings", Vector2(320, 180), Vector2(276, 80), func(): show_settings("menu"))
	var exit_button := button(overlay, "", CORNER_BUTTON_POSITION, CORNER_BUTTON_SIZE, exit_from_menu, false, Color("df414a"))
	exit_button.name = "ExitGame"
	exit_button.icon = MenuIcons.CLOSE
	exit_button.expand_icon = true
	exit_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_button.add_theme_constant_override("icon_max_width", 38)
	for state_name in ["normal", "hover", "pressed"]:
		var style := exit_button.get_theme_stylebox(state_name) as StyleBoxFlat
		style.content_margin_left = 8
		style.content_margin_right = 8
	exit_button.tooltip_text = localization.text("menu.exit")
	exit_button.accessibility_name = exit_button.tooltip_text
	exit_button.set_meta("tooltip_key", "menu.exit")
	exit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fit_localized_text(exit_button, true)
	primary.grab_focus()
	apply_ui_direction()

func exit_from_menu() -> void:
	var exit_button := overlay.get_node_or_null("ExitGame") as Button
	if exit_button:
		exit_button.disabled = true
	release_controls()
	store_run()
	quit_game()

func confirm_new_night() -> void:
	clear_overlay("confirm")
	var card := panel(overlay, Vector2(300, 188), Vector2(680, 344))
	label(card, "confirm.title", Vector2(28, 24), Vector2(624, 60), 34, CREAM, true)
	label(card, "confirm.description", Vector2(28, 102), Vector2(624, 82), 20, MUTED)
	button(card, "confirm.continue", Vector2(28, 232), Vector2(300, 84), continue_night).grab_focus()
	button(card, "confirm.start", Vector2(352, 232), Vector2(300, 84), start_night, true)
	apply_ui_direction()

func start_night() -> void:
	sound.begin_gameplay()
	# New games use code defaults; Continue uses its saved rules.
	model.development_player = DifficultyRules.player_values(GameSettings.new())
	model.base_stages = JSON.parse_string(FileAccess.get_file_as_string(GameModel.STAGES))
	model.difficulty_config = DifficultyRules.catalog()
	model.start(0,selected_difficulty,selected_assists,selected_game_mode,selected_custom_parameters,selected_round_count)
	save_mode_preferences()
	active_run = true
	save_timer = 0
	world.set_model(model)
	resume_game()
	toast(control_hint(),6)
	store_run()

func mode_text() -> String:
	return mode_caption(model.difficulty_id,model.game_mode,model.legacy_run and not model.adjusted_run)

func mode_caption(id: String, mode: String, legacy: bool = false) -> String:
	var base := localization.text("difficulty."+id) if id in DifficultyRules.IDS else localization.text("difficulty.previous")
	if mode == "custom": return localization.text("custom.title")
	return localization.text("difficulty.previous") if legacy else base

func load_mode_selection() -> void:
	selected_game_mode = profile.settings.game_mode
	standard_draft = profile.settings.difficulty
	selected_difficulty = "hard" if selected_game_mode == "custom" else profile.settings.difficulty
	selected_assists = profile.settings.custom_assists.duplicate()
	selected_custom_parameters = profile.settings.custom_parameters.duplicate()
	selected_round_count = profile.settings.custom_round_count
	custom_rounds = JSON.parse_string(FileAccess.get_file_as_string(GameModel.STAGES))
	custom_player = DifficultyRules.player_values(GameSettings.new())

func save_mode_preferences() -> void:
	profile.settings.game_mode = selected_game_mode
	if selected_game_mode == "custom":
		profile.settings.custom_round_count = selected_round_count
		profile.settings.custom_parameters = selected_custom_parameters.duplicate()
		profile.settings.custom_assists = selected_assists.duplicate()
	else:
		profile.settings.difficulty = selected_difficulty

func open_custom_game() -> void:
	if view != "difficulty": return
	standard_draft = selected_difficulty
	custom_advanced = false
	selected_game_mode = "custom"
	selected_difficulty = "hard" # Legacy rule metadata only; Custom has no difficulty choice.
	selected_custom_parameters = profile.settings.custom_parameters.duplicate()
	selected_assists = profile.settings.custom_assists.duplicate()
	selected_round_count = profile.settings.custom_round_count
	show_difficulty(false)

func difficulty_back() -> void:
	if custom_advanced:
		change_custom_page(false)
		return
	if selected_game_mode == "custom":
		selected_game_mode = "standard"
		selected_difficulty = standard_draft
		show_difficulty(false)
	else:
		close_difficulty()

func show_difficulty(reset: bool = true) -> void:
	# New games start from Main menu; other screens cannot enter setup.
	if view not in ["menu","difficulty","confirm"]: return
	if reset:
		custom_advanced = false
		load_mode_selection()
	var custom := selected_game_mode == "custom"
	clear_overlay("difficulty")
	difficulty_buttons.clear()
	var card := panel(overlay,Vector2(44,24),Vector2(1192,672))
	card.name = "CustomGamePanel" if custom else "DifficultyPanel"
	if custom:
		build_custom_editor(card)
		apply_ui_direction()
		return
	label(card,"custom.title" if custom else "difficulty.title",Vector2(32,14),Vector2(1128,60),40,GOLD,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(card,"difficulty.nextGame",Vector2(32,80),Vector2(1128,42),20,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for i in 4:
		var id: String = DifficultyRules.IDS[i]
		var choice := button(card,"",Vector2(32+i*286,138),Vector2(270,330),func(): select_difficulty(id))
		choice.name = "Difficulty_"+id
		choice.toggle_mode = true
		choice.button_group = group
		choice.set_meta("difficulty_id",id)
		choice.accessibility_name = localization.text("difficulty."+id)+". "+localization.text("difficulty."+id+"Help")
		var selected := box(Color("237f83"),17,GOLD)
		selected.set_border_width_all(4)
		choice.add_theme_stylebox_override("pressed",selected)
		choice.add_theme_stylebox_override("hover_pressed",selected)
		var portrait := DifficultyPortrait.new()
		portrait.difficulty = id
		portrait.position = Vector2(135,102)
		choice.add_child(portrait)
		label(choice,"difficulty."+id,Vector2(12,202),Vector2(246,46),30,CREAM,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label(choice,"difficulty."+id+"Help",Vector2(16,248),Vector2(238,74),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tick := stat_icon(choice,MenuIcons.CHECK,Vector2(224,15),30)
		tick.name = "Selected"
		difficulty_buttons.append(choice)
	button(card,"custom.title",Vector2(32,496),Vector2(350,76),open_custom_game).name = "CustomGame"
	label(card,"custom.invitation",Vector2(406,496),Vector2(754,76),20,MUTED)
	button(card,"difficulty.back",Vector2(32,596),Vector2(250,68),difficulty_back).name = "DifficultyBack"
	var commit := button(card,"difficulty.start",Vector2(790,596),Vector2(370,68),commit_difficulty,true)
	commit.name = "DifficultyStart"
	select_difficulty(selected_difficulty)
	difficulty_buttons[DifficultyRules.IDS.find(selected_difficulty)].grab_focus()
	apply_ui_direction()

func change_custom_page(advanced: bool) -> void:
	custom_advanced = advanced
	show_difficulty(false)

func build_custom_editor(card: Control) -> void:
	custom_rows.clear()
	label(card,"custom.more" if custom_advanced else "custom.title",Vector2(32,14),Vector2(1128,60),40,GOLD,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if custom_advanced:
		build_custom_parameters(card)
		var back := button(card,"difficulty.back",Vector2(32,560),Vector2(330,88),func(): change_custom_page(false))
		back.name = "CustomOverview"
		refresh_custom_editor()
		back.grab_focus()
		return
	label(card,"custom.instructions",Vector2(32,82),Vector2(1128,54),22,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 3:
		var key: String = ["no_time_limit","no_icicles","landing_warnings"][i]
		var title_key: String = ["difficulty.noTime","difficulty.noIce","custom.landingWarnings"][i]
		var at := Vector2(32+i*576,275) if i < 2 else Vector2(608,394)
		var assist := button(card,title_key,at,Vector2(552,88),func(): pass)
		assist.name = "Assist_"+key
		assist.toggle_mode = true
		assist.button_pressed = selected_custom_parameters.get(key,true) if key == "landing_warnings" else selected_assists[key]
		assist.icon = MenuIcons.CHECK if assist.button_pressed else MenuIcons.UNCHECKED
		var selected := box(Color("33854d"),17,GOLD)
		selected.set_border_width_all(3)
		assist.add_theme_stylebox_override("pressed",selected)
		assist.add_theme_stylebox_override("hover_pressed",selected)
		assist.toggled.connect(func(enabled: bool):
			if key == "landing_warnings": selected_custom_parameters[key] = enabled
			else: selected_assists[key] = enabled
			assist.icon = MenuIcons.CHECK if enabled else MenuIcons.UNCHECKED
			refresh_custom_editor())
	button(card,"custom.more",Vector2(32,394),Vector2(552,88),func(): change_custom_page(true)).name = "CustomMore"
	label(card,"custom.rounds",Vector2(32,156),Vector2(246,88),23,CREAM,true).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var round_group := ButtonGroup.new()
	for count in range(1,DifficultyRules.ROUND_COUNT+1):
		var choice := button(card,str(count),Vector2(304+(count-1)*290,156),Vector2(276,88),func():
			selected_round_count = count)
		choice.name = "CustomRounds_"+str(count)
		choice.toggle_mode = true
		choice.button_group = round_group
		choice.set_pressed_no_signal(count == selected_round_count)
		choice.accessibility_name = localization.text("custom.rounds")+": "+str(count)
		var selected := box(Color("33854d"),17,GOLD)
		selected.set_border_width_all(3)
		choice.add_theme_stylebox_override("pressed",selected)
		choice.add_theme_stylebox_override("hover_pressed",selected)
	button(card,"difficulty.back",Vector2(32,560),Vector2(250,88),difficulty_back).name = "DifficultyBack"
	button(card,"custom.reset",Vector2(306,560),Vector2(430,88),func():
		selected_custom_parameters = DifficultyRules.custom_defaults()
		selected_assists = {"no_time_limit":false,"no_icicles":false}
		selected_round_count = DifficultyRules.ROUND_COUNT
		show_difficulty(false)).name = "CustomReset"
	var commit := button(card,"difficulty.start",Vector2(790,560),Vector2(370,88),commit_difficulty,true)
	commit.name = "DifficultyStart"
	refresh_custom_editor()
	(card.get_node("Assist_no_time_limit") as Button).grab_focus()

func build_custom_parameters(card: Control) -> void:
	for i in CustomRules.FIELDS.size():
		var field: Array = CustomRules.FIELDS[i]
		var key: String = field[0]
		var row := Panel.new()
		row.layout_direction = Control.LAYOUT_DIRECTION_LTR
		row.position = Vector2(32+(i%2)*576,108+(i/2)*108)
		row.set_meta("layout_position",row.position)
		row.size = Vector2(552,100)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel",box(Color(0.02,.13,.28,.28),12))
		card.add_child(row)
		var title := label(row,field[1],Vector2(14,6),Vector2(231,88),21,CREAM)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var value := label(row,"",Vector2(338,6),Vector2(114,88),23,GOLD,true)
		value.text_direction = Control.TEXT_DIRECTION_LTR
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var decrease := custom_step_button(row,key,-1,Vector2(248,6),field[1])
		var increase := custom_step_button(row,key,1,Vector2(458,6),field[1])
		custom_rows[key] = {"row":row,"value":value,"decrease":decrease,"increase":increase}

func custom_step_button(parent: Control, key: String, direction: int, at: Vector2, title_key: String) -> Button:
	var control := button(parent,"",at,Vector2(88,88),func():
		selected_custom_parameters[key] = CustomRules.adjusted(selected_custom_parameters,key,direction,custom_player)
		refresh_custom_editor())
	control.name = "Custom_"+key+("_less" if direction < 0 else "_more")
	control.icon = MenuIcons.MINUS if direction < 0 else MenuIcons.PLUS
	control.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.accessibility_name = localization.text("custom.decrease" if direction < 0 else "custom.increase",{"setting":localization.text(title_key)})
	control.tooltip_text = control.accessibility_name
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := control.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = 4
		style.content_margin_right = 4
		control.add_theme_stylebox_override(state,style)
	control.add_theme_color_override("icon_normal_color",CREAM)
	control.add_theme_color_override("icon_hover_color",CREAM)
	control.add_theme_color_override("icon_pressed_color",CREAM)
	return control

func refresh_custom_editor() -> void:
	var warnings := overlay.find_child("Assist_landing_warnings",true,false) as Button
	if warnings:
		warnings.disabled = selected_assists.no_icicles
		warnings.modulate.a = .45 if warnings.disabled else 1.0
	for key in custom_rows:
		var controls: Dictionary = custom_rows[key]
		var inactive: bool = selected_assists.no_time_limit if key == "extra_seconds" else selected_assists.no_icicles
		controls.row.modulate.a = .45 if inactive else 1.0
		controls.value.text = CustomRules.value(selected_custom_parameters,key,custom_rounds,custom_player,localization)
		controls.value.accessibility_name = controls.value.text
		fit_localized_text(controls.value,true)
		controls.decrease.disabled = inactive or is_equal_approx(CustomRules.adjusted(selected_custom_parameters,key,-1,custom_player),selected_custom_parameters[key])
		controls.increase.disabled = inactive or is_equal_approx(CustomRules.adjusted(selected_custom_parameters,key,1,custom_player),selected_custom_parameters[key])

func select_difficulty(id: String) -> void:
	selected_difficulty = id
	for choice in difficulty_buttons:
		choice.set_pressed_no_signal(choice.get_meta("difficulty_id") == id)
		choice.get_node("Selected").visible = choice.button_pressed

func close_difficulty() -> void:
	show_menu()

func commit_difficulty() -> void:
	if view != "difficulty": return
	if not profile.active_run.is_empty(): confirm_new_night()
	else: start_night()

func continue_night() -> void:
	if profile.active_run.get("state","") in ["won","lost"]:
		active_run = false
		profile.active_run = {}
		if not qa_mode: profile.save()
		show_menu()
		return
	if profile.restore_active(model):
		active_run = true
		world.set_model(model)
		if model.is_active():
			show_pause()
		else:
			show_result()
	else:
		active_run = false
		profile.active_run = {}
		profile.save()
		show_menu()
		toast("messages.restoreFailed", 6)

func resume_game() -> void:
	clear_overlay("playing")
	refresh_hud()
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

func toggle_pause() -> void:
	if view == "playing":
		show_pause()
	elif view == "pause":
		resume_game()

func resume_caption() -> String:
	# A paused round, walk to the door and Santa scene all resume the same game.
	return "pause.resume"

func update_pause_button() -> void:
	# Only the pause overlay can be dismissed by this shortcut. Settings and
	# results keep their own navigation and must never resume the round directly.
	pause_button.visible = view in ["playing", "pause"]
	pause_button.disabled = not pause_button.visible
	pause_button.icon = RESUME_ICON if view == "pause" else PAUSE_ICON
	var key := resume_caption() if view == "pause" else "hud.pause"
	pause_button.set_meta("tooltip_key", key)
	pause_button.tooltip_text = localization.text(key)
	pause_button.accessibility_name = pause_button.tooltip_text

func build_hud() -> void:
	# Direct outlined lettering leaves the illustration and roof warning area visible.
	round_label = label(hud, "", Vector2(28, 14), Vector2(320, 36), HUD_LABEL_SIZE, GOLD, true)
	progress_label = label(hud, "", Vector2(28, 56), Vector2(432, 36), HUD_LABEL_SIZE, CREAM, true)
	progress_bar = Panel.new()
	progress_bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	progress_bar.position = Vector2(29, 90)
	progress_bar.size = Vector2(210, 16)
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := box(Color("102f5340"), 8, Color("a5d9ed66"))
	var fill := box(Color("80eea2b3"), 7)
	fill.set_border_width_all(0)
	for style in [track, fill]:
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		style.content_margin_left = 0
		style.content_margin_right = 0
	progress_bar.add_theme_stylebox_override("panel", track)
	hud.add_child(progress_bar)
	progress_fill = Panel.new()
	progress_fill.layout_direction = Control.LAYOUT_DIRECTION_LTR
	progress_fill.position = Vector2.ONE
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_fill.add_theme_stylebox_override("panel", fill)
	progress_bar.add_child(progress_fill)
	time_icon = stat_icon(hud, TIME_ICON, Vector2(0, 32), 36)
	time_label = label(hud, "", Vector2(0, 28), Vector2(128, 52), HUD_VALUE_SIZE, CREAM, true)
	time_label.text_direction = Control.TEXT_DIRECTION_LTR
	# The pointed star needs a larger box than the circular clock to carry
	# similar visual weight. Both remain centred on y = 50.
	score_icon = stat_icon(hud, SCORE_ICON, Vector2(0, 29), 42)
	score_label = label(hud, "", Vector2(0, 28), Vector2(168, 52), HUD_VALUE_SIZE, CREAM, true)
	score_label.text_direction = Control.TEXT_DIRECTION_LTR
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_button = button(hud, "", CORNER_BUTTON_POSITION, CORNER_BUTTON_SIZE, toggle_pause)
	pause_button.name = "PauseResume"
	pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var alpha := .20 if state_name == "pressed" else (.12 if state_name == "hover" else .06)
		var style := box(Color(CREAM, alpha), 17)
		style.set_border_width_all(0)
		style.set_expand_margin_all(-10)
		style.content_margin_left = 18
		style.content_margin_right = 18
		pause_button.add_theme_stylebox_override(state_name, style)
	var focus := box(Color.TRANSPARENT, 17, Color(GOLD, .7))
	focus.set_border_width_all(2)
	pause_button.add_theme_stylebox_override("focus", focus)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		pause_button.add_theme_color_override("icon_" + state_name + "_color", Color.WHITE)
	update_pause_button()
	layout_hud_text()
	apply_ui_direction()

func stat_icon(parent: Control, texture: Texture2D, at: Vector2, dimension: float) -> TextureRect:
	var node := TextureRect.new()
	node.layout_direction = Control.LAYOUT_DIRECTION_LTR
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = at
	node.size = Vector2.ONE * dimension
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("layout_position", at)
	parent.add_child(node)
	return node

func hud_text_vertical_bounds(text: String, font: Font, font_size: int) -> Vector2:
	# Glyph bounds omit the font's unused ascender/descender space. Measure only
	# when laying out a language, never when the countdown or score changes.
	var line := TextLine.new()
	line.add_string(text, font, font_size, localization.active_code)
	var ascent := line.get_line_ascent()
	var server := TextServerManager.get_primary_interface()
	var bounds := Vector2(INF, -INF)
	for glyph in server.shaped_text_get_glyphs(line.get_rid()):
		if not glyph.font_rid.is_valid(): continue
		var size_key := Vector2i(glyph.font_size, 0)
		var dimensions := server.font_get_glyph_size(glyph.font_rid, size_key, glyph.index)
		if dimensions.y <= 0: continue
		var top: float = ascent + glyph.offset.y + server.font_get_glyph_offset(glyph.font_rid, size_key, glyph.index).y
		bounds.x = minf(bounds.x, top)
		bounds.y = maxf(bounds.y, top + dimensions.y)
	return bounds if is_finite(bounds.x) else Vector2(0, font.get_height(font_size))

func layout_hud_text() -> void:
	# Reserve the native line height instead of shrinking taller regional scripts.
	var heading_height := maxf(36, ceilf(secondary_font.get_height(HUD_LABEL_SIZE)) + 2)
	var next_row_y := 14 + heading_height
	# Align visible digit shapes with the icon centres, ignoring unused font
	# padding. Both values share the same size and vertical position in every locale.
	var digits := hud_text_vertical_bounds("0123456789", display_font, HUD_VALUE_SIZE)
	var value_y := 50.0 - (digits.x + digits.y) * .5
	for entry in [[round_label, Vector2(28,14), Vector2(320,heading_height)],
		[progress_label, Vector2(28,next_row_y+6), Vector2(432,heading_height)]]:
		var node: Label = entry[0]
		node.position = entry[1]
		node.set_meta("layout_position", entry[1])
		node.set_meta("translation_size", entry[2])
		fit_localized_text(node, true)
	progress_bar.position.y = next_row_y + heading_height + 12
	progress_bar.set_meta("layout_position", progress_bar.position)
	# The localized display faces have tabular digits. Cache one digit slot and
	# a full MM:SS timer slot per language, never measure changing values per frame.
	hud_digit_width = 0
	for digit in "0123456789":
		# A single glyph's width is rounded down by some font faces. Measure a
		# run before rounding the slot up so multi-digit values never shrink.
		var run_width := display_font.get_string_size(digit.repeat(8), HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_VALUE_SIZE).x
		hud_digit_width = maxf(hud_digit_width, ceilf(run_width / 8))
	hud_timer_width = ceilf(hud_digit_width * 4 + display_font.get_string_size(":", HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_VALUE_SIZE).x) + 4
	for node in [time_label, score_label]:
		node.position.y = value_y
		node.set_meta("translation_size", Vector2(0, maxf(52, ceilf(display_font.get_height(HUD_VALUE_SIZE)) + 2)))
	layout_hud_stats(true)

func layout_hud_stats(force: bool = false) -> void:
	var digit_count := str(model.score).length()
	if not force and digit_count == hud_score_digits: return
	hud_score_digits = digit_count
	# Keep the score's right edge beside Pause. Additional digits push the star
	# and timer left together; ordinary score changes and timer ticks stay still.
	var score_width := ceilf(hud_digit_width * digit_count) + 4
	score_label.position.x = CORNER_BUTTON_POSITION.x - HUD_PAUSE_GAP - score_width
	score_icon.position.x = score_label.position.x - 5 - score_icon.size.x
	time_label.position.x = score_icon.position.x - HUD_STAT_GAP - hud_timer_width
	time_icon.position.x = time_label.position.x - 10 - time_icon.size.x
	for entry in [[score_label, score_width], [time_label, hud_timer_width]]:
		var node: Label = entry[0]
		var dimensions: Vector2 = node.get_meta("translation_size")
		dimensions.x = entry[1]
		node.set_meta("translation_size", dimensions)
		fit_localized_text(node, true)
	for node in [score_label, score_icon, time_label, time_icon]:
		node.set_meta("layout_position", node.position)

func refresh_hud() -> void:
	var seconds := int(ceil(model.time_left))
	var next: Array = [localization.active_code, model.stage_index, model.state, seconds, model.score, model.snow.remaining, model.snow.initial,model.assists.no_time_limit,model.round_count]
	if next == hud_cache: return
	var language_changed: bool = hud_cache.is_empty() or hud_cache[0] != next[0]
	var round_changed: bool = language_changed or hud_cache[1] != next[1] or hud_cache[8] != next[8]
	var state_changed: bool = language_changed or hud_cache[2] != next[2] or hud_cache[7] != next[7]
	if round_changed:
		round_label.text = localization.text("hud.round", {"round": model.stage_index + 1, "total": model.round_count})
		fit_localized_text(round_label)
	if state_changed:
		var time_key := "hud.timeSaved" if model.state in ["returning", "greeting", "celebrating", "won"] else "hud.time"
		if model.assists.no_time_limit: time_key = "difficulty.untimed"
		time_label.set_meta("stat_key", time_key)
		time_icon.accessibility_name = localization.text(time_key)
	if language_changed:
		score_icon.accessibility_name = localization.text("hud.score")
	if state_changed or hud_cache[3] != seconds:
		time_label.text = "∞" if model.assists.no_time_limit else "%d:%02d" % [seconds / 60, seconds % 60]
		fit_localized_text(time_label)
	if state_changed or hud_cache[3] != seconds:
		time_label.accessibility_name = time_icon.accessibility_name + ": " + time_label.text
	if state_changed or (hud_cache[3] <= 20) != (seconds <= 20):
		time_label.add_theme_color_override("font_color", Color("ffac8e") if model.state == "playing" and seconds <= 20 and not model.assists.no_time_limit else CREAM)
	if language_changed or hud_cache[4] != next[4]:
		score_label.text = str(model.score)
		layout_hud_stats()
		fit_localized_text(score_label)
		score_label.accessibility_name = score_icon.accessibility_name + ": " + score_label.text
	var cleared := model.snow.completion() * 100
	if round_changed or hud_cache[2] != next[2] or hud_cache[5] != next[5] or hud_cache[6] != next[6]:
		progress_label.text = localization.text("hud.cleared", {"percent": int(cleared)})
		if model.state == "returning":
			progress_label.text = localization.text("hud.return")
		elif model.state == "greeting":
			progress_label.text = localization.text(["hud.handshake", "hud.present", "hud.magic"][model.ending_index()])
		elif model.state == "timeout":
			progress_label.text = localization.text("hud.timeout")
		fit_localized_text(progress_label)
		progress_fill.size = Vector2((progress_bar.size.x - 2) * cleared / 100, progress_bar.size.y - 2)
		progress_fill.visible = cleared > 0
	hud_cache = next

func show_pause() -> void:
	clear_overlay("pause")
	store_run(true)
	var card := panel(overlay, Vector2(340, 144), Vector2(600, 432))
	label(card, "pause.title", Vector2(28, 24), Vector2(544, 64), 43, GOLD, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_status = label(card, "", Vector2(28, 93), Vector2(544, 60), 19, MUTED)
	pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_pause_status()
	button(card, resume_caption(), Vector2(28, 160), Vector2(544, 68), resume_game, true).grab_focus()
	button(card, "common.settings", Vector2(28, 244), Vector2(544, 64), func(): show_settings("pause"))
	button(card, "common.mainMenu", Vector2(28, 324), Vector2(544, 68), show_menu)
	refresh_hud()
	apply_ui_direction()

func update_pause_status() -> void:
	if not is_instance_valid(pause_status) or not pause_status.is_inside_tree(): return
	if profile.storage_ok: bind_text(pause_status,"difficulty.paused",{"difficulty":mode_text()})
	else: bind_text(pause_status,"messages.storageFailed")

func show_result(pending: Dictionary = {}) -> void:
	if pending.is_empty() and model.state in ["won","lost"]: store_run(true)
	displayed_result = pending if not pending.is_empty() else profile.record_victory(model)
	clear_overlay("result")
	refresh_hud()
	var won := not displayed_result.is_empty()
	if not pending.is_empty():
		hud.hide()
		world.menu_pose = true
	var lost := model.state == "lost"
	var card := panel(overlay, Vector2(38,132), Vector2(520,552))
	label(card, "result.wonHeading" if won else ("result.lostHeading" if lost else "result.roundHeading"), Vector2(28, 22), Vector2(464, 28), 14, GOLD)
	label(card, "result.wonTitle" if won else ("result.lostTitle" if lost else "result.roundTitle"), Vector2(28, 58), Vector2(464, 124 if won else 70), 44 if won else 37, CREAM, true)
	var text_y := 192 if won else 144
	var message := "result.wonMessage" if won else ("result.lostMessage" if lost else ("result.handshakeMessage" if model.ending_index() == 0 else "result.presentMessage"))
	var description := label(card, message, Vector2(28, text_y), Vector2(464, 70), 18, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_icon(card, SCORE_ICON, Vector2(28, 281), 30)
	var points := label(card, "", Vector2(70, 273), Vector2(422, 46), 30, CREAM, true)
	bind_text(points, "result.points", {"score": "%06d" % int(displayed_result.score if won else model.score)})
	label(card,mode_caption(displayed_result.difficulty,displayed_result.game_mode) if won else mode_text(),Vector2(28,318),Vector2(464,28),18,GOLD)
	if won:
		if displayed_result.category == "standard" and displayed_result.difficulty in ["hard","extreme"]:
			var badge := panel(overlay,Vector2(646,104),Vector2(566,156),true)
			stat_icon(badge,MenuIcons.TROPHY,Vector2(24,25),58)
			label(badge,"difficulty.hero" if displayed_result.difficulty == "hard" else "difficulty.extremeHero",Vector2(100,18),Vector2(440,50),32,GOLD,true)
			label(badge,"difficulty.heroHelp" if displayed_result.difficulty == "hard" else "difficulty.extremeHeroHelp",Vector2(24,82),Vector2(518,54),20,CREAM)
		ensure_multilingual_font()
		name_edit = LineEdit.new()
		name_edit.name = "PlayerName"
		name_edit.layout_direction = Control.LAYOUT_DIRECTION_LTR
		name_edit.position = Vector2(28, 379)
		name_edit.set_meta("layout_position", Vector2(28, 379))
		name_edit.size = Vector2(464, 56)
		name_edit.max_length = 18
		name_edit.text = profile.player_name
		name_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_edit.placeholder_text = localization.text("result.name")
		name_edit.set_meta("placeholder_key", "result.name")
		name_edit.add_theme_font_override("font", language_font)
		name_edit.add_theme_font_size_override("font_size", 20)
		name_edit.add_theme_stylebox_override("normal", box(Color("173946"), 10, MUTED))
		card.add_child(name_edit)
		var name_prompt := label(card, "result.name", Vector2(28, 346), Vector2(464, 33), 21, GOLD, true)
		name_edit.accessibility_name = name_prompt.text
		name_prompt.name = "ScoreNamePrompt"
		button(card,"common.mainMenu",Vector2(28,456),Vector2(210,68),show_menu)
		button(card, "result.save", Vector2(254, 456), Vector2(238, 68), submit_score, true).grab_focus()
	elif lost:
		button(card, "result.retry", Vector2(28,376), Vector2(464,68), retry_round, true).grab_focus()
		button(card, "common.mainMenu", Vector2(28,460), Vector2(464,64), show_menu)
	else:
		var summary := label(card, "", Vector2(28, 346), Vector2(464, 28), 17, GOLD)
		bind_text(summary, "result.summary", {"bonus": model.last_reward, "hits": model.round_hits})
		button(card, "result.next", Vector2(28, 376), Vector2(464, 68), next_round, true).grab_focus()
		button(card, "common.mainMenu", Vector2(28, 460), Vector2(464, 64), show_menu)
	apply_ui_direction()

func next_round() -> void:
	model.next_round()
	world.set_model(model)
	resume_game()
	store_run()

func retry_round() -> void:
	sound.begin_gameplay()
	model.begin_round(model.stage_index)
	active_run = true
	world.set_model(model)
	resume_game()
	store_run()

func submit_score() -> void:
	var result := displayed_result.duplicate()
	if result.is_empty(): return
	var saved := profile.submit_pending(result.id, name_edit.text)
	if not saved:
		toast("messages.scoreFailed", 6)
		return
	name_edit.release_focus()
	DisplayServer.virtual_keyboard_hide()
	var tab: String = result.difficulty if result.category == "standard" and result.balance == DifficultyRules.version_for(result.difficulty) else "personal"
	score_feedback = {"id":result.id,"tab":tab,"score":result.score,"best":profile.last_was_best}
	show_scores(tab)

func update_score_keyboard_layout() -> void:
	if OS.get_name() != "Android" or view != "result" or displayed_result.is_empty() or not is_instance_valid(name_edit):
		return
	var card := name_edit.get_parent() as Panel
	var compact := name_edit.has_focus() and DisplayServer.virtual_keyboard_get_height() > 0
	if compact == bool(card.get_meta("keyboard_compact", false)):
		return
	card.set_meta("keyboard_compact", compact)
	card.position = Vector2(38, 12 if compact else 132)
	card.size.y = 252 if compact else 552
	for child in card.get_children():
		if not child is Control: continue
		if compact:
			child.set_meta("before_keyboard_visible", child.visible)
			child.visible = child == name_edit or child is Button or child is FestiveTrim or child.name == "ScoreNamePrompt"
		else:
			child.visible = bool(child.get_meta("before_keyboard_visible", true))
		if child == name_edit:
			child.position.y = 78 if compact else 379
		elif child is Button:
			child.position.y = 156 if compact else 456
		elif child.name == "ScoreNamePrompt":
			child.position.y = 22 if compact else 346
		elif child is FestiveTrim:
			child.size = card.size
			child.queue_redraw()

func show_scores(tab: String = "", focus_tab: bool = false) -> void:
	ensure_multilingual_font()
	if not tab.is_empty(): scores_tab = tab
	# Older in-memory selections cannot reopen the retired archive tab.
	if scores_tab not in DifficultyRules.IDS and scores_tab != "personal": scores_tab = profile.settings.difficulty
	clear_overlay("scores")
	var card := panel(overlay, Vector2(110, 24), Vector2(1060, 672))
	label(card, "scores.title", Vector2(28, 16), Vector2(1004, 54), 32, GOLD, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 4:
		var id: String = DifficultyRules.IDS[i]
		var tab_button := button(card,"difficulty."+id,Vector2(28+i*254,84),Vector2(242,64),func(): show_scores(id,true),scores_tab == id)
		tab_button.name = "Scores_"+id
		if id in profile.badges:
			tab_button.icon = MenuIcons.TROPHY
			fit_localized_text(tab_button,true)
	button(card,"scores.personal",Vector2(692,160),Vector2(340,68),func(): show_scores("personal",true),scores_tab == "personal").name = "Scores_personal"
	var caption := label(card,"",Vector2(28,160),Vector2(640,68),19,MUTED)
	if scores_tab in DifficultyRules.IDS: bind_text(caption,"scores.modeHelp",{"difficulty":localization.text("difficulty."+scores_tab)})
	else: bind_text(caption,"scores.personalHelp")
	var entries := profile.scores_for(scores_tab)
	if entries.is_empty():
		label(card, "scores.empty", Vector2(28, 290), Vector2(1004, 90), 23, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "ScoreScroll"
		scroll.position = Vector2(28,246)
		scroll.size = Vector2(1004,294)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		card.add_child(scroll)
		var rows := Control.new()
		rows.custom_minimum_size = Vector2(980,entries.size()*36)
		rows.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll.add_child(rows)
		for i in entries.size():
			var entry: Dictionary = entries[i]
			if score_feedback.get("id","") != "" and entry.get("id","") == score_feedback.id:
				var highlight := Panel.new()
				highlight.position = Vector2(0,i*36)
				highlight.size = Vector2(978,36)
				highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
				highlight.add_theme_stylebox_override("panel",box(Color(1,.85,.2,.2),7))
				rows.add_child(highlight)
			var entry_label := label(rows, "%02d   %s" % [i + 1, entry.name], Vector2(12, i * 36), Vector2(426, 36), 20)
			entry_label.add_theme_font_override("font", language_font)
			fit_localized_text(entry_label, true)
			if scores_tab == "personal":
				var id: String = entry.get("difficulty","")
				var entry_mode := mode_caption(id,entry.get("game_mode","standard"))
				if entry.get("game_mode","standard") == "custom": entry_mode += " · "+localization.text("custom.rounds")+": "+str(entry.get("round_count",DifficultyRules.ROUND_COUNT))
				label(rows,entry_mode,Vector2(450,i*36),Vector2(300,36),18,MUTED)
			label(rows, str(entry.score), Vector2(754, i * 36), Vector2(210, 36), 21, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if scores_tab == score_feedback.get("tab",""):
		var retained := entries.any(func(entry): return entry.get("id","") == score_feedback.id)
		var feedback := label(card,"",Vector2(28,540),Vector2(1004,42),22,GOLD,true)
		if score_feedback.best:
			bind_text(feedback,"scores.best",{"difficulty":localization.text("difficulty."+scores_tab)})
		elif not retained:
			bind_text(feedback,"scores.outside",{"score":score_feedback.score})
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var home := button(card, "common.mainMenu", Vector2(298, 590), Vector2(464, 60), show_menu)
	if focus_tab: (card.get_node("Scores_"+scores_tab) as Button).grab_focus()
	else: home.grab_focus()
	apply_ui_direction()

func show_settings(return_view: String) -> void:
	ensure_multilingual_font()
	settings_return = return_view
	clear_overlay("settings")
	var desktop := OS.get_name() == "Windows"
	var card := panel(overlay, Vector2(120 if desktop else 290, 62 if desktop else 24), Vector2(1040 if desktop else 700, 596 if desktop else 672))
	label(card, "settings.title", Vector2(28, 14), Vector2(card.size.x - 56, 65), 42, GOLD, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_icon(card, MenuIcons.LANGUAGE, Vector2(28, 96), 36)
	label(card, "settings.language", Vector2(78, 94), Vector2(170, 44), 18, Color.WHITE)
	var language_choice := TouchOptionButton.new()
	language_choice.layout_direction = Control.LAYOUT_DIRECTION_LTR
	language_choice.name = "LanguageChoice"
	language_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_choice.position = Vector2(260, 92)
	language_choice.set_meta("layout_position", Vector2(260, 92))
	language_choice.size = Vector2(752 if desktop else 412, 60)
	language_choice.fit_to_longest_item = false
	language_choice.clip_text = true
	language_choice.add_theme_font_override("font", language_font)
	language_choice.add_theme_font_size_override("font_size", 17)
	language_choice.add_item(localization.text("settings.system"))
	language_choice.set_item_metadata(0, "system")
	var selected_language := 0
	for entry in localization.languages:
		language_choice.add_item(entry.name)
		var index := language_choice.item_count - 1
		language_choice.set_item_metadata(index, entry.code)
		if entry.code == localization.preference:
			selected_language = index
	language_choice.select(selected_language)
	language_choice.choice_selected.connect(func(index: int): change_language(language_choice.get_item_metadata(index)))
	language_choice.back_dismissed.connect(func(): last_back_request = Time.get_ticks_msec())
	language_choice.get_popup().window_input.connect(func(event: InputEvent):
		if windows_display.handle_shortcut(event): language_choice.get_popup().set_input_as_handled())
	language_choice.get_popup().max_size = Vector2i(650, 500)
	language_choice.get_popup().add_theme_font_override("font", language_font)
	language_choice.get_popup().add_theme_font_size_override("font_size", 18)
	card.add_child(language_choice)
	for index in 2:
		var key := "music" if index == 0 else "effects"
		var row_y := 164 + index * 94 if desktop else 155 + index * 90
		stat_icon(card, MenuIcons.MUSIC if index == 0 else MenuIcons.SOUND, Vector2(28, row_y + 24), 36)
		label(card, "settings.music" if index == 0 else "settings.effects", Vector2(78, row_y + 22), Vector2(160 if desktop else 186, 44), 20, Color.WHITE)
		var slider := HSlider.new()
		slider.name = "MusicVolume" if index == 0 else "EffectsVolume"
		slider.layout_direction = Control.LAYOUT_DIRECTION_LTR
		slider.position = Vector2(254 if desktop else 278, row_y)
		slider.size = Vector2(246 if desktop else 394, 88)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		var groove := box(Color("174879"), 5)
		groove.content_margin_top = 5
		groove.content_margin_bottom = 5
		slider.add_theme_stylebox_override("slider", groove)
		var volume_fill := box(Color("73e5cd"), 5)
		volume_fill.content_margin_top = 5
		volume_fill.content_margin_bottom = 5
		slider.add_theme_stylebox_override("grabber_area", volume_fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", volume_fill)
		slider.value = profile.settings[key]
		slider.value_changed.connect(func(value: float): profile.settings[key] = value; apply_settings())
		card.add_child(slider)
	if desktop:
		var fullscreen := button(card,"settings.fullscreen",Vector2(28,350),Vector2(472,72),func(): windows_display.set_fullscreen(not windows_display.is_fullscreen()))
		fullscreen.name = "FullscreenToggle"
		fullscreen.toggle_mode = true
		fullscreen.set_meta("extra_text_margin",44)
		var selected_style := box(Color("33854d"),17,GOLD)
		selected_style.set_border_width_all(3)
		fullscreen.add_theme_stylebox_override("pressed",selected_style)
		fullscreen.add_theme_stylebox_override("hover_pressed",selected_style)
		for style_name in ["normal","hover","pressed","hover_pressed"]:
			fullscreen.get_theme_stylebox(style_name).content_margin_right = 64
		fit_localized_text(fullscreen,true)
		var check_icon := stat_icon(fullscreen,MenuIcons.UNCHECKED,Vector2(420,20),32)
		check_icon.name = "FullscreenCheck"
		label(card,"settings.fullscreenKeys",Vector2(28,434),Vector2(472,32),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sync_fullscreen_button()
	label(card,"settings.controls",Vector2(540,174) if desktop else Vector2(28,338),Vector2(472 if desktop else 644,32),23,GOLD,true)
	var group := ButtonGroup.new()
	var help := label(card,control_help(),Vector2(540,404) if desktop else Vector2(28,472),Vector2(472,96) if desktop else Vector2(644,58),18,MUTED)
	for index in 2:
		var mode := "screen" if index == 0 else "pad"
		var choice := button(card,"settings.screen" if index == 0 else "settings.pad",Vector2(540,214 + index * 96) if desktop else Vector2(28 + index * 330,380),Vector2(472,80) if desktop else Vector2(314,88),func(): pass)
		choice.name = "ScreenControls" if index == 0 else "ControlPad"
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = profile.settings.control_mode == mode
		var selected_style := box(Color("33854d"),17,Color("ffdc5c"))
		selected_style.set_border_width_all(3)
		choice.add_theme_stylebox_override("pressed",selected_style)
		choice.add_theme_stylebox_override("hover_pressed",selected_style)
		choice.toggled.connect(func(selected: bool):
			if selected:
				profile.settings.control_mode = mode
				apply_settings()
				bind_text(help, control_help()))
	var action_width := (card.size.x - 88.0) / 3.0
	button(card, "settings.done", Vector2(28,508 if desktop else 550), Vector2(action_width,64), close_settings, true).grab_focus()
	button(card, "settings.privacy", Vector2(44 + action_width,508 if desktop else 550), Vector2(action_width,64), show_privacy).name = "PrivacyButton"
	button(card, "common.credits", Vector2(60 + action_width * 2,508 if desktop else 550), Vector2(action_width,64), show_credits)
	apply_ui_direction()

func sync_fullscreen_button() -> void:
	var toggle: Button = overlay.find_child("FullscreenToggle",true,false)
	if not toggle: return
	var active := windows_display.is_fullscreen()
	toggle.set_pressed_no_signal(active)
	var icon: TextureRect = toggle.get_node("FullscreenCheck")
	icon.texture = MenuIcons.CHECK if active else MenuIcons.UNCHECKED

func control_help() -> String:
	return "settings.screenHelp" if profile.settings.control_mode == "screen" else "settings.padHelp"

func control_hint() -> String:
	if profile.settings.control_mode == "pad":
		return "messages.padHint"
	return "messages.touchHint" if OS.get_name() == "Android" else "messages.mouseHint"

func show_credits(licenses: bool = false) -> void:
	clear_overlay("licenses" if licenses else "credits")
	var card := panel(overlay, Vector2(250, 72), Vector2(780, 576))
	label(card, "credits.licenses" if licenses else "credits.title", Vector2(28, 20), Vector2(720, 56), 37, CREAM, true)
	var text := RichTextLabel.new()
	text.name = "CreditsText"
	text.layout_direction = Control.LAYOUT_DIRECTION_LTR
	text.position = Vector2(28, 95)
	text.size = Vector2(724, 360)
	text.add_theme_font_override("normal_font", body_font)
	text.add_theme_font_size_override("normal_font_size", 18)
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.set_meta("credits_body", licenses)
	text.text = licenses_text() if licenses else credits_text()
	card.add_child(text)
	if licenses:
		button(card, "difficulty.back", Vector2(28, 488), Vector2(724, 64), show_credits, true).grab_focus()
	else:
		button(card, "credits.back", Vector2(28, 488), Vector2(352, 64), func(): show_settings(settings_return), true).grab_focus()
		button(card, "credits.licenses", Vector2(400, 488), Vector2(352, 64), func(): show_credits(true)).name = "LicensesButton"
	apply_ui_direction()

func show_privacy() -> void:
	clear_overlay("privacy")
	var card := panel(overlay, Vector2(250, 72), Vector2(780, 576))
	label(card, "settings.privacy", Vector2(28, 20), Vector2(724, 56), 37, CREAM, true)
	var text := RichTextLabel.new()
	text.name = "PrivacyText"
	text.layout_direction = Control.LAYOUT_DIRECTION_LTR
	text.text_direction = Control.TEXT_DIRECTION_LTR
	text.position = Vector2(28, 95)
	text.size = Vector2(724, 360)
	text.add_theme_font_override("normal_font", body_font)
	text.add_theme_font_size_override("normal_font_size", 18)
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.text = FileAccess.get_file_as_string("res://assets/licenses/PRIVACY_POLICY.txt")
	card.add_child(text)
	button(card, "credits.back", Vector2(28, 488), Vector2(724, 64), func(): show_settings(settings_return), true).grab_focus()
	apply_ui_direction()

func close_settings() -> void:
	profile.save()
	if settings_return == "pause":
		show_pause()
	else:
		show_menu()

func apply_settings() -> void:
	release_controls()
	update_controls()
	# Player settings always use the normal animation/effects path.
	world.reduced_motion = false
	sound.apply(profile.settings)

func configure_localized_fonts() -> void:
	var fallbacks := localization.fallback_fonts()
	body_font.fallbacks = fallbacks
	var weight_tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	for role in [[display_font,900],[secondary_font,800]]:
		var face: FontVariation = role[0]
		face.base_font = localization.display_base_font(role[1])
		face.variation_opentype = {weight_tag: float(role[1])}
		var display_fallbacks: Array[Font] = []
		for fallback in fallbacks:
			if fallback.base_font != face.base_font:
				display_fallbacks.append(fallback)
		face.fallbacks = display_fallbacks
	language_font.base_font = BODY
	language_font.variation_opentype = body_font.variation_opentype
	language_font.fallbacks = localization.fallback_fonts(language_font_complete)

func ensure_multilingual_font() -> void:
	if not language_font_complete:
		language_font_complete = true
		language_font.fallbacks = localization.fallback_fonts(true)

func change_language(code: String, persist: bool = true) -> bool:
	if not localization.set_language(code):
		refresh_language(localization.active_code)
		toast("messages.languageFailed", 6)
		return false
	if persist:
		profile.settings.language = code
		if not profile.save():
			toast("messages.storageFailed", 7)
	return true

func refresh_language(_code: String) -> void:
	hud_cache.clear()
	configure_localized_fonts()
	layout_hud_text()
	refresh_translated_nodes(ui)
	refresh_hud()
	apply_ui_direction()
	if not toast_key.is_empty() and toast_time > 0:
		toast_label.text = localization.text(toast_key, toast_variables)
		fit_localized_text(toast_label, true)

func collect_ui_controls(parent: Node, controls: Array[Control]) -> void:
	for child in parent.get_children():
		if child is Control:
			if not child.has_meta("layout_position"):
				child.set_meta("layout_position", child.position)
			controls.append(child)
		collect_ui_controls(child, controls)

func apply_ui_direction() -> void:
	# The scene composition is fixed. Only text follows the selected language.
	var controls: Array[Control] = []
	collect_ui_controls(overlay, controls)
	collect_ui_controls(hud, controls)
	var rtl := localization.is_rtl()
	stage.layout_direction = Control.LAYOUT_DIRECTION_LTR
	overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	for node in controls:
		node.layout_direction = Control.LAYOUT_DIRECTION_LTR
		if node.has_meta("translation_key") and (node is Label or node is Button):
			node.text_direction = Control.TEXT_DIRECTION_RTL if rtl else Control.TEXT_DIRECTION_AUTO
		if node is Label:
			if not node.has_meta("layout_alignment"):
				node.set_meta("layout_alignment", node.horizontal_alignment)
			var alignment: int = node.get_meta("layout_alignment")
			# Keep each HUD heading attached to its value/bar; text still shapes RTL.
			var mirror_alignment := rtl and node.get_parent() != hud
			node.horizontal_alignment = (HORIZONTAL_ALIGNMENT_RIGHT if alignment == HORIZONTAL_ALIGNMENT_LEFT else HORIZONTAL_ALIGNMENT_LEFT) if mirror_alignment and alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT] else alignment
		elif node is Button:
			if not node.has_meta("layout_alignment"):
				node.set_meta("layout_alignment", node.alignment)
			var alignment: int = node.get_meta("layout_alignment")
			node.alignment = (HORIZONTAL_ALIGNMENT_RIGHT if alignment == HORIZONTAL_ALIGNMENT_LEFT else HORIZONTAL_ALIGNMENT_LEFT) if rtl and alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT] else alignment
	overlay.position = Vector2.ZERO
	hud.position = Vector2.ZERO
	for node in controls:
		node.position = node.get_meta("layout_position")

func refresh_translated_nodes(node: Node) -> void:
	if node.has_meta("translation_key"):
		node.text = localization.text(node.get_meta("translation_key"), node.get_meta("translation_variables", {}))
	if node.has_meta("tooltip_key"):
		node.tooltip_text = localization.text(node.get_meta("tooltip_key"))
		if node is Button and node.text.is_empty():
			node.accessibility_name = node.tooltip_text
	if node.has_meta("placeholder_key"):
		node.placeholder_text = localization.text(node.get_meta("placeholder_key"))
	if node.has_meta("credits_body"):
		node.text = licenses_text() if node.get_meta("credits_body") else credits_text()
	if node is OptionButton and node.name == "LanguageChoice":
		node.set_item_text(0, localization.text("settings.system"))
		for index in node.item_count:
			if node.get_item_metadata(index) == localization.preference:
				node.select(index)
	if node.has_meta("translation_font_size"):
		fit_localized_text(node, true)
	for child in node.get_children():
		refresh_translated_nodes(child)

func bind_text(node: Control, key: String, variables: Dictionary = {}) -> void:
	node.set_meta("translation_key", key)
	node.set_meta("translation_variables", variables.duplicate())
	node.text = localization.text(key, variables)
	fit_localized_text(node)

func fit_localized_text(node: Control, force: bool = false) -> void:
	if not node.has_meta("translation_font_size"):
		return
	if not force and node.has_meta("fitted_text") and node.get_meta("fitted_text") == node.text:
		return
	var requested: int = node.get_meta("translation_font_size")
	var font := node.get_theme_font("font")
	var dimensions: Vector2 = node.get_meta("translation_size", node.size)
	var icon_space := 0.0
	if node is Button and node.icon != null and node.expand_icon:
		icon_space = node.get_theme_constant("icon_max_width") + node.get_theme_constant("h_separation")
	var width := maxf(1, dimensions.x - (44 if node is BaseButton else 4) - icon_space - float(node.get_meta("extra_text_margin",0)))
	var height := maxf(1, dimensions.y - (16 if node is BaseButton else 2))
	var font_size := requested
	var measured := Vector2.ZERO
	while true:
		var paragraph := TextParagraph.new()
		if (node is Label or node is Button) and node.autowrap_mode != TextServer.AUTOWRAP_OFF:
			paragraph.width = width
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			if node.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
				paragraph.break_flags |= TextServer.BREAK_ADAPTIVE
		paragraph.add_string(node.text, font, font_size)
		measured = paragraph.get_size()
		# Wrapped labels need the font's native metrics for every visible line.
		var lines := maxi(1, paragraph.get_line_count())
		var spacing := node.get_theme_constant("line_spacing") if node is Label else 0
		measured.y = maxf(measured.y, font.get_height(font_size) * lines + spacing * (lines - 1))
		if (measured.x <= width and measured.y <= height) or font_size <= 10:
			break
		font_size -= 1
	node.add_theme_font_size_override("font_size", font_size)
	node.size = dimensions
	node.set_meta("fitted_text", node.text)
	node.set_meta("text_fits", measured.x <= width + 1 and measured.y <= height + 1)

func credits_text() -> String:
	var dedication := localization.text("credits.createdBy", {"author":"Andrjus Valkuns", "daughter":"Karolina Valkunaite"})
	return "%s %s\nExistical Games\nhttp://www.existical.com\n\n%s\n\n%s\n\n%s\n\n%s" % [ProjectSettings.get_setting("application/config/name"), ProjectSettings.get_setting("application/config/version"), dedication, localization.text("credits.description"), FileAccess.get_file_as_string("res://assets/licenses/SOUND_CREDITS.txt").strip_edges(), FileAccess.get_file_as_string("res://assets/licenses/MUSIC_CREDITS.txt")]

func licenses_text() -> String:
	# Keep each upstream copyright and licence intact, accessible offline.
	var text := "Big Snow Shift — code licence\n\n" + FileAccess.get_file_as_string("res://assets/licenses/GAME_LICENSE.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/licenses/ASSET_LICENSES.txt") + "\n\nGodot Engine\n\n" + Engine.get_license_text()
	for path in ["res://assets/licenses/THIRD_PARTY_NOTICES.txt", "res://assets/fonts/Nunito-LICENSE.txt", "res://assets/fonts/MPLUSRounded1c-LICENSE.txt", "res://assets/licenses/CC-BY-4.0.txt", "res://assets/licenses/CC0-1.0.txt"]:
		text += "\n\n" + FileAccess.get_file_as_string(path)
	for name in GameLocalization.FONT_NAMES:
		text += "\n\n" + FileAccess.get_file_as_string("res://assets/fonts/" + name + "-LICENSE.txt")
	return text

func _exit_tree() -> void:
	profile.shutdown()
	localization.dispose()

func store_run(wait: bool = false) -> void:
	if quitting:
		return
	if active_run and model.state in ["won","lost"]:
		if model.state == "won": profile.record_victory(model)
		active_run = false
		profile.active_run = {}
		# Flush after the clear so an earlier queued autosave cannot restore it.
		wait = true
	if qa_mode: return
	if active_run and model.run_id not in profile.submitted:
		profile.active_run = model.snapshot()
		if OS.is_debug_build():
			print("BIG_SNOW_SHIFT_RUN ", JSON.stringify({"view": view, "state": model.state, "remaining": model.snow.remaining, "initial": model.snow.initial, "time": model.time_left, "player": [model.player.x, model.player.y], "stun":model.stun,"hit_duration":model.hit_duration,"id": model.run_id,"control_mode":profile.settings.control_mode,"pointer_held":steering.held(),"pad_visible":pad.visible,"music_id":sound.track_id(),"music_context":sound.context,"music_paused":sound.paused or sound.suspended}))
	if not profile.save_async() or (wait and not profile.flush_pending()):
		warn_storage_failure()
	elif wait:
		last_storage_warning = false
	if wait and view == "pause": update_pause_status()

func warn_storage_failure() -> void:
	if not last_storage_warning:
		last_storage_warning = true
		toast("messages.storageFailed", 7)

func toast(message: String, duration: float = 3.0, variables: Dictionary = {}) -> void:
	toast_key = message
	toast_variables = variables.duplicate()
	toast_label.text = localization.text(message, variables)
	fit_localized_text(toast_label)
	toast_time = duration

func on_hit() -> void:
	release_controls()
	update_controls()
	sound.play("hit")
	world.player_hit()
	toast("messages.hit", 3)

func on_round_completed(last: bool) -> void:
	if last:
		sound.play_outcome("win")
	else:
		sound.play("chime")
	world.celebrate()

func on_snow_cleared(amount: int) -> void:
	world.shovel_burst(amount)
	if shovel_audio_timer <= 0:
		sound.play("shovel")
		shovel_audio_timer = 0.38

func capture() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(capture_path)
	print("BIG_SNOW_SHIFT_CAPTURE result=%s path=%s" % [result, capture_path])
	quit_game(0 if result == OK else 1)
