class_name KhataPeek
extends Control
## Bounded controls for the folded pose of the shared notebook renderer.

signal open_requested
signal close_requested
signal book_input(event: InputEvent)
signal turn_requested(direction: int)

const PAGE_RECT := Rect2(16, 16, 480, 660)
const VIEW_SIZE := Vector2(584, 710)
var book: KhataBook
var input_suspended := false:
	set(value):
		input_suspended = value
		if is_node_ready():
			_refresh_buttons()
var _arrival := 1.0
var _motion: Tween


func _ready() -> void:
	size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	$OpenButton.pressed.connect(func(): open_requested.emit())
	$CloseButton.pressed.connect(func(): close_requested.emit())
	$PreviousButton.pressed.connect(func(): turn_requested.emit(-1))
	$NextButton.pressed.connect(func(): turn_requested.emit(1))
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_layout)
	_layout()


func reveal(animate := true) -> void:
	_stop_motion()
	_arrival = 0.0 if animate else 1.0
	show()
	_layout()
	if animate:
		_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_method(_set_arrival, 0.0, 1.0, 0.3)


func dismiss() -> void:
	_stop_motion()
	hide()
	_arrival = 1.0
	modulate.a = 1.0


func _set_arrival(value: float) -> void:
	_arrival = value
	_layout()


func settled_position() -> Vector2:
	return get_viewport_rect().size - VIEW_SIZE * scale - Vector2(18, 20) * scale


func _layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var ratio := minf(viewport_size.x / 1600.0, viewport_size.y / 1000.0) * 0.82
	scale = Vector2.ONE * ratio
	position = settled_position() + Vector2((1.0 - _arrival) * 84.0 * ratio, 0)
	modulate.a = _arrival
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(book):
		return
	_refresh_buttons()
	var point := book.get_local_mouse_position()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if book._edge_at(point) != 0 and not book.busy and not input_suspended else Control.CURSOR_ARROW


func _refresh_buttons() -> void:
	if not is_instance_valid(book):
		return
	$PreviousButton.disabled = input_suspended or book.busy or book.spread == 0
	$NextButton.disabled = input_suspended or book.busy or book.spread == book.section_titles.size() - 1
	$OpenButton.disabled = input_suspended or book.busy
	$CloseButton.disabled = input_suspended
	for button in [$PreviousButton, $NextButton, $OpenButton, $CloseButton]:
		button.visible = not input_suspended and not book.busy


func _gui_input(event: InputEvent) -> void:
	if input_suspended:
		accept_event()
		return
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		forwarded.position = get_global_transform_with_canvas() * event.position
	book_input.emit(forwarded)
	accept_event()


func _has_point(point: Vector2) -> bool:
	if not input_suspended and PAGE_RECT.has_point(point):
		return true
	if not is_instance_valid(book) or not book.is_visible_in_tree():
		return false
	# A curling leaf can briefly protrude beyond the folded page. It still owns
	# that visible patch, so a release cannot fall through into the stall.
	var global_point := get_global_transform_with_canvas() * point
	return book.get_visible_book_rect().has_point(book.get_global_transform_with_canvas().affine_inverse() * global_point)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_motion()
		if visible:
			hide()


func _exit_tree() -> void:
	dismiss()


func _stop_motion() -> void:
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = null
