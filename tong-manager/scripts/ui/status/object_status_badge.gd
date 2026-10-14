class_name ObjectStatusBadge
extends Control
## Pointer-transparent bubbles; the owner layer moves this Control as one group.

var _config: StatusMarkerConfig = preload("res://data/balance/status_markers.tres")
var _tokens: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _badge_size := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = false


func configure(config: StatusMarkerConfig) -> void:
	_config = config if config != null else StatusMarkerConfig.new()
	_relayout()
	queue_redraw()


func set_tokens(tokens: Array[Dictionary]) -> void:
	if _tokens == tokens:
		return
	_tokens.assign(tokens.duplicate(true))
	_relayout()
	queue_redraw()


func get_tokens() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	copy.assign(_tokens.duplicate(true))
	return copy


func get_badge_size() -> Vector2:
	return _badge_size


func get_presentation_text() -> String:
	var descriptions := PackedStringArray()
	for token in _tokens:
		descriptions.append(String(token.get("description", token.get("label", ""))))
	return " · ".join(descriptions)


func get_token_rects() -> Array[Rect2]:
	return _rects.duplicate()


func _get_minimum_size() -> Vector2:
	return _badge_size


func _font() -> Font:
	return _config.font if _config.font != null else ThemeDB.fallback_font


func _amount_height() -> float:
	return maxf(22.0, _font().get_height(_config.amount_font_size) + 2.0)


func _relayout() -> void:
	_rects.clear()
	_badge_size = Vector2.ZERO
	var columns := maxi(1, _config.columns)
	var diameter := maxf(24.0, _config.bubble_size)
	var row_height := diameter + maxf(8.0, _amount_height() - 14.0)
	var gap := maxf(0.0, _config.bubble_gap)
	var row: Array[Rect2] = []
	var y := 2.0
	var x := 2.0
	for i in _tokens.size():
		var width := diameter
		if _tokens[i].kind == &"ingredient":
			var text := String(_tokens[i].get("amount_text", ""))
			width = maxf(width, _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _config.amount_font_size).x + 10.0)
		row.append(Rect2(Vector2(x, y), Vector2(width, row_height)))
		x += width + gap
		if row.size() == columns or i == _tokens.size() - 1:
			_badge_size.x = maxf(_badge_size.x, x - gap + 2.0)
			_rects.append_array(row)
			row.clear()
			x = 2.0
			y += row_height + gap
	if not _tokens.is_empty():
		_badge_size.y = y - gap + 1.0
	for row_start in range(0, _rects.size(), columns):
		var row_end := mini(row_start + columns - 1, _rects.size() - 1)
		var row_width := _rects[row_end].end.x - _rects[row_start].position.x
		var offset := (_badge_size.x - 4.0 - row_width) * 0.5
		for i in range(row_start, row_end + 1):
			_rects[i].position.x += offset
	custom_minimum_size = _badge_size
	size = _badge_size
	update_minimum_size()


func _draw() -> void:
	for i in _tokens.size():
		_draw_token(_tokens[i], _rects[i], i)


func _draw_token(token: Dictionary, rect: Rect2, index: int) -> void:
	var diameter := maxf(24.0, _config.bubble_size)
	var radius := diameter * 0.5
	var center := rect.position + Vector2(rect.size.x * 0.5, radius)
	draw_circle(center + Vector2(0, 2), radius, Color(_config.ink, 0.16), true, -1.0, true)
	draw_circle(center, radius, _config.paper, true, -1.0, true)
	draw_circle(center, radius - 2.0, _background(token), true, -1.0, true)
	var texture := token.get("icon") as Texture2D
	if token.kind == &"ingredient" and texture != null:
		var native := texture.get_size()
		if native.x > 0.0 and native.y > 0.0:
			var drawn := native * minf(diameter * 0.78 / native.x, diameter * 0.76 / native.y)
			draw_texture_rect(texture, Rect2(center - drawn * 0.5, drawn), false)
	else:
		var turn := -0.055 if index % 2 == 0 else 0.055
		draw_set_transform(center, turn, Vector2.ONE * diameter / 40.0)
		_draw_symbol(token)
		draw_set_transform(Vector2.ZERO)
	if token.kind == &"ingredient":
		_draw_amount(String(token.get("amount_text", "")), rect, diameter)


func _background(token: Dictionary) -> Color:
	var kind := StringName(token.kind)
	var band := StringName(token.get("band", &""))
	if kind == &"ingredient":
		match StringName(token.get("unit", &"")):
			&"teabag": return _config.mint
			&"spoonful": return _config.lilac
		return _config.paper
	if kind == &"thermal":
		return _config.blue if band == &"cool" else (_config.peach if band == &"hot" else _config.pink)
	if kind == &"heating" or band in [&"oversteeped", &"dirty", &"served", &"boiling"]:
		return _config.peach
	if kind == &"brew" and band == &"steeping":
		return _config.lilac
	if kind == &"fill" and token.get("liquid_id", &"") == &"water":
		return _config.blue
	return _config.mint


func _draw_amount(text: String, rect: Rect2, diameter: float) -> void:
	var font := _font()
	var font_size := _config.amount_font_size
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pill := Rect2(Vector2(rect.end.x - text_width - 7.0, rect.position.y + diameter - 14.0), Vector2(text_width + 8.0, _amount_height()))
	var style := StyleBoxFlat.new()
	style.bg_color = _config.paper
	style.set_corner_radius_all(7)
	style.shadow_color = Color(_config.ink, 0.17)
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, 1)
	draw_style_box(style, pill)
	draw_string(font, pill.position + Vector2(4, font.get_ascent(font_size) + (pill.size.y - font.get_height(font_size)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _config.ink)


func _line(points: Array[Vector2], color: Color, width := 1.8) -> void:
	draw_polyline(PackedVector2Array(points), color, width, true)


func _draw_symbol(token: Dictionary) -> void:
	var ink := _config.ink
	var kind := StringName(token.kind)
	var band := StringName(token.get("band", &""))
	match kind:
		&"fill":
			_draw_fill(token)
		&"thermal":
			if band == &"cool":
				for i in 3:
					var direction := Vector2.from_angle(float(i) * PI / 3.0)
					draw_line(-direction * 11.0, direction * 11.0, ink, 1.8, true)
					for sign_value in [-1.0, 1.0]:
						var tip: Vector2 = direction * 8.0 * float(sign_value)
						draw_line(tip, tip - direction.rotated(0.65) * 4.0 * sign_value, ink, 1.5, true)
						draw_line(tip, tip - direction.rotated(-0.65) * 4.0 * sign_value, ink, 1.5, true)
			else:
				draw_circle(Vector2.ZERO, 5.0, ink, false, 1.8, true)
				for i in (8 if band == &"hot" else 4):
					var angle := TAU * float(i) / (8.0 if band == &"hot" else 4.0)
					var ray := Vector2.from_angle(angle)
					draw_line(ray * 8.0, ray * 11.5, ink, 1.8, true)
		&"heating":
			var count := 1 if band == &"low" else (2 if band == &"medium" else 3)
			for i in count:
				var x := (float(i) - float(count - 1) * 0.5) * 8.0
				_line([Vector2(x, 10), Vector2(x - 3, 4), Vector2(x + 1, -3), Vector2(x + 2, -10), Vector2(x + 5, 1), Vector2(x + 4, 7), Vector2(x, 10)], ink, 1.6)
		&"brew":
			match band:
				&"steeping":
					_line([Vector2(-8, -11), Vector2(8, -11), Vector2(7, -6), Vector2(-6, 6), Vector2(-8, 11), Vector2(8, 11), Vector2(6, 6), Vector2(-7, -6), Vector2(-8, -11)], ink)
					draw_line(Vector2(-4, 7), Vector2(4, 7), ink, 2.0, true)
				&"boiling":
					draw_circle(Vector2(-6, 5), 4.0, ink, false, 1.8, true)
					draw_circle(Vector2(6, 1), 5.0, ink, false, 1.8, true)
					draw_circle(Vector2(-3, -8), 2.5, ink, false, 1.8, true)
				&"heating": _draw_steam(ink)
				&"oversteeped":
					_draw_cup(ink)
					draw_line(Vector2(0, -12), Vector2(0, -5), ink, 2.5, true)
					draw_circle(Vector2(0, -1), 1.3, ink, true, -1.0, true)
				_:
					_draw_cup(ink)
					_draw_steam(ink, Vector2(0, -9), 0.45)
		&"cleanliness":
			if band == &"clean":
				_line([Vector2(0, -11), Vector2(3, -3), Vector2(11, 0), Vector2(3, 3), Vector2(0, 11), Vector2(-3, 3), Vector2(-11, 0), Vector2(-3, -3), Vector2(0, -11)], ink)
				draw_circle(Vector2(10, -10), 1.5, ink, true, -1.0, true)
			else:
				_draw_cup(ink)
				draw_circle(Vector2(-3, 3), 2.5, ink, true, -1.0, true)
				draw_circle(Vector2(4, 6), 2.0, ink, true, -1.0, true)
				if band == &"dirty":
					draw_circle(Vector2(7, -8), 2.0, ink, true, -1.0, true)
		_:
			var initials := String(token.get("label", "?")).left(2).to_upper()
			draw_string(_font(), Vector2(-14, 5), initials, HORIZONTAL_ALIGNMENT_CENTER, 28, 15, ink)


func _draw_fill(token: Dictionary) -> void:
	var ink := _config.ink
	var band := StringName(token.get("band", &"empty"))
	var level: float = {&"empty": 0.0, &"low": 0.22, &"half": 0.52, &"full": 0.83}.get(band, 0.0)
	var fluid := _config.water if token.get("liquid_id", &"") == &"water" else _config.tea
	if level > 0.0:
		var top := 10.0 - level * 21.0
		draw_colored_polygon(PackedVector2Array([Vector2(-7.5, top), Vector2(7.5, top), Vector2(5, 10), Vector2(-5, 10)]), fluid)
	_line([Vector2(-9, -11), Vector2(9, -11), Vector2(6, 12), Vector2(-6, 12), Vector2(-9, -11)], ink)
	if token.get("liquid_id", &"") == &"water":
		draw_circle(Vector2(1, 5), 1.2, _config.paper, true, -1.0, true)


func _draw_cup(ink: Color) -> void:
	_line([Vector2(-9, -4), Vector2(7, -4), Vector2(6, 9), Vector2(-6, 9), Vector2(-9, -4)], ink)
	draw_arc(Vector2(8, 2), 4.0, -PI * 0.5, PI * 0.5, 12, ink, 1.8, true)
	draw_line(Vector2(-10, 12), Vector2(10, 12), ink, 1.8, true)


func _draw_steam(ink: Color, offset := Vector2.ZERO, scale_factor := 1.0) -> void:
	for i in 3:
		var points: Array[Vector2] = []
		for j in 7:
			points.append(offset + Vector2((float(i) - 1.0) * 7.0 + sin(float(j) * 0.9) * 2.0, 10.0 - float(j) * 3.5) * scale_factor)
		_line(points, ink, 1.7)
