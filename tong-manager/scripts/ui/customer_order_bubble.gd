class_name CustomerOrderBubble
extends Control
## Read-only order cues. The owner controls visibility and screen placement.

const CUP_ICON := preload("res://assets/art/toolkit/cup_clean_provisional.png")

@export_range(32.0, 64.0, 1.0) var bubble_diameter := 46.0
@export_range(0.0, 16.0, 1.0) var bubble_gap := 5.0
@export_range(1, 6, 1) var columns := 3
@export_range(10, 24, 1) var amount_font_size := 14
@export var font: Font

var order: OrderState:
	get: return _order
	set(_value): pass

var _order: OrderState
var _display: Dictionary = {"valid": false, "order_id": &"", "request_id": &"", "request_kind": &"", "tokens": [], "accessibility_summary": ""}
var _tokens: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _content_size := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = false


func set_order(value: OrderState, catalog: Node = null) -> void:
	_order = value
	_tokens.clear()
	_display = {"valid": false, "order_id": &"", "request_id": &"", "request_kind": &"",
		"tokens": [], "accessibility_summary": ""}
	if not is_instance_valid(catalog) and is_inside_tree(): catalog = get_node_or_null("/root/Catalog")
	var request := value.get_request() if value != null else {}
	if request.is_empty():
		_relayout()
		queue_redraw()
		return
	var descriptions := PackedStringArray()
	if request.kind == &"tea":
		var identity := StringName(request.brewed_liquid_id)
		var label := _item_label(catalog, identity)
		var token := _token(&"tea", &"tea", identity, label, CUP_ICON, request.quantity, &"cup")
		token["identity_icon"] = request.get("icon") as Texture2D
		token["identity_label"] = label
		token["amount_text"] = ""
		token["description"] = "%s %s of %s" % [request.quantity, _unit_label(&"cup", request.quantity), label]
		_tokens.append(token)
		descriptions.append(token.description)
		var additions: Array[Dictionary] = []
		for raw_id in request.cup_portion_counts:
			var item_id := StringName(raw_id)
			var item := _item(catalog, item_id)
			var amount := int(request.cup_portion_counts[raw_id])
			var unit := StringName(request.cup_portion_units[raw_id])
			var addition := _token(StringName("addition:" + String(item_id)), &"addition", item_id,
				_item_label(catalog, item_id), item.icon if item != null else null, amount, unit)
			addition["pantry_order"] = item.pantry_order if item != null else 2147483647
			additions.append(addition)
		additions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.pantry_order != b.pantry_order: return a.pantry_order < b.pantry_order
			return String(a.item_id) < String(b.item_id))
		for addition in additions:
			_tokens.append(addition)
			descriptions.append(addition.description)
		if additions.is_empty(): descriptions.append("No requested cup additions")
	elif request.kind == &"ready_item":
		var item_id := StringName(request.item_id)
		var token := _token(&"ready_item", &"ready_item", item_id, _item_label(catalog, item_id),
			request.get("icon") as Texture2D, request.quantity, StringName(request.unit))
		_tokens.append(token)
		descriptions.append(token.description)
	_display = {"valid": not _tokens.is_empty(), "order_id": value.order_id,
		"request_id": value.request_id, "request_kind": value.request_kind,
		"tokens": _tokens.duplicate(true), "accessibility_summary": "; ".join(descriptions)}
	_relayout()
	queue_redraw()


func get_display_snapshot() -> Dictionary:
	return _display.duplicate(true)


func get_accessibility_summary() -> String:
	return _display.get("accessibility_summary", "")


func get_token_rects() -> Array[Rect2]:
	return _rects.duplicate()


func _get_minimum_size() -> Vector2:
	return _content_size


func _font() -> Font:
	return font if font != null else ThemeDB.fallback_font


func _diameter() -> float:
	return clampf(bubble_diameter, 32.0, 64.0) if is_finite(bubble_diameter) else 46.0


func _font_size() -> int:
	return clampi(amount_font_size, 10, 24)


func _relayout() -> void:
	_rects.clear()
	_content_size = Vector2.ZERO
	var diameter := _diameter()
	var gap := clampf(bubble_gap, 0.0, 16.0) if is_finite(bubble_gap) else 5.0
	var max_columns := clampi(columns, 1, 6)
	var row_height := diameter + maxf(4.0, _font().get_height(_font_size()) + 2.0 - 14.0)
	var x := 2.0
	var y := 2.0
	for index in _tokens.size():
		var text := String(_tokens[index].amount_text)
		var width := maxf(diameter, _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x + 10.0)
		_rects.append(Rect2(Vector2(x, y), Vector2(width, row_height)))
		x += width + gap
		if (index + 1) % max_columns == 0 or index == _tokens.size() - 1:
			_content_size.x = maxf(_content_size.x, x - gap + 2.0)
			x = 2.0
			y += row_height + gap
	if not _tokens.is_empty(): _content_size.y = y - gap + 2.0
	for start in range(0, _rects.size(), max_columns):
		var end := mini(start + max_columns - 1, _rects.size() - 1)
		var row_width := _rects[end].end.x - _rects[start].position.x
		var offset := (_content_size.x - 4.0 - row_width) * 0.5
		for index in range(start, end + 1): _rects[index].position.x += offset
	custom_minimum_size = _content_size
	size = _content_size
	update_minimum_size()


func _draw() -> void:
	for index in mini(_tokens.size(), _rects.size()):
		_draw_token(_tokens[index], _rects[index], index)


func _draw_token(token: Dictionary, rect: Rect2, _index: int) -> void:
	var diameter := _diameter()
	var radius := diameter * 0.5
	var center := rect.position + Vector2(rect.size.x * 0.5, radius)
	var fill := Color("ffe5a2")
	var edge := Color("bb9458")
	if token.kind == &"ready_item":
		fill = Color("c9edaf")
		edge = Color("83ab62")
	elif token.kind == &"addition":
		# Ingredient identity retains its palette when another addition is absent.
		var palette_index := posmod(String(token.item_id).hash(), 3)
		fill = [Color("f5d6ba"), Color("d5e8ef"), Color("e3ddf2")][palette_index]
		edge = [Color("ba9d83"), Color("91b3c0"), Color("aaa0be")][palette_index]
	draw_circle(center + Vector2(0, 2), radius, Color(0.30, 0.23, 0.13, 0.12), true, -1.0, true)
	draw_circle(center, radius, edge, true, -1.0, true)
	for ring in range(12):
		var amount := float(ring) / 11.0
		draw_circle(center + Vector2(0.0, -amount * radius * 0.15), (radius - 1.5) * (1.0 - amount * 0.64), fill.lightened(amount * 0.15), true, -1.0, true)
	var texture := token.get("icon") as Texture2D
	var icon_center := center + Vector2(-3.0, -1.0) if token.kind == &"tea" else center
	if texture != null:
		_draw_fitted(texture, icon_center, Vector2.ONE * diameter * 0.73)
	else:
		_draw_initials(String(token.item_id), center, diameter)
	if token.kind == &"tea":
		var small_center := center + Vector2(radius * 0.47, radius * 0.37)
		var small_radius := diameter * 0.21
		draw_circle(small_center, small_radius + 1.0, edge, true, -1.0, true)
		draw_circle(small_center, small_radius, Color("fff6d9"), true, -1.0, true)
		var identity := token.get("identity_icon") as Texture2D
		if identity != null:
			_draw_fitted(identity, small_center, Vector2.ONE * small_radius * 1.76)
		else:
			_draw_initials(String(token.item_id), small_center, small_radius * 2.0)
	elif not String(token.amount_text).is_empty():
		_draw_amount(String(token.amount_text), rect, diameter)


func _draw_fitted(texture: Texture2D, center: Vector2, available: Vector2) -> void:
	var native := texture.get_size()
	if native.x <= 0.0 or native.y <= 0.0: return
	var fitted := native * minf(available.x / native.x, available.y / native.y)
	draw_texture_rect(texture, Rect2(center - fitted * 0.5, fitted), false)


func _draw_initials(item_id: String, center: Vector2, diameter: float) -> void:
	var words := item_id.replace("_", " ").split(" ", false)
	var initials := "?"
	if not words.is_empty():
		initials = words[0].left(2).to_upper() if words.size() == 1 else (words[0].left(1) + words[1].left(1)).to_upper()
	var text_size := clampi(int(diameter * 0.31), 8, 19)
	var width := _font().get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_string(_font(), center + Vector2(-width * 0.5, _font().get_ascent(text_size) - _font().get_height(text_size) * 0.5), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color("6a5337"))


func _draw_amount(text: String, rect: Rect2, diameter: float) -> void:
	var text_width := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	var height := maxf(18.0, _font().get_height(_font_size()) + 2.0)
	var width := maxf(20.0, text_width + 8.0)
	var box := Rect2(Vector2(rect.end.x - width, rect.position.y + diameter - 14.0), Vector2(width, height))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff8e7")
	style.border_color = Color("aa8b62")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	draw_style_box(style, box)
	var baseline := box.position + Vector2((width - text_width) * 0.5, (height - _font().get_height(_font_size())) * 0.5 + _font().get_ascent(_font_size()))
	draw_string(_font(), baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(), Color("58432b"))


static func _item(catalog: Node, item_id: StringName) -> ItemDef:
	return OrderRequestDef.lookup(catalog, "items", item_id) as ItemDef


static func _item_label(catalog: Node, item_id: StringName) -> String:
	var item := _item(catalog, item_id)
	return item.get_portion_label() if item != null else String(item_id).replace("_", " ").capitalize()


static func _unit_label(unit: StringName, amount: int) -> String:
	return String(unit) + ("" if amount == 1 else "s")


static func _token(key: StringName, kind: StringName, item_id: StringName, label: String, icon: Texture2D, amount: int, unit: StringName) -> Dictionary:
	return {"key": key, "kind": kind, "item_id": item_id, "label": label, "icon": icon,
		"amount": amount, "unit": unit, "amount_text": str(amount),
		"description": "%s: %s %s" % [label, amount, _unit_label(unit, amount)]}
