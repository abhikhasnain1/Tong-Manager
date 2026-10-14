class_name CustomerFeedback
extends Node2D
## One compact, pointer-transparent head-corner cue. No recipe evaluator.

var size := 44.0
var emotion: StringName = &""
var order_icon: Texture2D
var green_palette := false


func configure(diameter: float, value: StringName, icon: Texture2D, green: bool) -> void:
	size = maxf(20.0, diameter)
	emotion = value
	order_icon = icon
	green_palette = green
	queue_redraw()


func _draw() -> void:
	var radius := size * 0.5
	var fill := Color("ffe5a2")
	var edge := Color("bb9458")
	var ink := Color("78511e")
	if green_palette and emotion.is_empty():
		fill = Color("c9edaf"); edge = Color("83ab62"); ink = Color("405f2b")
	if emotion in [&"cold", &"unhappy"]:
		fill = Color("bceaf5"); edge = Color("6eafc4"); ink = Color("285e72")
	elif emotion == &"wrong":
		fill = Color("ffd0ba"); edge = Color("c68b71"); ink = Color("814d32")
	draw_circle(Vector2.ZERO, radius, edge, true, -1.0, true)
	for ring in range(12):
		var amount := float(ring) / 11.0
		draw_circle(Vector2(0.0, -amount * radius * 0.15), (radius - 1.5) * (1.0 - amount * 0.64), fill.lightened(amount * 0.15), true, -1.0, true)
	if emotion.is_empty() and order_icon != null:
		var available := Vector2.ONE * size * 0.72
		var texture_size := order_icon.get_size()
		var fitted := texture_size * minf(available.x / texture_size.x, available.y / texture_size.y)
		draw_texture_rect(order_icon, Rect2(-fitted * 0.5, fitted), false)
	elif emotion == &"wrong":
		draw_arc(Vector2.ZERO, radius * 0.43, -PI * 0.35, PI * 1.20, 24, ink, 2.3, true)
		draw_polyline(PackedVector2Array([Vector2(-radius * 0.55, -radius * 0.02), Vector2(-radius * 0.36, -radius * 0.34), Vector2(-radius * 0.05, -radius * 0.19)]), ink, 2.3, true)
	elif emotion in [&"cold", &"unhappy"]:
		_face(Vector2(0.0, -radius * 0.24), radius * 0.43, false, ink)
		if emotion == &"cold":
			var center := Vector2(0.0, radius * 0.48)
			for spoke in range(3):
				var direction := Vector2.from_angle(float(spoke) * PI / 3.0) * radius * 0.22
				draw_line(center - direction, center + direction, ink, 1.8, true)
	else:
		_face(Vector2.ZERO, radius * 0.65, true, ink)


func _face(center: Vector2, radius: float, happy: bool, ink: Color) -> void:
	draw_circle(center, radius, ink, false, 1.8, true)
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.23), 1.4, ink, true, -1.0, true)
	draw_circle(center + Vector2(radius * 0.32, -radius * 0.23), 1.4, ink, true, -1.0, true)
	var mouth := center + Vector2(0.0, radius * (0.06 if happy else 0.55))
	draw_arc(mouth, radius * 0.42, 0.15 if happy else PI + 0.15, PI - 0.15 if happy else TAU - 0.15, 16, ink, 1.8, true)
