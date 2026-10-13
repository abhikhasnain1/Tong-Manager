class_name KhataInkButton
extends Button
## Pencil navigation drawn directly on a page or an attached paper bookmark.

@export var ink_icon: StringName = &"next":
	set(value):
		ink_icon = value
		queue_redraw()
@export var paper_tab := false:
	set(value):
		paper_tab = value
		queue_redraw()
@export var tab_color := Color("91a878"):
	set(value):
		tab_color = value
		queue_redraw()

const DESIGN_SIZE := Vector2(72, 66)
var _ink := Color("503d2c")
var _line_width := 1.9


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	queue_redraw()


func _draw() -> void:
	var mode := get_draw_mode()
	var hovered := mode in [DRAW_HOVER, DRAW_HOVER_PRESSED]
	var pressed_down := mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
	_ink = Color("35271c") if hovered or pressed_down else Color("503d2c")
	if disabled:
		_ink.a = 0.32
	_line_width = 2.25 if hovered or pressed_down else 1.9
	draw_set_transform(Vector2.ZERO, 0.0, size / DESIGN_SIZE)
	if paper_tab:
		_draw_paper(hovered, pressed_down)
	match ink_icon:
		&"previous":
			_stroke([Vector2(55, 32), Vector2(20, 33), Vector2(33, 20)])
			_stroke([Vector2(20, 33), Vector2(34, 46)])
		&"next":
			_stroke([Vector2(17, 33), Vector2(52, 32), Vector2(39, 19)])
			_stroke([Vector2(52, 32), Vector2(38, 46)])
		&"expand":
			_draw_notebook(false)
			_stroke([Vector2(29, 30), Vector2(8, 31), Vector2(17, 22)])
			_stroke([Vector2(8, 31), Vector2(17, 40)])
		&"fold":
			_draw_notebook(true)
			_stroke([Vector2(14, 29), Vector2(30, 25), Vector2(47, 29), Vector2(40, 20)])
			_stroke([Vector2(47, 29), Vector2(38, 35)])
		&"close":
			_stroke([Vector2(25, 19), Vector2(53, 16), Vector2(56, 47), Vector2(28, 50), Vector2(25, 19)])
			_stroke([Vector2(30, 20), Vector2(33, 47)])
			_stroke([Vector2(20, 46), Vector2(12, 40), Vector2(11, 27), Vector2(20, 20)])
			_stroke([Vector2(12, 19), Vector2(20, 20), Vector2(20, 28)])
		&"pantry":
			_stroke([Vector2(22, 27), Vector2(47, 26), Vector2(45, 44), Vector2(39, 49), Vector2(29, 48), Vector2(24, 43), Vector2(22, 27)])
			_stroke([Vector2(48, 29), Vector2(55, 29), Vector2(57, 36), Vector2(53, 42), Vector2(46, 42)])
			_stroke([Vector2(29, 21), Vector2(27, 17), Vector2(30, 12)])
			_stroke([Vector2(39, 21), Vector2(37, 17), Vector2(40, 11)])
		&"recipes":
			_draw_notebook(true)
			_stroke([Vector2(22, 30), Vector2(30, 31)])
			_stroke([Vector2(21, 37), Vector2(30, 38)])
			_stroke([Vector2(42, 31), Vector2(52, 29)])
			_stroke([Vector2(42, 38), Vector2(53, 36)])
		&"finance":
			_stroke([Vector2(19, 18), Vector2(48, 18), Vector2(49, 45), Vector2(20, 45), Vector2(19, 18)])
			_stroke([Vector2(25, 24), Vector2(42, 24)])
			_stroke([Vector2(25, 31), Vector2(37, 31)])
			_stroke([Vector2(25, 38), Vector2(34, 38)])
			_loop(Vector2(49, 45), Vector2(10, 9))
			_stroke([Vector2(49, 39), Vector2(49, 50)])
			_stroke([Vector2(45, 42), Vector2(53, 42)])
		&"quests":
			_stroke([Vector2(23, 15), Vector2(52, 17), Vector2(51, 50), Vector2(21, 48), Vector2(23, 15)])
			_stroke([Vector2(26, 26), Vector2(29, 29), Vector2(35, 21)])
			_stroke([Vector2(39, 26), Vector2(46, 26)])
			_stroke([Vector2(27, 36), Vector2(31, 39), Vector2(36, 32)])
			_stroke([Vector2(40, 36), Vector2(46, 36)])
	if paper_tab and button_pressed:
		_stroke([Vector2(19, 55), Vector2(34, 56), Vector2(54, 54)])
	elif hovered and not disabled:
		var underline := _ink
		underline.a = 0.28
		draw_polyline(PackedVector2Array([Vector2(24, 54), Vector2(38, 55), Vector2(49, 53)]), underline, 1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_paper(hovered: bool, pressed_down: bool) -> void:
	var paper := tab_color.lightened(0.09 if hovered else 0.0)
	if pressed_down:
		paper = paper.darkened(0.035)
	var outline := PackedVector2Array([Vector2(1, 3), Vector2(67, 1), Vector2(71, 7),
		Vector2(69, 62), Vector2(65, 65), Vector2(2, 63)])
	draw_colored_polygon(outline, paper)
	outline.append(outline[0])
	var edge := _ink
	edge.a = 0.3 if not disabled else 0.16
	draw_polyline(outline, edge, 0.9, true)
	draw_line(Vector2(7, 7), Vector2(8, 59), edge, 1.0, true)
	draw_line(Vector2(10, 8), Vector2(11, 58), Color(1, 0.97, 0.86, 0.20), 1.0, true)


func _draw_notebook(both_sides: bool) -> void:
	_stroke([Vector2(36, 20), Vector2(56, 17), Vector2(58, 47), Vector2(37, 50), Vector2(36, 20)])
	if both_sides:
		_stroke([Vector2(36, 20), Vector2(17, 16), Vector2(15, 46), Vector2(37, 50)])
	else:
		_stroke([Vector2(34, 22), Vector2(33, 49), Vector2(39, 52), Vector2(58, 49)])


func _loop(center: Vector2, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for index in range(17):
		var angle := float(index) / 16.0 * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_stroke(points)


func _stroke(points: PackedVector2Array) -> void:
	draw_polyline(points, _ink, _line_width, true)
	var pencil := PackedVector2Array()
	for index in range(points.size()):
		pencil.append(points[index] + Vector2(0.7 + sin(index * 1.9) * 0.35, 0.65 + cos(index * 1.3) * 0.3))
	var faint := _ink
	faint.a *= 0.38
	draw_polyline(pencil, faint, 0.7, true)
