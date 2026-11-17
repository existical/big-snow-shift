class_name TouchOptionButton
extends OptionButton
## Godot 4.7 PopupMenu activates the hovered row on mouse release even after
## a touchscreen scroll. Defer touch selections until the native contact ends;
## retain mouse, keyboard and accessibility behavior.

signal choice_selected(index: int)
signal back_dismissed

const DRAG_THRESHOLD := 12.0
var finger := -1
var origin := Vector2.ZERO
var dragged := false
var original_selection := -1
var pending_selection := -1
var hide_items := true
var hide_checks := true
var list_scroll: ScrollContainer
var scroll_origin := 0
var body_gesture := false

func _ready() -> void:
	item_selected.connect(_on_item_selected)
	get_popup().window_input.connect(_on_popup_input)
	get_popup().popup_hide.connect(_reset_gesture)
	list_scroll = _find_scroll(get_popup())

func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children(true):
		var found := _find_scroll(child)
		if found:
			return found
	return null

func _on_item_selected(index: int) -> void:
	if finger < 0:
		choice_selected.emit(index)
	else:
		pending_selection = index
		# OptionButton updates its check marks before emitting item_selected.
		select(original_selection)

func _on_popup_input(event: InputEvent) -> void:
	var popup := get_popup()
	if event.is_action_pressed("ui_cancel"):
		# Android may also send the root window a Back notification. Mark this
		# dismissal so the same action cannot close the settings underneath.
		back_dismissed.emit()
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and finger < 0 and popup.visible:
			finger = event.index
			origin = event.position
			dragged = false
			original_selection = selected
			pending_selection = -1
			body_gesture = false
			if list_scroll:
				scroll_origin = list_scroll.scroll_vertical
				var at: Vector2 = event.position / popup.content_scale_factor
				var bar := list_scroll.get_v_scroll_bar()
				body_gesture = list_scroll.get_global_rect().has_point(at) and not bar.get_global_rect().has_point(at)
			hide_items = popup.hide_on_item_selection
			hide_checks = popup.hide_on_checkable_item_selection
			popup.hide_on_item_selection = false
			popup.hide_on_checkable_item_selection = false
		elif event.index == finger and (not event.pressed or event.canceled):
			dragged = dragged or event.position.distance_to(origin) / popup.content_scale_factor > DRAG_THRESHOLD
			var commit := pending_selection if not dragged and not event.canceled else -1
			var same_item: bool = body_gesture and not dragged and not event.canceled and popup.get_focused_item() == original_selection
			_reset_gesture()
			if commit >= 0:
				select(commit)
				popup.hide()
				choice_selected.emit(commit)
			elif same_item:
				popup.hide()
	elif event is InputEventScreenDrag and event.index == finger:
		# Window events use window pixels, unlike the popup's scaled contents.
		if event.position.distance_to(origin) / popup.content_scale_factor > DRAG_THRESHOLD:
			dragged = true
		if dragged and body_gesture:
			list_scroll.scroll_vertical = scroll_origin + roundi((origin.y - event.position.y) / popup.content_scale_factor)

func _reset_gesture() -> void:
	if finger >= 0:
		get_popup().hide_on_item_selection = hide_items
		get_popup().hide_on_checkable_item_selection = hide_checks
	finger = -1
	dragged = false
	pending_selection = -1

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		get_popup().hide()
		_reset_gesture()
