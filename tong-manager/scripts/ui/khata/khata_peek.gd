class_name KhataPeek
extends Control
## Bounded controls for the folded pose of the shared notebook renderer.

signal open_requested
signal close_requested
signal book_input(event: InputEvent)
signal turn_requested(direction: int)

const PAGE_RECT := Rect2(16, 16, 480, 660)
const VIEW_SIZE := Vector2(512, 746)
var book: KhataBook
var _arrival := 1.0
var _motion: Tween


func _ready() -> void:
	size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	$OpenButton.pressed.connect(func(): open_requested.emit())
	$CloseButton.pressed.connect(func(): close_requested.emit())
	$PreviousButton.pressed.connect(func(): turn_requested.emit(-1))
	$NextButton.pressed.connect(func(): turn_requested.emit(1))
	for button in [$OpenButton, $CloseButton, $PreviousButton, $NextButton]:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", Color("f0e9d4"))
		button.add_theme_color_override("font_disabled_color", Color("897d70"))
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("795149") if state == "hover" else Color("51382f")
			style.set_corner_radius_all(4)
			button.add_theme_stylebox_override(state, style)
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
	$PreviousButton.disabled = book.busy or book.spread == 0
	$NextButton.disabled = book.busy or book.spread == book.section_titles.size() - 1
	$OpenButton.disabled = book.busy
	var point := book.get_local_mouse_position()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if book._edge_at(point) != 0 and not book.busy else Control.CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		forwarded.position = get_global_transform_with_canvas() * event.position
	book_input.emit(forwarded)
	accept_event()


func _has_point(point: Vector2) -> bool:
	if Rect2(Vector2.ZERO, size).has_point(point):
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


func _draw() -> void:
	# Paper, folded cover, binding and curls are all drawn by the same Book.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("642d29")
	style.set_corner_radius_all(5)
	draw_style_box(style, Rect2(0, 679, VIEW_SIZE.x, VIEW_SIZE.y - 679))
