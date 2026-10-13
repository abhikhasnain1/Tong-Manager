class_name KhataModal
extends Control

signal opened
signal closed
signal page_selected(index: int)

const ShellPage := preload("res://scripts/ui/khata/khata_shell_page.gd")
const PAGE_NAMES := ["InventoryPage", "RecipesPage", "FinancePage", "QuestsPage"]
const TAB_NAMES := ["InventoryTab", "RecipesTab", "FinanceTab", "QuestsTab"]

@export_node_path("Control") var peek_path: NodePath
@export_node_path("Sprite2D") var cover_path: NodePath
@onready var peek: KhataPeek = get_node_or_null(peek_path) as KhataPeek if not peek_path.is_empty() else null
@onready var cover: Sprite2D = get_node_or_null(cover_path) as Sprite2D if not cover_path.is_empty() else null
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
var _travel_kind: StringName = &""
var _travel_progress := 0.0
var _travel_motion: Tween
var _travel_cover: Sprite2D
var _travel_from := Transform2D.IDENTITY
var _travel_book_rect := Rect2()
var _cover_leased := false
var _cover_was_visible := true
var _retiring := false


func _enter_tree() -> void:
	# Child page viewports are created before this Control's _ready callback.
	get_node("NotebookBackground/Book").page_factory = _make_page


func _ready() -> void:
	book.auto_fit = false
	book.opened_changed.connect(_on_book_opened_changed)
	book.fold_finished.connect(_on_fold_finished)
	book.page_changed.connect(_on_page_changed)
	book.close_requested.connect(close)
	book_input.gui_input.connect(_on_book_input)
	dimmer.gui_input.connect(_on_dimmer_input)
	$CloseButton.pressed.connect(close)
	$PeekButton.pressed.connect(open_peek)
	if is_instance_valid(peek):
		peek.book = book
		peek.open_requested.connect(open)
		peek.close_requested.connect(close_peek)
		peek.turn_requested.connect(book.request_turn)
		peek.book_input.connect(_on_peek_input)
		peek.visibility_changed.connect(_on_peek_visibility_changed)
	$PreviousButton.pressed.connect(func(): book.request_turn(-1))
	$NextButton.pressed.connect(func(): book.request_turn(1))
	for index in range(4):
		var button := $TabContainer.get_node(TAB_NAMES[index]) as Button
		button.pressed.connect(select_page.bind(index))
	get_viewport().size_changed.connect(_on_resize)
	visibility_changed.connect(_on_visibility_changed)
	_on_page_changed(0)
	_layout()


func configure(value: InteractionController) -> void:
	if controller == value:
		return
	_dismiss_peek()
	_stop_travel()
	_restore_cover()
	if _active:
		# The old controller owns any reservation and modal lock. Finish that
		# session before binding another controller, without transferring input.
		hide()
	elif is_node_ready():
		book.reset_closed()
		hide()
	if is_instance_valid(controller):
		_release_ownership()
		for pair in [[controller.mode_changed, _on_mode_changed], [controller.drag_canceled, _on_drag_canceled], [controller.drag_dropped, _on_drag_dropped]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	_active = false
	_closing = false
	_peek_after_close = false
	controller = value
	if is_instance_valid(controller):
		controller.mode_changed.connect(_on_mode_changed)
		controller.drag_canceled.connect(_on_drag_canceled)
		controller.drag_dropped.connect(_on_drag_dropped)


func open() -> bool:
	if _active or _closing or not is_inside_tree() or is_queued_for_deletion() or not _host_is_visible() or not _controller_is_live() or controller.is_world_input_blocked():
		return false
	if book.busy or is_traveling():
		return false
	var from_folded := book.opened and book.fold_amount > 0.0
	_active = true
	_closing = false
	_dismiss_peek()
	show()
	# Establish ownership before cancellation emits callbacks into world objects.
	controller.set_world_input_blocked(self, true)
	if not _active or _closing or is_queued_for_deletion():
		return false
	_reading_visible(true)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	if from_folded:
		book.fold_to(0.0)
	else:
		animation.play("reveal")
		_layout()
		if not _begin_travel(&"open_full"):
			book.open_book()
	opened.emit()
	return true


func is_open() -> bool:
	return _active


func is_modal_input_active() -> bool:
	# The renderer stays here in both poses; only Full owns the modal lock.
	return _active


func is_peeking() -> bool:
	return is_instance_valid(peek) and peek.is_visible_in_tree()


func is_traveling() -> bool:
	return _travel_kind != &""


func open_peek() -> bool:
	if (_closing or is_traveling() or not is_inside_tree() or is_queued_for_deletion()
		or not _peek_is_available() or not _controller_is_live()):
		return false
	if _active:
		if exporting:
			cancel_export()
			if not _active or _closing or not _peek_is_available():
				return false
		if book.busy:
			return false
		_peek_after_close = true
		return book.fold_to(1.0)
	if controller.is_world_input_blocked():
		return false
	if not is_peeking():
		show()
		var from_closed := not book.opened
		if from_closed:
			book.open_folded()
		peek.reveal(false)
		_reading_visible(true)
		_layout()
		if from_closed:
			_begin_travel(&"open_peek")
	return true


func close_peek() -> void:
	_peek_after_close = false
	if _active:
		_dismiss_peek()
		return
	if _closing:
		return
	if is_peeking() and is_node_ready():
		_closing = true
		book.cancel_turn()
		if _begin_travel(&"return_peek"):
			return
		_finish_peek_close()


func _dismiss_peek() -> void:
	if is_instance_valid(peek):
		# The shared renderer is still needed during a fold or return flight.
		var was_closing := _closing
		_closing = true
		peek.dismiss()
		_closing = was_closing


func _finish_peek_close() -> void:
	_stop_travel()
	_dismiss_peek()
	book.reset_closed()
	_restore_cover()
	hide()
	_closing = false


func close() -> void:
	close_peek()
	_start_close()


func _start_close() -> void:
	if not _active or _closing:
		return
	_closing = true
	cancel_export()
	_stop_travel()
	if book.folding:
		book.reset_closed()
		_begin_return()
	elif not book.opened and not book.busy:
		_begin_return()
	else:
		book.close_book()


func select_page(index: int) -> void:
	if (_active or is_peeking()) and not _closing and not exporting and not book.folding and not is_traveling() and index >= 0 and index < 4:
		book.select_page(index)


func begin_export(payload: HeldItemPayload, visual: Node2D, point: Vector2, allowed_targets: Array[DropZone]) -> bool:
	if not _active or _closing or is_traveling() or exporting or book.busy or not book.opened or not _controller_is_live():
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
	book_input.visible = value and _active
	$TabContainer.visible = value
	$Pages.visible = value and _active
	$PreviousButton.visible = value and _active
	$NextButton.visible = value and _active
	$PeekButton.visible = value and _active
	$CloseButton.visible = _active
	$Hint.hide()
	dimmer.visible = _active
	dimmer.color.a = 0.48 if value else 0.12


func _on_drag_canceled(_payload: HeldItemPayload) -> void:
	if exporting:
		_export_finished()


func _on_drag_dropped(_payload: HeldItemPayload, _target: DropZone) -> void:
	if exporting:
		_export_finished()


func _on_book_opened_changed(value: bool) -> void:
	if not value and _active and not _retiring:
		_begin_return()


func _begin_return() -> void:
	if _travel_kind == &"return_full":
		return
	if not _begin_travel(&"return_full"):
		_finish_close()


func _on_fold_finished(folded: bool) -> void:
	if not folded or not _active or not _peek_after_close:
		return
	_active = false
	_closing = true
	animation.stop()
	_release_ownership()
	_reading_visible(true)
	_closing = false
	closed.emit()
	# A close/open observer may replace the requested destination.
	if _peek_after_close and not _active and _peek_is_available() and _controller_is_live() and not controller.is_world_input_blocked():
		_peek_after_close = false
		peek.reveal(false)
		_layout()
	elif not _active and not is_peeking():
		_peek_after_close = false
		book.reset_closed()
		_restore_cover()
		hide()


func _finish_close() -> void:
	if not _active:
		return
	_active = false
	_closing = true
	_stop_travel()
	_restore_cover()
	book.reset_closed()
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
	elif is_peeking():
		book.cancel_turn()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and not _retiring and (_active or is_peeking() or is_traveling() or (is_instance_valid(book) and book.opened)):
		_retiring = true
		var owned_input := _active
		_active = false
		_peek_after_close = false
		_closing = true
		_stop_travel()
		_restore_cover()
		hide()
		if is_instance_valid(peek):
			peek.dismiss()
		if owned_input:
			_release_ownership()
		book.reset_closed()
		_closing = false
		_retiring = false


func _exit_tree() -> void:
	_retiring = true
	_dismiss_peek()
	_active = false
	_closing = true
	_stop_travel()
	_restore_cover()
	hide()
	_release_ownership()
	if is_instance_valid(book):
		book.reset_closed()
	_closing = false
	_retiring = false


func _on_resize() -> void:
	if _active:
		cancel_export()
	if is_instance_valid(book):
		book.cancel_turn()
	_layout()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if _active:
			cancel_export()
		if is_instance_valid(book):
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
	if is_traveling() and _active:
		# Keep modal ownership until the cover has reached its resting place.
		if event.is_action_pressed(InteractionController.INPUT_CANCEL):
			close()
		get_viewport().set_input_as_handled()
		return
	if is_peeking() and event.is_action_pressed(InteractionController.INPUT_CANCEL):
		# A held world gesture gets first cancellation; otherwise put the page away.
		if book.dragging:
			book.cancel_turn()
		elif _controller_is_live() and (controller.is_dragging() or controller.has_active_action()):
			controller.cancel_world_action()
		else:
			close_peek()
		get_viewport().set_input_as_handled()
		return
	if is_peeking():
		# Capture an owned page drag even outside the paper; ordinary world
		# events elsewhere continue through the normal interaction controller.
		if book.dragging and event is InputEventMouse:
			book.handle_book_input(event)
			get_viewport().set_input_as_handled()
		elif not is_traveling() and event is InputEventKey and event.keycode in [KEY_LEFT, KEY_RIGHT] and not controller.is_dragging() and not controller.has_active_action():
			book.handle_book_input(event)
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
	if exporting or _closing or is_traveling():
		return
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		forwarded.position = book_input.get_global_transform_with_canvas() * event.position
	book.handle_book_input(forwarded)
	book_input.accept_event()


func _on_peek_input(event: InputEvent) -> void:
	if is_peeking() and not is_traveling() and _controller_is_live() and not controller.is_dragging() and not controller.has_active_action():
		book.handle_book_input(event)


func _on_peek_visibility_changed() -> void:
	if not _active and not _closing and not is_peeking() and is_node_ready():
		_stop_travel()
		_restore_cover()
		book.reset_closed()
		hide()


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
	if is_traveling() and not _cover_is_live():
		if _active:
			_finish_close()
		else:
			_finish_peek_close()
		return
	if _travel_kind == &"open_peek" and not _peek_is_available():
		_finish_peek_close()
		return
	if _peek_after_close and book.folding and not _peek_is_available():
		close()
	if is_peeking() and (not _controller_is_live() or controller.is_world_input_blocked()):
		close_peek()
	if not _active and not is_peeking() and not is_traveling():
		return
	if not _controller_is_live():
		_stop_travel()
		_restore_cover()
		hide()
		return
	if exporting and not controller.is_modal_export_active(self):
		_export_finished()
	_layout()


func _cover_is_live() -> bool:
	return is_instance_valid(cover) and cover.is_inside_tree() and not cover.is_queued_for_deletion()


func _lease_cover() -> void:
	if not _cover_is_live() or _cover_leased:
		return
	_cover_was_visible = cover.visible
	_cover_leased = true
	cover.hide()


func _restore_cover() -> void:
	if _cover_leased and is_instance_valid(cover):
		cover.visible = _cover_was_visible
	_cover_leased = false


func _cover_ui_transform() -> Transform2D:
	return get_global_transform_with_canvas().affine_inverse() * cover.get_global_transform_with_canvas()


func _begin_travel(kind: StringName) -> bool:
	if not _cover_is_live() or not is_inside_tree() or not _host_is_visible():
		return false
	_stop_travel()
	if not is_instance_valid(_travel_cover):
		_travel_cover = Sprite2D.new()
		_travel_cover.name = "TravellingCover"
		_travel_cover.texture = cover.texture
		_travel_cover.region_enabled = cover.region_enabled
		_travel_cover.region_rect = cover.region_rect
		_travel_cover.centered = cover.centered
		_travel_cover.offset = cover.offset
		_travel_cover.flip_h = cover.flip_h
		_travel_cover.flip_v = cover.flip_v
		add_child(_travel_cover)
	_travel_book_rect = book.get_visible_book_rect()
	var book_to_ui := get_global_transform_with_canvas().affine_inverse() * book.get_global_transform_with_canvas()
	_travel_from = book_to_ui * _cover_to_book_transform()
	_travel_kind = kind
	_travel_progress = 0.0
	_lease_cover()
	_travel_cover.show()
	if is_instance_valid(peek):
		peek.input_suspended = true
	_layout()
	_travel_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_travel_motion.tween_method(_set_travel_progress, 0.0, 1.0, 0.55)
	_travel_motion.tween_callback(_travel_finished)
	return true


func _cover_to_book_transform() -> Transform2D:
	var source := _travel_cover.get_rect()
	var ratio := _travel_book_rect.size / source.size
	return Transform2D(Vector2(ratio.x, 0), Vector2(0, ratio.y), _travel_book_rect.position - source.position * ratio)


func _set_travel_progress(value: float) -> void:
	_travel_progress = value
	_layout()


func _layout_travel() -> void:
	if not is_traveling() or not _cover_is_live():
		return
	var returning := _travel_kind in [&"return_full", &"return_peek"]
	var home_pose := _cover_ui_transform()
	var book_to_ui := get_global_transform_with_canvas().affine_inverse() * book.get_global_transform_with_canvas()
	var reading_pose := book_to_ui * _cover_to_book_transform()
	_travel_cover.transform = _travel_from.interpolate_with(home_pose, _travel_progress) if returning else home_pose.interpolate_with(reading_pose, _travel_progress)
	# The rendered book and the authored cover share one travelling footprint.
	# Cross-blend their cloth details while approaching/leaving the stall.
	var ink_amount := 1.0 - smoothstep(0.0, 0.8, _travel_progress) if returning else smoothstep(0.2, 1.0, _travel_progress)
	book.transform = _travel_cover.transform * _cover_to_book_transform().affine_inverse()
	# Keep the paper stack opaque beneath the cover blend; fading every draw
	# would make the closed cover translucent and reveal printed pages inside.
	book.modulate.a = 1.0
	# Once Full has shut, travel with the exact authored cover. Blending two
	# differently proportioned cover labels would draw the handwriting twice.
	_travel_cover.modulate.a = 1.0 if _travel_kind == &"return_full" else 1.0 - ink_amount
	if _active:
		dimmer.color.a *= 1.0 - _travel_progress if returning else _travel_progress


func _travel_finished() -> void:
	var destination := _travel_kind
	_stop_travel()
	if destination == &"return_full":
		_finish_close()
	elif destination == &"return_peek":
		_finish_peek_close()
	elif destination == &"open_full":
		_layout()
		book.open_book()
	else:
		_layout()


func _stop_travel() -> void:
	if is_instance_valid(_travel_motion):
		_travel_motion.kill()
	_travel_motion = null
	_travel_kind = &""
	if is_instance_valid(_travel_cover):
		_travel_cover.hide()
	if is_instance_valid(book):
		book.modulate.a = 1.0
	if is_instance_valid(peek):
		peek.input_suspended = false


func _controller_is_live() -> bool:
	return is_instance_valid(controller) and controller.is_inside_tree() and not controller.is_queued_for_deletion()


func _host_is_visible() -> bool:
	var host := get_parent() as CanvasItem
	return host == null or host.is_visible_in_tree()


func _peek_is_available() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not _host_is_visible() or not is_instance_valid(peek) or not peek.is_inside_tree() or peek.is_queued_for_deletion():
		return false
	var host := peek.get_parent() as CanvasItem
	return host == null or host.is_visible_in_tree()


func _layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var fit := minf(viewport_size.x / book.DESIGN.x, viewport_size.y / book.DESIGN.y)
	var full_scale := Vector2.ONE * fit
	var full_position := (viewport_size - book.DESIGN * fit) * 0.5
	book.scale = full_scale
	book.rotation = 0.0
	book.position = full_position
	book.modulate.a = 1.0
	if _peek_is_available():
		var page_position := peek.position if is_peeking() else peek.settled_position()
		var folded_position := page_position + peek.PAGE_RECT.position * peek.scale - book._book_origin() * peek.scale
		book.scale = full_scale.lerp(peek.scale, book.fold_amount)
		book.position = full_position.lerp(folded_position, book.fold_amount)
		if is_peeking():
			book.modulate.a = peek.modulate.a
	dimmer.color.a = 0.12 if exporting else 0.48 * (1.0 - book.fold_amount)
	_layout_travel()
	_place(book_input, Rect2(300, 190, 1000, 704))
	_place($Pages, Rect2(320, 209, 960, 660))
	_place_ink($CloseButton, Vector2(390, 12))
	_place_ink($PeekButton, Vector2(280, 590))
	_place_ink($PreviousButton, Vector2(-420, 590))
	_place_ink($NextButton, Vector2(390, 590))
	var reading := book.opened and not book.busy and not _closing and not is_traveling() and not exporting
	# Bookmarks stay attached during travel, with input disabled until reading.
	$TabContainer.visible = not exporting
	for index in range(4):
		var button := $TabContainer.get_node(TAB_NAMES[index]) as Button
		var tab := book.make_tab_rect(index)
		button.set_pressed_no_signal(book.spread == index)
		# Keep the authored size: Control minimum sizes would otherwise prevent
		# the bookmark from narrowing with the rotating cover.
		button.position = book.position + tab.position * book.scale
		button.size = book.TAB_SIZE
		button.scale = book.scale * tab.size / book.TAB_SIZE
		button.visible = tab.size.x > 0.6
		button.disabled = not reading or (_controller_is_live() and (controller.is_dragging() or controller.has_active_action()))
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	$PreviousButton.disabled = book.busy or not book.opened or book.spread <= 0 or _closing
	$NextButton.disabled = book.busy or not book.opened or book.spread >= 3 or _closing
	$PreviousButton.visible = _active and reading
	$NextButton.visible = _active and reading
	$PeekButton.visible = _active and reading
	$CloseButton.visible = _active and reading
	$Hint.hide()
	$PeekButton.disabled = book.busy or not book.opened or _closing
	book_input.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if book._edge_at(book.get_local_mouse_position()) != 0 and book.opened and not book.busy else Control.CURSOR_ARROW


func _place_ink(control: Control, offset: Vector2) -> void:
	control.position = book.position + (book._book_origin() + offset) * book.scale
	control.size = Vector2(56, 56)
	control.scale = book.scale


func _place(control: Control, rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	var fit := minf(viewport_size.x / book.DESIGN.x, viewport_size.y / book.DESIGN.y)
	control.position = (viewport_size - book.DESIGN * fit) * 0.5 + rect.position * fit
	control.size = rect.size
	control.scale = Vector2.ONE * fit
