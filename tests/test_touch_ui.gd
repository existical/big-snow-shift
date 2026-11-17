extends SceneTree
## Native regression checks pass real touch events through Input, including
## generated mouse events. Viewport.push_input alone bypasses that conversion.
var game: Control
var checks := 0
var failures: Array[String] = []
var previous := Vector2.ZERO
const TEST_MOUSE_DEVICE := 100

class NativeMouseGuard:
	extends Node
	func _input(event: InputEvent) -> void:
		# Keep real touch-to-mouse conversion (-1), plus deliberately injected
		# desktop events. Host pointer motion must not hijack synthetic drags.
		if event is InputEventMouse and event.device != -1 and event.device != TEST_MOUSE_DEVICE:
			get_viewport().set_input_as_handled()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func finger(at: Vector2, down: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = down
	event.index = index
	event.window_id = root.get_window_id()
	previous = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func motion(at: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = at
	event.relative = at - previous
	event.index = index
	event.window_id = root.get_window_id()
	previous = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(at: Vector2) -> void:
	finger(at,true)
	finger(at,false)

func swipe(start: Vector2, end: Vector2) -> void:
	finger(start,true)
	for i in 12:
		motion(start.lerp(end,(i+1)/12.0))
		await create_timer(.02).timeout
	finger(end,false)
	await process_frame

func internal_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer: return node
	for child in node.get_children(true):
		var found := internal_scroll(child)
		if found: return found
	return null

func write_report(filename: String, contents: Variant) -> void:
	var file := FileAccess.open("res://builds/touch-review/"+filename,FileAccess.WRITE)
	if file == null:
		check(false,"Cannot open touch test report "+filename+": "+error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(contents,"\t"))

func run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/touch-review")) != OK:
		printerr("FAIL: Cannot create builds/touch-review")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: touch GUI checks require the graphical renderer")
		quit(1)
		return
	root.gui_embed_subwindows = true
	Input.emulate_touch_from_mouse = false
	check(Input.emulate_mouse_from_touch, "touch-to-mouse compatibility is enabled for built-in GUI controls")
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = "res://builds/touch-review/unused-native-profile.json"
	root.add_child(game)
	root.add_child(NativeMouseGuard.new())
	game.set_physics_process(false)
	game.sound.set_suspended(true)
	game.change_language("en",false)
	game.start_night()
	game.show_settings("pause")
	await process_frame
	var music: HSlider = game.overlay.find_child("MusicVolume",true,false)
	check(music.size.y >= 84 and game.pause_button.size.x >= 84 and game.pause_button.size.y >= 84,"phone slider and pause targets reach 48 dp at 420 dpi")
	var slider_trace: Array = []
	music.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouse:
			slider_trace.append({"event":str(event),"device":event.device,"value":music.value})
	)
	var origin := music.global_position
	await swipe(origin+music.size*Vector2(.1,.5),origin+music.size*Vector2(.9,.5))
	check(game.profile.settings.music > .8, "a real touch drag moves the music slider")
	await swipe(origin+music.size*Vector2(.9,.5),origin+music.size*Vector2(.1,.5))
	write_report("slider-events.json",{"events":slider_trace,"origin":str(origin),"window":str(root.size),"transform":str(root.get_final_transform())})
	check(game.profile.settings.music < .2, "slider touch drags work in both directions")
	var choice: Button = game.overlay.find_child("ControlPad",true,false)
	var calls := [0]
	choice.pressed.connect(func(): calls[0] += 1)
	tap(choice.global_position + Vector2(40,choice.size.y*.5))
	check(calls[0] == 1 and game.profile.settings.control_mode == "pad", "a touch on the button icon activates its radio option exactly once")
	var current: int = calls[0]
	finger(choice.global_position+choice.size*.5,true)
	motion(Vector2(20,20))
	finger(Vector2(20,20),false)
	check(calls[0] == current, "dragging outside a button cancels its activation")
	var privacy_button: Button = game.overlay.find_child("PrivacyButton",true,false)
	tap(privacy_button.global_position + privacy_button.size * .5)
	Input.emulate_touch_from_mouse = true
	await process_frame
	check(game.view == "privacy" and game.model.paused, "Privacy button opens offline policy without resuming gameplay")
	var privacy: RichTextLabel = game.overlay.find_child("PrivacyText",true,false)
	check(privacy.text.contains("existicalgames[at]gmail[dot]com") and privacy.text.contains("https://www.existical.com/privacy/big-snow-shift/"), "offline policy includes the published URL and obfuscated contact")
	var policy_start := privacy.global_position + Vector2(350,300)
	await swipe(policy_start,policy_start-Vector2(0,220))
	check(privacy.get_v_scroll_bar().value > 100, "privacy text scrolls by touch")
	game.handle_back_request()
	check(game.view == "settings" and game.settings_return == "pause" and game.model.paused, "privacy Back returns to the correct paused Settings context")
	game.show_credits()
	# Only the desktop credits test needs this touchscreen-availability hint.
	# Keep actual mouse input separate from injected fingers elsewhere.
	Input.emulate_touch_from_mouse = true
	check(DisplayServer.is_touchscreen_available(), "desktop native touch hint is active for scrolling")
	await process_frame
	var credits: RichTextLabel = game.overlay.find_child("CreditsText",true,false)
	var bar := credits.get_v_scroll_bar()
	var start := credits.global_position + Vector2(350,300)
	await swipe(start,start-Vector2(0,220))
	check(bar.value > 100, "credits text scrolls by dragging its body")
	tap(credits.global_position+Vector2(100,100)) # Stop inertia before reverse.
	var scrolled := bar.value
	await swipe(start-Vector2(0,220),start)
	check(bar.value < scrolled, "credits can be scrolled back upwards")
	var licence_button: Button = game.overlay.find_child("LicensesButton",true,false)
	tap(licence_button.global_position + licence_button.size * .5)
	await process_frame
	check(game.view == "licenses" and game.model.paused, "touch opens licences without resuming the game")
	var legal: RichTextLabel = game.overlay.find_child("CreditsText",true,false)
	start = legal.global_position + Vector2(350,300)
	await swipe(start,start-Vector2(0,220))
	check(legal.get_v_scroll_bar().value > 100, "full licence notices scroll with touch")
	game.handle_back_request()
	check(game.view == "credits", "Back from licences returns to acknowledgements")
	game.show_settings("pause")
	Input.emulate_touch_from_mouse = false
	await process_frame
	var language: OptionButton = game.overlay.find_child("LanguageChoice",true,false)
	tap(language.global_position+language.size*.5)
	await process_frame
	var popup := language.get_popup()
	var scroll := internal_scroll(popup)
	check(popup.visible and scroll != null, "language dropdown opens with touch")
	var selection: String = game.localization.preference
	var position := Vector2(popup.position)
	await swipe(position+Vector2(150,400),position+Vector2(150,70))
	check(scroll.scroll_vertical > 50 and popup.visible, "language list swipes scroll without closing it")
	check(game.localization.preference == selection, "a language swipe does not select an item")
	var down_scroll := scroll.scroll_vertical
	await swipe(position+Vector2(150,70),position+Vector2(150,350))
	check(scroll.scroll_vertical < down_scroll and popup.visible, "language swipes scroll in both directions")
	for i in 6:
		await swipe(position+Vector2(150,420),position+Vector2(150,70))
	var vbar := scroll.get_v_scroll_bar()
	check(vbar.value >= vbar.max_value-vbar.page-2, "all languages at the end of the list are reachable")
	check(game.localization.preference == selection, "repeated language swipes leave the selected locale unchanged")
	popup.hide()
	await process_frame
	tap(language.global_position+language.size*.5)
	await process_frame
	scroll.scroll_vertical = 0
	await process_frame
	await create_timer(.45).timeout
	position = Vector2(popup.position)
	# Choose a different row after scrolling; a tap must still commit exactly once.
	var chosen := [0]
	language.choice_selected.connect(func(_index): chosen[0] += 1)
	tap(position+Vector2(150,90))
	check(not popup.visible and chosen[0] == 1 and game.localization.preference != selection, "a language tap after swiping commits once and closes the list")
	await process_frame
	tap(language.global_position+language.size*.5)
	await process_frame
	await create_timer(.45).timeout
	tap(Vector2(popup.position)+Vector2(150,90))
	check(not popup.visible and chosen[0] == 1, "tapping the currently selected language closes the list without applying it twice")
	await process_frame
	tap(language.global_position+language.size*.5)
	await process_frame
	var selected_position := Vector2(popup.position)+Vector2(150,145)
	# Cancellation must not commit the hovered row.
	finger(selected_position,true)
	var canceled := InputEventScreenTouch.new()
	canceled.position = selected_position
	canceled.index = 0
	canceled.canceled = true
	canceled.window_id = root.get_window_id()
	Input.parse_input_event(canceled)
	Input.flush_buffered_events()
	check(chosen[0] == 1 and language.finger == -1, "a cancelled dropdown touch does not select a language")
	# Desktop wheel scrolling remains available on the same dropdown.
	var before_wheel := scroll.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.device = TEST_MOUSE_DEVICE
	wheel.position = Vector2(popup.position)+Vector2(150,220)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.emulate_touch_from_mouse = false
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	check(scroll.scroll_vertical > before_wheel, "desktop mouse wheel still scrolls languages")
	var navigation := InputEventKey.new()
	navigation.pressed = true
	navigation.keycode = KEY_DOWN
	navigation.physical_keycode = KEY_DOWN
	Input.parse_input_event(navigation)
	Input.flush_buffered_events()
	var release_down := InputEventKey.new()
	release_down.keycode = KEY_DOWN
	release_down.physical_keycode = KEY_DOWN
	Input.parse_input_event(release_down)
	var accept := InputEventKey.new()
	accept.pressed = true
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	Input.parse_input_event(accept)
	var release_accept := InputEventKey.new()
	release_accept.keycode = KEY_ENTER
	release_accept.physical_keycode = KEY_ENTER
	Input.parse_input_event(release_accept)
	Input.flush_buffered_events()
	check(chosen[0] == 2 and not popup.visible, "keyboard navigation still selects and closes the language dropdown")
	popup.hide()
	await process_frame
	tap(language.global_position+language.size*.5)
	await process_frame
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	var escape_up := InputEventKey.new()
	escape_up.keycode = KEY_ESCAPE
	escape_up.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(escape_up)
	Input.flush_buffered_events()
	await process_frame
	game.handle_back_request()
	check(not popup.visible and game.view == "settings", "dropdown Escape plus Android Back notification leaves settings open")
	game.profile.settings.control_mode = "screen"
	game.resume_game()
	game.model.stun = 0
	var anchor: Vector2 = game.control_anchor()
	finger(anchor+Vector2(150,0),true)
	check(game.steering.finger == 0 and not game.steering.mouse_held, "screen movement is owned by native touch only")
	motion(anchor+Vector2(-150,0))
	check(game.movement_input() == Vector2.LEFT, "screen steering turns during a touch drag")
	finger(anchor+Vector2(-150,0),false)
	check(game.movement_input() == Vector2.ZERO, "screen movement stops on touch release with emulation enabled")
	await check_pause_toggle()
	game.profile.settings.control_mode = "pad"
	game.apply_settings()
	var pad_at: Vector2 = game.pad.global_position + Vector2(83,25)
	finger(pad_at,true)
	check(game.pad.finger == 0 and not game.pad.mouse_held and game.pad.direction.y < -.9, "pad movement is owned by native touch only")
	finger(pad_at+Vector2(50,50),true,1)
	check(game.pad.finger == 0, "a second finger cannot steal the control pad")
	finger(pad_at+Vector2(50,50),false,1)
	check(game.pad.finger == 0, "a second finger release does not stop the owner")
	finger(pad_at,false)
	check(game.pad.direction == Vector2.ZERO and not game.pad.mouse_held, "pad release is not held by an emulated mouse")
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.pressed = true
	cancel.position = pad_at
	game.pad._input(cancel)
	cancel.canceled = true
	game.pad._input(cancel)
	check(game.pad.direction == Vector2.ZERO and game.pad.finger == -1, "cancelled pad touches release ownership")
	game.pad.mouse_held = true
	game.pad.direction = Vector2.UP
	var missed_release := InputEventMouseMotion.new()
	game.pad._input(missed_release)
	check(not game.pad.mouse_held and game.pad.direction == Vector2.ZERO, "pad releases if a mouse motion no longer has a held button")
	game.pad.mouse_held = true
	game.pad.direction = Vector2.UP
	game._notification(Control.NOTIFICATION_WM_MOUSE_EXIT)
	check(not game.pad.mouse_held and game.pad.direction == Vector2.ZERO, "leaving the window releases a mouse-held pad")
	game.show_result()
	game.model.state = "won"
	game.show_result()
	check(not game.pause_button.visible, "result screens do not expose a resume shortcut")
	game.toggle_pause()
	check(game.view == "result" and game.model.paused, "pause shortcut cannot bypass the results")
	await process_frame
	var field: LineEdit = game.name_edit
	tap(field.global_position+field.size*.5)
	check(field.has_focus(), "touch focuses the score-name input")
	var key := InputEventKey.new()
	key.pressed = true
	key.unicode = 90
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check("Z" in field.text, "focused name input accepts text after a touch")
	Input.emulate_touch_from_mouse = false
	await check_difficulty_controls()
	game.sound.shutdown()
	await create_timer(.15).timeout
	game.free()
	var result := {"touch_ui_checks":checks,"failures":failures}
	write_report("native-tests.json",result)
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func check_pause_toggle() -> void:
	await process_frame
	var corner: Vector2 = game.pause_button.global_position + game.pause_button.size * .5
	var calls := [0]
	game.pause_button.pressed.connect(func(): calls[0] += 1)
	# A second finger can pause while the first finger is still steering.
	var movement: Vector2 = game.control_anchor() + Vector2(150,0)
	finger(movement,true)
	finger(corner,true,1)
	finger(corner,false,1)
	check(calls[0] == 1 and game.view == "pause" and game.model.paused, "corner touch pauses once while a movement finger is held")
	check(not game.steering.held() and game.movement_input() == Vector2.ZERO, "pausing releases the held movement input")
	finger(movement,false)
	var time_left: float = game.model.time_left
	var position: Vector2 = game.model.player
	game._physics_process(.25)
	check(game.model.time_left == time_left and game.model.player == position, "corner pause freezes both the clock and character")
	check(game.pause_button.icon == game.RESUME_ICON and game.pause_button.tooltip_text == game.localization.text(game.resume_caption()), "paused corner shows play with the localized resume action")
	await process_frame
	tap(corner)
	check(calls[0] == 2 and game.view == "playing" and not game.model.paused, "tapping the paused corner resumes exactly once")
	check(game.pause_button.icon == game.PAUSE_ICON and not game.steering.held(), "resume restores pause icon without restarting held movement")
	game._physics_process(.25)
	check(game.model.time_left < time_left and game.model.player == position, "resumed clock advances while the character stays still")
	# Desktop mouse follows the same GUI path; dragging away cancels activation.
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.device = TEST_MOUSE_DEVICE
		event.position = corner
		event.window_id = root.get_window_id()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	check(calls[0] == 3 and game.view == "pause", "desktop click pauses through the same corner button")
	await process_frame
	finger(corner,true)
	motion(Vector2(20,200))
	finger(Vector2(20,200),false)
	check(calls[0] == 3 and game.view == "pause", "dragging off the resume button leaves the game paused")
	tap(corner)
	check(calls[0] == 4 and game.view == "playing", "resume remains usable after a cancelled tap")
	game.show_settings("pause")
	check(not game.pause_button.visible and game.pause_button.disabled, "settings hides and disables the corner shortcut")
	game.toggle_pause()
	check(game.view == "settings" and game.model.paused, "pause shortcut cannot dismiss settings")
	game.close_settings()
	check(game.view == "pause" and game.pause_button.visible, "closing settings restores the paused resume button")
	game.resume_game()

func check_difficulty_controls() -> void:
	game.profile.active_run = {}
	game.profile.settings.difficulty = "easy"
	game.profile.settings.game_mode = "standard"
	game.profile.settings.custom_parameters = DifficultyRules.custom_defaults()
	game.profile.settings.custom_assists = {"no_time_limit":false,"no_icicles":false}
	game.profile.last_submitted_id = ""
	game.show_scores()
	game.show_difficulty()
	check(game.view == "scores","Scores cannot enter new-game setup directly")
	game.show_menu()
	await process_frame
	var play: Button
	for child in game.overlay.get_children():
		for node in child.get_children():
			if node is Button and node.get_meta("translation_key","") == "menu.play": play = node
	tap(play.global_position+play.size*.5)
	check(game.view == "difficulty" and game.selected_difficulty == "easy","Play opens difficulty cards with Easy selected")
	check(game.overlay.find_child("Assist_no_icicles",true,false) == null and game.overlay.find_child("Assist_no_time_limit",true,false) == null,"fixed difficulty screen has no help switches")
	await process_frame
	var hard: Button = game.overlay.find_child("Difficulty_hard",true,false)
	tap(hard.global_position+Vector2(135,100))
	check(game.view == "difficulty" and game.selected_difficulty == "hard" and hard.button_pressed,"touching a portrait selects its card without starting")
	check(hard.get_node("Selected").visible,"selection has a check mark as well as color")
	var start: Button = game.overlay.find_child("DifficultyStart",true,false)
	tap(start.global_position+start.size*.5)
	check(game.view == "playing" and game.model.difficulty_id == "hard" and game.model.time_left == 420,"Start begins the selected mode")
	check(not game.steering.held(),"starting a run does not carry the menu touch into movement")
	game.profile.active_run = game.model.snapshot()
	var old_id: String = game.model.run_id
	game.show_menu()
	game.show_difficulty()
	game.select_difficulty("extreme")
	game.commit_difficulty()
	check(game.view == "confirm" and game.profile.active_run.id == old_id,"old save survives selection until replacement confirmation")
	game.last_back_request = -1000
	game.handle_back_request()
	check(game.view == "difficulty" and game.selected_difficulty == "extreme","Back from replacement confirmation returns to the selected card")
	game.close_difficulty()
	check(game.view == "menu" and game.profile.active_run.id == old_id,"cancel preserves old run")
	game.continue_night()
	check(game.view == "pause" and game.model.difficulty_id == "hard","Continue bypasses selection and restores its own mode")
	game.model.time_left = 100
	game.show_menu()
	game.show_difficulty()
	await process_frame
	var custom_button: Button = game.overlay.find_child("CustomGame",true,false)
	tap(custom_button.global_position+Vector2(40,38))
	check(game.selected_game_mode == "custom" and game.overlay.find_child("CustomGamePanel",true,false) != null,"Custom gear icon opens its own screen")
	await process_frame
	check(game.overlay.find_child("Difficulty_easy",true,false) == null and game.custom_rows.is_empty(),"Custom overview shows the basic choices")
	for count in [1,2,3]:
		var round_choice: Button = game.overlay.find_child("CustomRounds_"+str(count),true,false)
		tap(round_choice.global_position+round_choice.size*.5)
		check(game.selected_round_count == count and round_choice.button_pressed,"touch selects Custom length "+str(count))
		for other in [1,2,3]:
			check((game.overlay.find_child("CustomRounds_"+str(other),true,false) as Button).button_pressed == (count == other),"round choices remain mutually exclusive")
	var CustomMore: Button = game.overlay.find_child("CustomMore",true,false)
	tap(CustomMore.global_position+CustomMore.size*.5)
	await process_frame
	check(game.custom_rows.size() == 8,"Advanced page exposes eight settings")
	for field in CustomRules.FIELDS:
		var parameter: String = field[0]
		var previous_value: float = game.selected_custom_parameters[parameter]
		var controls: Dictionary = game.custom_rows[parameter]
		check(controls.increase.size.x >= 84 and controls.increase.size.y >= 84 and not controls.increase.get_rect().intersects(controls.decrease.get_rect()),"separate 48 dp stepper targets for "+parameter)
		tap(controls.increase.global_position+Vector2(30,30))
		check(game.selected_custom_parameters[parameter] > previous_value,"touch increases "+parameter)
		tap(controls.decrease.global_position+Vector2(30,30))
		check(is_equal_approx(game.selected_custom_parameters[parameter],previous_value),"touch decreases "+parameter)
	var extra: Button = game.custom_rows.extra_seconds.increase
	tap(extra.global_position+Vector2(30,30))
	var CustomOverview: Button = game.overlay.find_child("CustomOverview",true,false)
	tap(CustomOverview.global_position+CustomOverview.size*.5)
	await process_frame
	var warnings: Button = game.overlay.find_child("Assist_landing_warnings",true,false)
	check(warnings.button_pressed and not warnings.disabled,"Custom landing warnings default on")
	tap(warnings.global_position+Vector2(40,30))
	check(not game.selected_custom_parameters.landing_warnings,"touch turns landing warnings off")
	var no_ice: Button = game.overlay.find_child("Assist_no_icicles",true,false)
	tap(no_ice.global_position+Vector2(40,30))
	check(game.selected_assists.no_icicles,"assist toggles through its icon with touch")
	check(warnings.disabled and not warnings.button_pressed,"No icicles disables warnings without erasing the selection")
	tap(no_ice.global_position+Vector2(40,30))
	check(not warnings.disabled and not warnings.button_pressed,"re-enabling icicles restores the warning selection")
	tap(no_ice.global_position+Vector2(40,30))
	game.change_custom_page(true)
	check(game.custom_rows.interval_multiplier.increase.disabled and game.custom_rows.recovery_multiplier.decrease.disabled and not game.custom_rows.extra_seconds.increase.disabled,"No icicles disables related controls while retaining the timer controls")
	game.difficulty_back()
	game.commit_difficulty()
	check(game.view == "confirm" and game.model.run_id == old_id,"Custom settings cannot replace the old game until confirmed")
	game.start_night()
	check(not game.model.landing_warnings and not game.profile.settings.custom_parameters.landing_warnings,"starting the new Custom game persists hidden landing warnings")
	check(game.model.game_mode == "custom" and game.model.custom_parameters.extra_seconds == 150 and game.model.time_left == 570 and game.model.assists.no_icicles and game.model.score_category() == "personal","new Custom game starts at round one with its selected parameters")
	check(game.mode_text() == game.localization.text("custom.title"),"Custom caption contains no preset difficulty")
	game.profile.active_run = game.model.snapshot()
	game.show_menu()
	game.show_difficulty()
	await process_frame
	game.change_custom_page(true)
	var more_time: Button = game.custom_rows.extra_seconds.increase
	more_time.grab_focus()
	for down in [true,false]:
		var key := InputEventKey.new()
		key.pressed = down
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		Input.parse_input_event(key)
		Input.flush_buffered_events()
	check(game.selected_custom_parameters.extra_seconds == 180,"keyboard can change Custom parameters")
	var saved_custom: Dictionary = game.model.snapshot()
	game.difficulty_back()
	game.last_back_request = -1000
	game.handle_back_request()
	check(game.selected_game_mode == "standard" and game.overlay.find_child("Assist_no_icicles",true,false) == null,"Android Back from Custom returns to fixed presets")
	check(game.model.snapshot() == saved_custom,"Back does not apply an unfinished Custom edit")
	game.select_difficulty("hard")
	game.commit_difficulty()
	check(game.view == "confirm" and game.model.snapshot() == saved_custom,"new preset selection waits for replacement confirmation")
	game.start_night()
	check(game.model.game_mode == "standard" and not game.model.assists.no_icicles and not game.model.assists.no_time_limit and game.model.score_category() == "standard","starting a new preset clears switches and has its own leaderboard eligibility")
	check(game.profile.settings.custom_assists.no_icicles and game.profile.settings.custom_parameters.extra_seconds == 150,"preset selection retains independent Custom parameters")
	game.model.adjusted_run = true
	game.model.legacy_run = true
	check(game.mode_text() == game.localization.text("difficulty.hard"),"an adjusted pre-difficulty save displays the newly chosen preset")
	game.model.legacy_run = false
	game.model.adjusted_run = false
	game.show_menu()
	game.show_difficulty()
	game.open_custom_game()
	await process_frame
	var reset: Button = game.overlay.find_child("CustomReset",true,false)
	game.selected_round_count = 1
	tap(reset.global_position+Vector2(40,30))
	check(game.selected_round_count == 3 and (game.overlay.find_child("CustomRounds_3",true,false) as Button).button_pressed,"Reset returns to three rounds")
	check(game.selected_custom_parameters.extra_seconds == 120 and not game.selected_assists.no_icicles,"Reset restores numeric defaults and switches in the draft")
	check(game.selected_custom_parameters.landing_warnings and not game.profile.settings.custom_parameters.landing_warnings,"Reset restores warnings only in the draft")
	check(game.profile.settings.custom_parameters.extra_seconds == 150,"Reset does not save or apply until confirmed")
	game.close_difficulty()
	game.profile.scores = []
	for i in 30:
		game.profile.scores.append({"name":"Family "+str(i),"score":10000-i,"category":"personal","difficulty":"hard","balance":"old"})
	game.show_scores("easy")
	await process_frame
	var tab: Button = game.overlay.find_child("Scores_extreme",true,false)
	tap(tab.global_position+Vector2(40,32))
	check(game.scores_tab == "extreme" and game.overlay.find_child("Scores_extreme",true,false).has_focus(),"touching a score-tab icon changes difficulty")
	game.show_scores("personal")
	Input.emulate_touch_from_mouse = true
	await process_frame
	var scroll: ScrollContainer = game.overlay.find_child("ScoreScroll",true,false)
	var from := scroll.global_position+Vector2(360,250)
	await swipe(from,from-Vector2(0,190))
	check(scroll.scroll_vertical > 80,"My results lists scroll with a finger")
	Input.emulate_touch_from_mouse = false
