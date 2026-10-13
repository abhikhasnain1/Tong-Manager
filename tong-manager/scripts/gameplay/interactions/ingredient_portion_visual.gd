class_name IngredientPortionVisual
extends Node2D

# Temporary interaction artwork. Its origin is the portion drop probe.
var item_id: StringName
var unit: StringName
var definition: ItemDef

func _init(p_item_id: StringName = &"", p_unit: StringName = &"teabag") -> void:
	item_id = p_item_id
	unit = p_unit
	z_index = 5

func _ready() -> void:
	var catalog := get_node_or_null("/root/Catalog")
	definition = catalog.get_portion_item(item_id) if catalog != null else null
	queue_redraw()

func presentation_style() -> String:
	if definition != null:
		return definition.get_portion_visual()
	return "teabag" if unit == &"teabag" else ("spoon" if unit == &"spoonful" else "icon")

func _draw() -> void:
	var outline := Color("302820")
	var style := presentation_style()
	if style in ["banana", "biscuit"]:
		_draw_ready_item(outline, style)
	elif style == "teabag":
		var bag := PackedVector2Array([Vector2(-11,-9),Vector2(-7,-15),Vector2(7,-15),Vector2(11,-9),Vector2(11,13),Vector2(-11,13)])
		draw_colored_polygon(bag,Color("e4d2a4"))
		var border := bag.duplicate()
		border.append(bag[0])
		draw_polyline(border,outline,2,true)
		draw_line(Vector2(0,-15),Vector2(15,-28),Color("f1e6cb"),2,true)
		draw_rect(Rect2(12,-34,12,10),Color("ae4c37"))
		draw_circle(Vector2(0,3),4,Color("927140"))
	elif style == "spoon":
		draw_line(Vector2(-2,-2),Vector2(17,27),outline,9,true)
		draw_line(Vector2(-2,-2),Vector2(17,27),Color("b8c3c7"),5,true)
		draw_set_transform(Vector2(-4,-8),-.35,Vector2(.8,1.1))
		draw_circle(Vector2.ZERO,12,outline)
		draw_circle(Vector2.ZERO,10,Color("bec9ca"))
		draw_circle(Vector2.ZERO,7.5,definition.portion_color if definition != null else Color("fff9ee"))
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_icon(outline)

func _draw_icon(outline: Color) -> void:
	if definition != null and definition.icon != null:
		var dimensions := definition.icon.get_size()
		if dimensions.x > 0 and dimensions.y > 0:
			var fitted := dimensions * minf(48.0 / dimensions.x, 48.0 / dimensions.y)
			draw_texture_rect(definition.icon, Rect2(-fitted * 0.5, fitted), false)
			return
	# Missing artwork stays neutral; it must not impersonate another item.
	draw_circle(Vector2.ZERO, 19, outline)
	draw_circle(Vector2.ZERO, 17, definition.portion_color if definition != null else Color("f0e4c8"))
	var label := definition.get_portion_label() if definition != null else String(item_id).capitalize()
	draw_string(ThemeDB.fallback_font, Vector2(-16, 5), label.substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, 32, 14, outline)

func _draw_ready_item(outline: Color, style: String) -> void:
	if style == "banana":
		# Separate temporary piece; the hanging bunch artwork stays on its pin.
		var crescent := PackedVector2Array([
			Vector2(-24,-14),Vector2(-23,0),Vector2(-16,14),Vector2(-3,23),
			Vector2(12,22),Vector2(24,12),Vector2(29,-4),Vector2(25,-10),
			Vector2(20,1),Vector2(11,8),Vector2(0,9),Vector2(-11,4),Vector2(-19,-7),
		])
		draw_colored_polygon(crescent,Color("e8bb43"))
		var border := crescent.duplicate()
		border.append(crescent[0])
		draw_polyline(border,outline,2,true)
		draw_polyline(PackedVector2Array([Vector2(-21,-2),Vector2(-12,13),Vector2(2,18),Vector2(16,14),Vector2(25,1)]),Color("ffdf79"),3,true)
		draw_line(Vector2(-24,-14),Vector2(-26,-19),outline,4,true)
		draw_line(Vector2(25,-10),Vector2(29,-11),outline,4,true)
	else:
		draw_set_transform(Vector2.ZERO,-0.16,Vector2(1.2,0.85))
		draw_circle(Vector2.ZERO,23,outline)
		draw_circle(Vector2.ZERO,21,Color("b87839"))
		draw_circle(Vector2.ZERO,18,Color("dfb46a"))
		for point in [Vector2(-8,-8),Vector2(4,-10),Vector2(11,0),Vector2(4,10),Vector2(-9,8),Vector2(-2,0)]:
			draw_circle(point,1.7,Color("926033"))
		draw_set_transform(Vector2.ZERO)
