class_name IngredientPortionVisual
extends Node2D

# Temporary interaction artwork. Its origin is the portion drop probe.
var item_id: StringName
var unit: StringName

func _init(p_item_id: StringName = &"", p_unit: StringName = &"teabag") -> void:
	item_id = p_item_id
	unit = p_unit
	z_index = 5

func _draw() -> void:
	var outline := Color("302820")
	if unit == &"teabag":
		var bag := PackedVector2Array([Vector2(-11,-9),Vector2(-7,-15),Vector2(7,-15),Vector2(11,-9),Vector2(11,13),Vector2(-11,13)])
		draw_colored_polygon(bag,Color("e4d2a4"))
		var border := bag.duplicate()
		border.append(bag[0])
		draw_polyline(border,outline,2,true)
		draw_line(Vector2(0,-15),Vector2(15,-28),Color("f1e6cb"),2,true)
		draw_rect(Rect2(12,-34,12,10),Color("ae4c37"))
		draw_circle(Vector2(0,3),4,Color("927140"))
	else:
		draw_line(Vector2(-2,-2),Vector2(17,27),outline,9,true)
		draw_line(Vector2(-2,-2),Vector2(17,27),Color("b8c3c7"),5,true)
		draw_set_transform(Vector2(-4,-8),-.35,Vector2(.8,1.1))
		draw_circle(Vector2.ZERO,12,outline)
		draw_circle(Vector2.ZERO,10,Color("bec9ca"))
		draw_circle(Vector2.ZERO,7.5,Color("f5e1a8") if item_id == &"condensed_milk" else Color("fff9ee"))
		draw_set_transform(Vector2.ZERO)
