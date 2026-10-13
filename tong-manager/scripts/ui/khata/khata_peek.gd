class_name KhataPeek
extends Control
## One folded-back pantry page. Only this bounded Control intercepts the stall.

signal open_requested
signal close_requested

const ShellPage := preload("res://scripts/ui/khata/khata_shell_page.gd")
const PAGE_RECT := Rect2(16, 16, 480, 660)
const VIEW_SIZE := Vector2(512, 746)
var _arrival := 1.0
var _motion: Tween


func _ready() -> void:
	size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := AtlasTexture.new()
	paper.atlas = KhataBook.PAPER_SOURCE
	paper.region = Rect2(827, 53, 420, 800)
	var page := ShellPage.new()
	page.name = "Page"
	page.configure(0, paper)
	page.position = PAGE_RECT.position
	add_child(page)
	move_child(page, 0)
	$OpenButton.pressed.connect(func(): open_requested.emit())
	$CloseButton.pressed.connect(func(): close_requested.emit())
	for button in [$OpenButton, $CloseButton]:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_color_override("font_color", Color("f0e9d4"))
		for state in ["normal", "hover", "pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("4d6048") if state == "hover" else Color("353f34")
			style.set_corner_radius_all(4)
			button.add_theme_stylebox_override(state, style)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_layout)
	_layout()


func reveal() -> void:
	_stop_motion()
	_arrival = 0.0
	show()
	_layout()
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


func _layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var ratio := minf(viewport_size.x / 1600.0, viewport_size.y / 1000.0) * 0.82
	scale = Vector2.ONE * ratio
	position = viewport_size - VIEW_SIZE * ratio - Vector2(18, 20) * ratio
	position.x += (1.0 - _arrival) * 84.0 * ratio
	modulate.a = _arrival
	queue_redraw()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		# A hidden ancestor must not resurrect a stale Peek on scene reentry.
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
	# Folded cover and layered paper edges keep the quick view part of the book.
	draw_style_box(_cover_style(), Rect2(Vector2.ZERO, VIEW_SIZE))
	for offset in range(4, 0, -1):
		draw_rect(Rect2(PAGE_RECT.position + Vector2(offset * 1.8, offset * 1.5), PAGE_RECT.size), Color("bdae90"))
	draw_line(Vector2(11, 14), Vector2(11, 678), Color("9a8c62"), 3.0)


func _cover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("414d35")
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.02, 0.04, 0.02, 0.32)
	style.shadow_size = 12
	style.shadow_offset = Vector2(-4, 5)
	return style
