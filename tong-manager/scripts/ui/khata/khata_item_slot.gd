class_name KhataItemSlot
extends Control
## A paper inventory cell. The containing notebook owns all input and commands.

const INK := Color("493d30")
const SOFT_INK := Color("85735d")
const BORDER := Color("9b8766")
var item_id: StringName = &""
var item_label := ""
var unit: StringName = &""
var icon: Texture2D
var remaining := 0
var available := 0
var stock_bound := false
var hovered := false
var interaction_enabled := true
var _font: Font = ThemeDB.fallback_font
var _title_font := SystemFont.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_title_font.font_names = PackedStringArray(["Georgia", "Noto Serif", "serif"])


func configure(id: StringName, label: String, portion_unit: StringName, texture: Texture2D) -> void:
	item_id = id
	item_label = label
	unit = portion_unit
	icon = texture
	queue_redraw()


func set_stock(total: int, free: int, bound: bool) -> bool:
	total = maxi(total, 0)
	free = clampi(free, 0, total)
	if remaining == total and available == free and stock_bound == bound:
		return false
	remaining = total
	available = free
	stock_bound = bound
	queue_redraw()
	return true


func set_hovered(value: bool) -> bool:
	if hovered == value:
		return false
	hovered = value
	queue_redraw()
	return true


func set_interaction_enabled(value: bool) -> bool:
	if interaction_enabled == value:
		return false
	interaction_enabled = value
	queue_redraw()
	return true


func display_snapshot() -> Dictionary:
	return {
		"item_id": item_id, "label": item_label, "unit": unit,
		"remaining": remaining, "available": available, "stock_bound": stock_bound,
		"status": _status_text(), "hovered": hovered,
		"interaction_enabled": interaction_enabled,
	}


func _status_text() -> String:
	if not stock_bound:
		return "Unavailable"
	if remaining == 0:
		return "Out of stock"
	if available < remaining:
		return "%d held" % (remaining - available)
	return ""


func _plural_unit() -> String:
	if remaining == 1:
		return String(unit)
	match unit:
		&"teabag": return "teabags"
		&"spoonful": return "spoonfuls"
		&"piece": return "pieces"
	return String(unit)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var usable := stock_bound and available > 0 and interaction_enabled
	var tint := Color("8fa174") if hovered and usable else Color("f4ead2")
	tint.a = 0.19 if hovered and usable else 0.48
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), tint)
	var border := INK if hovered and interaction_enabled else BORDER
	var outline := PackedVector2Array([
		Vector2(2, 4), Vector2(size.x * 0.49, 2), Vector2(size.x - 3, 4),
		Vector2(size.x - 2, size.y * 0.53), Vector2(size.x - 4, size.y - 3),
		Vector2(size.x * 0.47, size.y - 2), Vector2(3, size.y - 4), Vector2(2, 4),
	])
	draw_polyline(outline, border, 1.6 if hovered else 1.1, true)
	if icon != null:
		var icon_size := icon.get_size()
		if icon_size.x > 0.0 and icon_size.y > 0.0:
			var draw_size := icon_size * minf(60.0 / icon_size.x, 49.0 / icon_size.y)
			var icon_color := Color.WHITE
			if not stock_bound or remaining == 0:
				icon_color.a = 0.42
			draw_texture_rect(icon, Rect2(Vector2((size.x - draw_size.x) * 0.5, 12), draw_size), false, icon_color)
	draw_string(_title_font, Vector2(5, 81), item_label, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 19, INK)
	var quantity := str(remaining) if stock_bound else "—"
	var quantity_font_size := 25
	while quantity_font_size > 13 and _title_font.get_string_size(quantity, HORIZONTAL_ALIGNMENT_LEFT, -1, quantity_font_size).x > size.x - 12:
		quantity_font_size -= 1
	draw_string(_title_font, Vector2(6, 109), quantity, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12, quantity_font_size, INK)
	draw_string(_font, Vector2(4, 128), _plural_unit(), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 16, SOFT_INK)
	draw_string(_font, Vector2(4, 146), _status_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 14, SOFT_INK)
