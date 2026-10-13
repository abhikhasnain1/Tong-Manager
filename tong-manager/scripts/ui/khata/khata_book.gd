class_name KhataBook
extends Node2D
## Reusable book motion. The owning UI supplies pages and input arbitration.
const PAPER_SOURCE: Texture2D = preload("res://assets/art/khata/khata_open_reference.png")
const COVER_SOURCE: Texture2D = preload("res://assets/art/toolkit/khata_closed.png")
const TURN_SOUND: AudioStream = preload("res://assets/audio/page_turn.mp3")
const DESIGN := Vector2(1600, 1000)
const PAGE_SIZE := Vector2(480, 660)
const PAGE_EDGE_WIDTH := 85.0
var section_titles: Array[String] = ["Pantry", "Recipes", "Finance", "Quests"]
var section_colors: Array[Color] = [Color("91a878"), Color("bd916b"), Color("7994a1"), Color("a58bac")]
var page_factory: Callable
var standalone := false
var auto_fit := true

signal opened_changed(is_open: bool)
signal page_changed(section_index: int)
signal close_requested
const CLOSE_RECT := Rect2(1260, 116, 138, 44)
const SLOW_RECT := Rect2(1080, 43, 175, 40)
const SOUND_RECT := Rect2(1270, 43, 128, 40)

var spread := 0
var opened := false
var busy := false
var opening_amount := 0.0
var turn_progress := 0.0
var turn_direction := 1
var turning := false
var dragging := false
var slow_motion := false
var sound_enabled := true
var _drag_start := Vector2.ZERO
var _drag_distance := 0.0
var _pointer := Vector2(-1000, -1000)
var _hover_edge := 0.0
var _target_spread := -1
var _close_pending := false
var _opening := false
var _closing := false
var _tearing_down := false
var _layout_viewport: Viewport
var _motion: Tween
var _pages: Array[SubViewport] = []
var _paper: AtlasTexture
var _cover: Texture2D
var _audio: AudioStreamPlayer
var _font: Font = ThemeDB.fallback_font
var _title_font := SystemFont.new()


func _ready() -> void:
	if section_titles.is_empty():
		section_titles.append("Pantry")
	set_process_unhandled_input(standalone)
	_title_font.font_names = PackedStringArray(["Georgia", "Noto Serif", "serif"])
	_paper = AtlasTexture.new()
	_paper.atlas = PAPER_SOURCE
	# Original embedded bitmap, without its SVG wrapper; crop away from tabs/edges.
	_paper.region = Rect2(827, 53, 420, 800)
	var cover_viewport := SubViewport.new()
	cover_viewport.name = "CoverSurface"
	cover_viewport.size = Vector2i(PAGE_SIZE * 2)
	cover_viewport.transparent_bg = true
	cover_viewport.disable_3d = true
	cover_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(cover_viewport)
	# Reuse cloth, binding, label and corner at separate scales, keeping the
	# handwritten cover label in proportion on this wider reading-view notebook.
	_cover_piece(cover_viewport, Rect2(811, 317, 290, 480), Rect2(Vector2.ZERO, PAGE_SIZE))
	_cover_piece(cover_viewport, Rect2(795, 39, 18, 1003), Rect2(0, 0, 13, 660))
	_cover_piece(cover_viewport, Rect2(892, 169, 196, 98), Rect2(111, 95, 258, 129))
	_cover_piece(cover_viewport, Rect2(1037, 973, 88, 69), Rect2(400, 597, 80, 63))
	_cover = cover_viewport.get_texture()
	for index in range(section_titles.size() * 2):
		var viewport := SubViewport.new()
		viewport.name = "BookPage%d" % (index + 1)
		viewport.size = Vector2i(PAGE_SIZE * 2.0)
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var page := _make_page(index)
		if page is Node2D:
			(page as Node2D).scale = Vector2(2, 2)
		elif page is Control:
			(page as Control).scale = Vector2(2, 2)
		viewport.add_child(page)
		_pages.append(viewport)
	_audio = AudioStreamPlayer.new()
	_audio.stream = TURN_SOUND
	_audio.volume_db = -13.0
	add_child(_audio)
	_connect_layout()
	if standalone:
		# Only the isolated study replaces the gameplay cursor.
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	queue_redraw()


func _cover_piece(viewport: SubViewport, region: Rect2, destination: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = COVER_SOURCE
	atlas.region = region
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.position = destination.position * 2
	sprite.scale = destination.size * 2 / region.size
	viewport.add_child(sprite)


func _exit_tree() -> void:
	_tearing_down = true
	reset_closed()
	if is_instance_valid(_layout_viewport) and _layout_viewport.size_changed.is_connected(_on_viewport_resized):
		_layout_viewport.size_changed.disconnect(_on_viewport_resized)
	_layout_viewport = null
	if standalone:
		var service := get_node_or_null("/root/CursorService")
		if service != null:
			service.call("_install_custom_cursors")
			service.call("reset")


func reset_closed() -> void:
	# View-only teardown: never touch the world, stock, or selected spread.
	# Publish the closed signal after all state is coherent, so repeated cleanup
	# and observers that synchronously close again remain harmless.
	var was_active := opened or busy or turning or dragging or opening_amount > 0.0
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = null
	if is_instance_valid(_audio):
		_audio.stop()
	dragging = false
	turning = false
	busy = false
	opened = false
	_opening = false
	_closing = false
	_close_pending = false
	_target_spread = -1
	turn_progress = 0.0
	opening_amount = 0.0
	_drag_distance = 0.0
	_pointer = Vector2(-1000, -1000)
	_hover_edge = 0.0
	queue_redraw()
	if was_active:
		opened_changed.emit(false)


func _enter_tree() -> void:
	_tearing_down = false
	if not _pages.is_empty():
		_connect_layout.call_deferred()


func _connect_layout() -> void:
	if not is_inside_tree():
		return
	_layout_viewport = get_viewport()
	if not _layout_viewport.size_changed.is_connected(_on_viewport_resized):
		_layout_viewport.size_changed.connect(_on_viewport_resized)
	if auto_fit:
		_fit()


func _on_viewport_resized() -> void:
	cancel_turn()
	if auto_fit:
		_fit()


func _make_page(index: int) -> Node:
	var page: Node = null
	if page_factory.is_valid():
		page = page_factory.call(index, _paper) as Node
	if page != null:
		return page
	var blank := Node2D.new()
	var paper := Polygon2D.new()
	paper.polygon = PackedVector2Array([Vector2.ZERO, Vector2(PAGE_SIZE.x, 0), PAGE_SIZE, Vector2(0, PAGE_SIZE.y)])
	paper.color = Color("f0e4c8")
	blank.add_child(paper)
	var texture := Sprite2D.new()
	texture.texture = _paper
	texture.centered = false
	texture.scale = PAGE_SIZE / _paper.get_size()
	blank.add_child(texture)
	return blank

func _fit() -> void:
	if not is_inside_tree():
		return
	var available := get_viewport_rect().size
	var fit_scale := minf(available.x / DESIGN.x, available.y / DESIGN.y)
	scale = Vector2.ONE * fit_scale
	position = (available - DESIGN * fit_scale) * 0.5
	if dragging:
		cancel_turn()
	queue_redraw()

func _process(delta: float) -> void:
	var wants_edge := opened and not busy and _edge_at(_pointer) != 0
	_hover_edge = move_toward(_hover_edge, 1.0 if wants_edge else 0.0, delta * 7.0)
	queue_redraw()


func _book_origin() -> Vector2:
	return Vector2(560 + 240 * opening_amount, 209)


func _edge_at(point: Vector2) -> int:
	var local := point - _book_origin()
	if Rect2(PAGE_SIZE.x - PAGE_EDGE_WIDTH, 0, PAGE_EDGE_WIDTH, PAGE_SIZE.y).has_point(local) and spread < section_titles.size() - 1:
		return 1
	if Rect2(-PAGE_SIZE.x, 0, PAGE_EDGE_WIDTH, PAGE_SIZE.y).has_point(local) and spread > 0:
		return -1
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if standalone and handle_book_input(event):
		get_viewport().set_input_as_handled()


func handle_book_input(event: InputEvent) -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	if event is InputEventMouse:
		_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventMouseMotion:
		if dragging:
			_drag_distance = maxf(_drag_distance, _pointer.distance_to(_drag_start))
			turn_progress = clampf((_drag_start.x - _pointer.x) * turn_direction / 750.0, 0.0, 1.0)
		if standalone:
			var actionable := _edge_at(_pointer) != 0 or CLOSE_RECT.has_point(_pointer)
			if not opened:
				actionable = Rect2(_book_origin(), PAGE_SIZE).has_point(_pointer)
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if actionable and not busy else Input.CURSOR_ARROW)
		return dragging
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and dragging:
			_finish_turn(_drag_distance < 9.0 or turn_progress > 0.35)
			return true
		if event.pressed:
			return _handle_click(_pointer)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and dragging:
		cancel_turn()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not standalone:
					if opened or busy:
						close_requested.emit()
						return true
				elif dragging:
					cancel_turn()
					return true
				elif opened or _opening:
					close_book()
					return true
			KEY_SPACE, KEY_ENTER:
				if standalone:
					if opened or _opening:
						close_book()
					else:
						open_book()
					return true
			KEY_RIGHT, KEY_LEFT:
				if opened:
					request_turn(1 if event.keycode == KEY_RIGHT else -1)
					return true
			KEY_S:
				if standalone:
					slow_motion = not slow_motion
					return true
			KEY_M:
				if standalone:
					sound_enabled = not sound_enabled
					if not sound_enabled:
						_audio.stop()
					return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_turn()

func _handle_click(point: Vector2) -> bool:
	if standalone:
		if SOUND_RECT.has_point(point):
			sound_enabled = not sound_enabled
			if not sound_enabled:
				_audio.stop()
			return true
		if SLOW_RECT.has_point(point):
			slow_motion = not slow_motion
			return true
		if CLOSE_RECT.has_point(point) and (opened or _opening):
			close_book()
			return true
	if busy:
		return false
	if not opened:
		if standalone and Rect2(_book_origin(), PAGE_SIZE).has_point(point):
			open_book()
			return true
		return false
	if standalone:
		for index in range(section_titles.size()):
			if make_tab_rect(index).has_point(point):
				select_page(index)
				return true
	var edge := _edge_at(point)
	if edge != 0:
		_begin_turn(edge)
		dragging = true
		_drag_start = point
		_drag_distance = 0.0
		return true
	if standalone and Rect2(225, 498, 58, 58).has_point(point):
		request_turn(-1)
		return true
	if standalone and Rect2(1320, 498, 58, 58).has_point(point):
		request_turn(1)
		return true
	return false

func open_book() -> void:
	if _tearing_down or busy or opened or not is_inside_tree() or _pages.is_empty():
		return
	busy = true
	_opening = true
	_close_pending = false
	_play_sound(0.9)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "opening_amount", 1.0, _duration(0.85))
	_motion.tween_callback(func():
		opened = true
		busy = false
		_opening = false
		opened_changed.emit(true)
		if not is_inside_tree() or is_queued_for_deletion():
			return
		if _close_pending:
			close_book()
		else:
			_continue_navigation()
	)

func close_book() -> void:
	if _opening:
		_close_pending = true
		_target_spread = -1
		return
	if not opened or _closing or not is_inside_tree():
		return
	if busy:
		if turning:
			_close_pending = true
			_target_spread = -1
			if dragging:
				_finish_turn(false)
		return
	busy = true
	_closing = true
	_target_spread = -1
	_play_sound(0.85)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "opening_amount", 0.0, _duration(0.75))
	_motion.tween_callback(func():
		opened = false
		busy = false
		_closing = false
		_close_pending = false
		opened_changed.emit(false)
	)

func request_turn(direction: int) -> void:
	if direction not in [-1, 1] or not opened or busy or spread + direction < 0 or spread + direction >= section_titles.size():
		return
	_begin_turn(direction)
	_finish_turn(true)


func select_page(index: int) -> void:
	# Public page selection uses section/spread indices, not individual leaf sides.
	if index < 0 or index >= section_titles.size() or _closing:
		return
	if not opened and not _opening:
		if spread != index:
			spread = index
			page_changed.emit(spread)
		queue_redraw()
		return
	_target_spread = index
	if not busy:
		_continue_navigation()


func cancel_turn() -> void:
	_target_spread = -1
	if turning:
		_finish_turn(false)

func _begin_turn(direction: int) -> void:
	turn_direction = direction
	turn_progress = 0.0
	busy = true
	turning = true
	_play_sound(1.03 if direction > 0 else 0.97)


func _finish_turn(commit: bool) -> void:
	if not turning or not is_inside_tree():
		return
	dragging = false
	if is_instance_valid(_motion):
		_motion.kill()
	var destination := 1.0 if commit else 0.0
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "turn_progress", destination, _duration(maxf(0.18, absf(destination - turn_progress) * 0.78)))
	_motion.tween_callback(func():
		if commit:
			spread += turn_direction
		turning = false
		busy = false
		turn_progress = 0.0
		if commit:
			page_changed.emit(spread)
		if not is_inside_tree() or is_queued_for_deletion():
			return
		if _close_pending:
			close_book()
		else:
			_continue_navigation()
	)

func _continue_navigation() -> void:
	if _target_spread < 0 or _target_spread == spread:
		_target_spread = -1
		return
	request_turn(1 if _target_spread > spread else -1)


func _duration(seconds: float) -> float:
	return seconds * (2.5 if slow_motion else 1.0)


func _play_sound(pitch: float) -> void:
	if sound_enabled:
		_audio.pitch_scale = pitch
		_audio.play()


func make_tab_rect(index: int) -> Rect2:
	return Rect2(_book_origin() + Vector2(-547, 65 + 90 * index), Vector2(72, 66))


func _tab_rect(index: int) -> Rect2:
	# Compatibility for the accepted standalone motion test.
	return make_tab_rect(index)

func _draw() -> void:
	if _pages.is_empty():
		return
	if standalone:
		# Warm, quiet tabletop; only the notebook is interactive in this study.
		draw_rect(Rect2(-2000, -2000, 6000, 6000), Color("252c29"))
		for index in range(18):
			draw_line(Vector2(0, index * 65 + 10), Vector2(1600, index * 65 - 90), Color(0.7, 0.75, 0.65, 0.022), 2.0)
		draw_string(_font, Vector2(200, 65), "KHATA  /  MOTION STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("bcc8b9"))
		draw_string(_title_font, Vector2(200, 123), "A notebook for the stall", HORIZONTAL_ALIGNMENT_LEFT, -1, 35, Color("f0e9d4"))
		draw_string(_font, Vector2(202, 154), "Sample pages · visual review", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("aeb8aa"))
		_draw_button(SLOW_RECT, "Slow motion" if not slow_motion else "Slow motion: on", slow_motion)
		_draw_button(SOUND_RECT, "Sound: on" if sound_enabled else "Sound: off", sound_enabled)
		if opened:
			_draw_button(CLOSE_RECT, "Close khata", false)
	var origin := _book_origin()
	draw_set_transform(origin)
	# Until the front cover rests on the left, the bound paper block remains
	# on the right. Growing a flat block during opening would expose a blank slab.
	var resting_open := opening_amount > 0.98
	var left_extent := -494.0 if resting_open else 0.0
	for layer in range(14, 0, -1):
		draw_style_box(_box(Color(0, 0, 0, 0.013), 13), Rect2(left_extent - layer * 2.0, 10 - layer, 501 - left_extent + layer * 4, 680 + layer * 2))
	draw_style_box(_box(Color("642d29"), 5), Rect2(left_extent, -12, 494 - left_extent, 687))
	# Paper block edges add thickness before any sheet moves.
	for layer in range(5, 0, -1):
		var paper_left := -480.0 if resting_open else 0.0
		draw_rect(Rect2(paper_left, layer * 2, 480 - paper_left, 660), Color("aaa38a").lightened(layer * 0.025))
	if opening_amount > 0.98:
		var left_page := spread * 2
		var right_page := left_page + 1
		if turning:
			if turn_direction > 0:
				right_page += 2
			else:
				left_page -= 2
		draw_texture_rect(_pages[left_page].get_texture(), Rect2(-PAGE_SIZE.x, 0, PAGE_SIZE.x, PAGE_SIZE.y), false)
		draw_texture_rect(_pages[right_page].get_texture(), Rect2(Vector2.ZERO, PAGE_SIZE), false)
		_draw_spine()
		if turning:
			var front_index := spread * 2 + (1 if turn_direction > 0 else 0)
			var back_index := front_index + turn_direction
			var angle := turn_progress * PI if turn_direction > 0 else (1.0 - turn_progress) * PI
			_draw_sheet(angle, _pages[front_index].get_texture(), _pages[back_index].get_texture(), turn_direction < 0, true)
		elif _hover_edge > 0.0:
			_draw_edge_hint(_edge_at(_pointer))
	else:
		# Right-hand page is revealed as the real cover rotates around the binding.
		draw_texture_rect(_pages[spread * 2 + 1].get_texture(), Rect2(Vector2.ZERO, PAGE_SIZE), false)
		_draw_sheet(opening_amount * PI, _cover, _pages[spread * 2].get_texture(), false, false)
	draw_set_transform(Vector2.ZERO)
	if standalone:
		if opened:
			for index in range(section_titles.size()):
				var tab := _tab_rect(index)
				var tab_color := section_colors[index % section_colors.size()] if not section_colors.is_empty() else Color("91a878")
				draw_style_box(_box(tab_color.darkened(0.12 if spread != index else 0), 4), tab)
				draw_string(_font, tab.position + Vector2(9, 39), section_titles[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("243129"))
			_draw_arrow(Vector2(250, 528), -1, spread > 0)
			_draw_arrow(Vector2(1348, 528), 1, spread < section_titles.size() - 1)
			draw_string(_font, Vector2(500, 934), "Click or drag either outer edge  ·  ← / → turn  ·  Esc closes", HORIZONTAL_ALIGNMENT_CENTER, 600, 18, Color("d1d6c7"))
			draw_string(_font, Vector2(500, 968), "%s  ·  %d / %d" % [section_titles[spread], spread + 1, section_titles.size()], HORIZONTAL_ALIGNMENT_CENTER, 600, 16, Color("94a38f"))
		else:
			draw_string(_font, Vector2(500, 934), "Click the cover to open  ·  Space / Enter", HORIZONTAL_ALIGNMENT_CENTER, 600, 20, Color("d1d6c7"))


func _draw_sheet(angle: float, front: Texture2D, back: Texture2D, from_left: bool, flexible: bool) -> void:
	var lift := sin(angle)
	var curl := lift * 0.85 if flexible else 0.0
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var segment_count := 48
	var x := 0.0
	var depth := 0.0
	for index in range(segment_count + 1):
		var u := float(index) / segment_count
		if index > 0:
			var slope := angle + curl * (u - 0.5)
			x += cos(slope) * PAGE_SIZE.x / segment_count
			depth += sin(slope) * PAGE_SIZE.x / segment_count
		var top_y := -depth * 0.23
		top.append(Vector2(x, top_y))
		bottom.append(Vector2(x, top_y + PAGE_SIZE.y * (1.0 - depth / 3100.0)))
	# Broad cast shadow falls across the exposed page below the lifted sheet.
	if lift > 0.01:
		var shadow := PackedVector2Array([Vector2.ZERO, top[-1] + Vector2(45 * lift, 55 * lift), bottom[-1] + Vector2(45 * lift, 55 * lift), Vector2(0, 660)])
		draw_colored_polygon(shadow, Color(0.13, 0.11, 0.06, 0.16 * lift))
	for index in range(segment_count):
		var u0 := float(index) / segment_count
		var u1 := float(index + 1) / segment_count
		# A curled leaf can show both faces at once. Pick each strip's local face,
		# not the global angle, so text does not pop at the halfway point.
		var facing_back := cos(angle + curl * (u1 - 0.5)) < 0.0
		var texture := back if facing_back != from_left else front
		var points := PackedVector2Array([top[index], top[index + 1], bottom[index + 1], bottom[index]])
		if absf(top[index + 1].x - top[index].x) < 0.005:
			continue
		var tex0 := 1.0 - u0 if facing_back else u0
		var tex1 := 1.0 - u1 if facing_back else u1
		var shade := 1.0 - lift * (0.10 + 0.12 * sin(u0 * PI))
		draw_polygon(points, PackedColorArray([Color(shade, shade, shade)]), PackedVector2Array([Vector2(tex0, 0), Vector2(tex1, 0), Vector2(tex1, 1), Vector2(tex0, 1)]), texture)
	draw_polyline(top, Color(0.37, 0.30, 0.19, 0.55), 1.2, true)
	draw_polyline(bottom, Color(0.37, 0.30, 0.19, 0.65), 1.4, true)


func _draw_spine() -> void:
	for index in range(28):
		var alpha := 0.18 * pow(1.0 - float(index) / 28.0, 2)
		draw_line(Vector2(index, 0), Vector2(index, 660), Color(0.20, 0.17, 0.09, alpha), 1)
		draw_line(Vector2(-index, 0), Vector2(-index, 660), Color(0.20, 0.17, 0.09, alpha), 1)


func _draw_edge_hint(direction: int) -> void:
	if direction == 0:
		return
	var edge_x := PAGE_SIZE.x * direction
	# The hint follows the full usable side, matching the click/drag region.
	for offset in range(12):
		var alpha := (1.0 - float(offset) / 12.0) * 0.45 * _hover_edge
		var x := edge_x - direction * (offset + 1)
		draw_line(Vector2(x, 0), Vector2(x, PAGE_SIZE.y), Color(1.0, 0.98, 0.85, alpha), 1.0)


func _draw_arrow(center: Vector2, direction: int, enabled: bool) -> void:
	var color := Color("d4d9c6") if enabled else Color("4c584d")
	draw_polyline(PackedVector2Array([center + Vector2(-direction * 7, -12), center + Vector2(direction * 7, 0), center + Vector2(-direction * 7, 12)]), color, 2.5, true)


func _draw_button(rect: Rect2, text: String, active: bool) -> void:
	draw_style_box(_box(Color("4b5b49") if active else Color("323e35"), 7), rect)
	draw_string(_font, rect.position + Vector2(0, 27), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color("e0e4d4"))


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
