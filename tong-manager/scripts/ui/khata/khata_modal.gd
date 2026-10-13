class_name KhataModal
extends Control

signal opened
signal closed
signal page_selected(index: int)

const ShellPage := preload("res://scripts/ui/khata/khata_shell_page.gd")
const PAGE_NAMES := ["InventoryPage", "RecipesPage", "FinancePage", "QuestsPage"]
const TAB_NAMES := ["InventoryTab", "RecipesTab", "FinanceTab", "QuestsTab"]
const TAB_COLORS := [Color("91a878"), Color("bd916b"), Color("7994a1"), Color("ac94ab")]

@export_node_path("Control") var peek_path: NodePath
@onready var peek: KhataPeek = get_node_or_null(peek_path) as KhataPeek if not peek_path.is_empty() else null
@onready var book: KhataBook = $NotebookBackground/Book
@onready var dimmer: ColorRect = $Dimmer
@onready var book_input: Control = $BookInput
@onready var export_layer: Node2D = $DragExportLayer
@onready var animation: AnimationPlayer = $AnimationPlayer
var controller: InteractionController
var exporting := false
var page_index: int:
	get:
		return book.spread if is_instance_valid(book) else 0
var _active := false
var _closing := false
var _peek_after_close := false


func _enter_tree() -> void:
	# Child page viewports are created before this Control's _ready callback.
	get_node("NotebookBackground/Book").page_factory = _make_page


func _ready() -> void:
	book.opened_changed.connect(_on_book_opened_changed)
	book.page_changed.connect(_on_page_changed)
	book.close_requested.connect(close)
	book_input.gui_input.connect(_on_book_input)
	dimmer.gui_input.connect(_on_dimmer_input)
	$CloseButton.pressed.connect(close)
	$PeekButton.pressed.connect(open_peek)
	if is_instance_valid(peek):
		peek.open_requested.connect(open)
		peek.close_requested.connect(close_peek)
	$PreviousButton.pressed.connect(func(): book.request_turn(-1))
	$NextButton.pressed.connect(func(): book.request_turn(1))
	for index in range(4):
		var button := $TabContainer.get_node(TAB_NAMES[index]) as Button
		button.pressed.connect(select_page.bind(index))
		_style_button(button, TAB_COLORS[index], true)
	_style_button($CloseButton, Color("353f34"))
	_style_button($PeekButton, Color("353f34"))
	for button in [$PreviousButton, $NextButton]:
		_style_button(button, Color(0.17, 0.22, 0.17, 0.85))
	get_viewport().size_changed.connect(_on_resize)
	visibility_changed.connect(_on_visibility_changed)
	_on_page_changed(0)
	_layout()


func configure(value: InteractionController) -> void:
	if controller == value:
		return
	close_peek()
	if _active:
		# The old controller owns any reservation and modal lock. Finish that
		# session before binding another controller, without transferring input.
		hide()
	if is_instance_valid(controller):
		_release_ownership()
		for pair in [[controller.mode_changed, _on_mode_changed], [controller.drag_canceled, _on_drag_canceled], [controller.drag_dropped, _on_drag_dropped]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	controller = value
	if is_instance_valid(controller):
		controller.mode_changed.connect(_on_mode_changed)
		controller.drag_canceled.connect(_on_drag_canceled)
		controller.drag_dropped.connect(_on_drag_dropped)


func open() -> bool:
	if _active or _closing or not is_inside_tree() or is_queued_for_deletion() or not _host_is_visible() or not _controller_is_live() or controller.is_world_input_blocked():
		return false
	close_peek()
	_active = true
	_closing = false
	show()
	# Establish ownership before cancellation emits callbacks into world objects.
	controller.set_world_input_blocked(self, true)
	if not _active or _closing or is_queued_for_deletion():
		return false
	_reading_visible(true)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	animation.play("reveal")
	book.open_book()
	opened.emit()
	return true


func is_open() -> bool:
	return _active


func is_peeking() -> bool:
	return is_instance_valid(peek) and peek.is_visible_in_tree()


func open_peek() -> bool:
	if (_closing or not is_inside_tree() or is_queued_for_deletion()
		or not _host_is_visible() or not _controller_is_live() or not is_instance_valid(peek)
		or not peek.is_inside_tree() or peek.is_queued_for_deletion()):
		return false
	var peek_host := peek.get_parent() as CanvasItem
	if peek_host != null and not peek_host.is_visible_in_tree():
		return false
	if _active:
		_peek_after_close = true
		_start_close()
		return true
	if controller.is_world_input_blocked():
		return false
	if not is_peeking():
		peek.reveal()
	return true


func close_peek() -> void:
	_peek_after_close = false
	if is_instance_valid(peek):
		peek.dismiss()


func close() -> void:
	close_peek()
	_start_close()


func _start_close() -> void:
	if not _active:
		return
	_closing = true
	cancel_export()
	if not book.opened and not book.busy:
		_finish_close()
	else:
		book.close_book()


func select_page(index: int) -> void:
	if _active and not _closing and not exporting and index >= 0 and index < 4:
		book.select_page(index)


func begin_export(payload: HeldItemPayload, visual: Node2D, point: Vector2, allowed_targets: Array[DropZone]) -> bool:
	if not _active or _closing or exporting or book.busy or not book.opened or not _controller_is_live():
		return false
	exporting = true
	_reading_visible(false)
	var ignored_ui: Array[Control] = [dimmer]
	var accepted := controller.begin_modal_export(self, payload, visual, point, export_layer, allowed_targets, ignored_ui)
	if not accepted or not controller.is_modal_export_active(self):
		_export_finished()
		return false
	return true


func cancel_export() -> void:
	if is_instance_valid(controller):
		controller.end_modal_export(self)
	_export_finished()


func _export_finished() -> void:
	exporting = false
	if is_node_ready():
		_reading_visible(true)


func _reading_visible(value: bool) -> void:
	$NotebookBackground.visible = value
	book_input.visible = value
	$TabContainer.visible = value
	$Pages.visible = value
	$PreviousButton.visible = value
	$NextButton.visible = value
	$PeekButton.visible = value
	$Hint.text = "Click or drag an outer page edge · Arrow keys turn · Esc closes" if value else "Place the item · Esc returns to Khata"
	dimmer.color.a = 0.48 if value else 0.12


func _on_drag_canceled(_payload: HeldItemPayload) -> void:
	if exporting:
		_export_finished()


func _on_drag_dropped(_payload: HeldItemPayload, _target: DropZone) -> void:
	if exporting:
		_export_finished()


func _on_book_opened_changed(value: bool) -> void:
	if not value and _active:
		_finish_close()


func _finish_close() -> void:
	if not _active:
		return
	_active = false
	_closing = true
	animation.stop()
	hide()
	_release_ownership()
	_closing = false
	closed.emit()
	# Close/open observers can replace this destination during cleanup/signals.
	if _peek_after_close:
		_peek_after_close = false
		open_peek()


func _release_ownership() -> void:
	if is_instance_valid(controller):
		controller.end_modal_export(self)
		controller.set_world_input_blocked(self, false)
		# Mode was never forced to Use; a deliberate external change also keeps
		# its new selection through the mode_changed cancellation path.
		if is_instance_valid(controller.cursor_service):
			controller.cursor_service.call("_install_custom_cursors")
			controller.cursor_service.reset()
	exporting = false


func _on_mode_changed(_mode: StringName) -> void:
	if _active:
		# Keep the deliberate new selection while releasing notebook ownership.
		close()


func _on_visibility_changed() -> void:
	if _active and not is_visible_in_tree():
		_active = false
		_peek_after_close = false
		_closing = true
		hide()
		_release_ownership()
		book.reset_closed()
		_closing = false


func _exit_tree() -> void:
	close_peek()
	_active = false
	_closing = true
	hide()
	_release_ownership()
	if is_instance_valid(book):
		book.reset_closed()
	_closing = false


func _on_resize() -> void:
	if _active:
		cancel_export()
	_layout()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT] and _active:
		cancel_export()
		book.cancel_turn()


func _input(event: InputEvent) -> void:
	if _active and not _controller_is_live():
		hide()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		if _active:
			close()
		elif is_peeking():
			close_peek()
		elif not is_instance_valid(get_viewport().gui_get_focus_owner()):
			open_peek()
		get_viewport().set_input_as_handled()
		return
	if is_peeking() and event.is_action_pressed(InteractionController.INPUT_CANCEL):
		# A held world gesture gets first cancellation; otherwise put the page away.
		if _controller_is_live() and (controller.is_dragging() or controller.has_active_action()):
			controller.cancel_world_action()
		else:
			close_peek()
		get_viewport().set_input_as_handled()
		return
	if not _active:
		return
	if event.is_action_pressed(InteractionController.INPUT_CANCEL):
		if exporting:
			cancel_export()
		elif book.dragging:
			book.cancel_turn()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InteractionController.INPUT_ORGANIZE_TOGGLE) or event.is_action_pressed(InteractionController.INPUT_USE_TOGGLE):
		var mode := InteractionController.MODE_ORGANIZE if event.is_action_pressed(InteractionController.INPUT_ORGANIZE_TOGGLE) else InteractionController.MODE_USE
		controller.set_mode(InteractionController.MODE_NEUTRAL if controller.current_mode == mode else mode)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not exporting:
		book.handle_book_input(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if exporting:
			cancel_export()
		elif book.dragging:
			book.cancel_turn()
		else:
			close()
		get_viewport().set_input_as_handled()


func _on_book_input(event: InputEvent) -> void:
	if exporting or _closing:
		return
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		forwarded.position = book_input.get_global_transform_with_canvas() * event.position
	book.handle_book_input(forwarded)
	book_input.accept_event()


func _on_dimmer_input(event: InputEvent) -> void:
	if not exporting and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
	dimmer.accept_event()


func _on_page_changed(index: int) -> void:
	for page in range(4):
		$Pages.get_node(PAGE_NAMES[page]).visible = page == index
		($TabContainer.get_node(TAB_NAMES[page]) as Button).set_pressed_no_signal(page == index)
	page_selected.emit(index)


func _make_page(index: int, paper: Texture2D) -> Node:
	var page := ShellPage.new()
	page.name = PAGE_NAMES[index / 2] + ("Right" if index % 2 else "Left")
	page.configure(index, paper)
	return page


func _process(_delta: float) -> void:
	if is_peeking() and (not _controller_is_live() or controller.is_world_input_blocked()):
		close_peek()
	if not _active:
		return
	if not _controller_is_live():
		hide()
		return
	if exporting and not controller.is_modal_export_active(self):
		_export_finished()
	_layout()


func _controller_is_live() -> bool:
	return is_instance_valid(controller) and controller.is_inside_tree() and not controller.is_queued_for_deletion()


func _host_is_visible() -> bool:
	var host := get_parent() as CanvasItem
	return host == null or host.is_visible_in_tree()


func _layout() -> void:
	if not is_node_ready():
		return
	_place(book_input, Rect2(300, 190, 1000, 704))
	_place($Pages, Rect2(320, 209, 960, 660))
	_place($CloseButton, book.CLOSE_RECT)
	_place($PeekButton, Rect2(1060, 116, 182, 44))
	_place($PreviousButton, Rect2(165, 498, 58, 58))
	_place($NextButton, Rect2(1320, 498, 58, 58))
	_place($Hint, Rect2(310, 925, 980, 38))
	for index in range(4):
		var button := $TabContainer.get_node(TAB_NAMES[index]) as Button
		var tab := book.make_tab_rect(index)
		# Keep the authored size: Control minimum sizes would otherwise prevent
		# the bookmark from narrowing with the rotating cover.
		button.position = book.position + tab.position * book.scale
		button.size = book.TAB_SIZE
		button.scale = book.scale * tab.size / book.TAB_SIZE
		button.visible = tab.size.x > 0.6
		button.disabled = book.busy or not book.opened or _closing
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if button.disabled else Control.MOUSE_FILTER_STOP
	$PreviousButton.disabled = book.busy or not book.opened or book.spread <= 0 or _closing
	$NextButton.disabled = book.busy or not book.opened or book.spread >= 3 or _closing
	$PeekButton.disabled = book.busy or not book.opened or _closing
	book_input.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if book._edge_at(book.get_local_mouse_position()) != 0 and book.opened and not book.busy else Control.CURSOR_ARROW


func _place(control: Control, rect: Rect2) -> void:
	control.position = book.position + rect.position * book.scale
	control.size = rect.size
	control.scale = book.scale


func _style_button(button: Button, color: Color, tab := false) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.1) if state == "hover" else color
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("243129") if tab else Color("f0e9d4"))
	button.add_theme_color_override("font_pressed_color", Color("243129") if tab else Color("f0e9d4"))
	button.add_theme_color_override("font_disabled_color", Color("52604e") if tab else Color("8a9684"))
	button.add_theme_font_size_override("font_size", 15 if tab else 17)
