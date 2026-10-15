class_name CupReturnBadge
extends Node2D
## A light icon backing; the original reusable cup is drawn above it.

var radius := 48.0


func configure(cup: Cup) -> void:
	var sprite := cup.cup_sprite
	var rect := sprite.transform * sprite.get_rect()
	var next_radius := maxf(rect.size.x, rect.size.y) / 1.44
	# A cup may retain the tray's perspective stretch; its icon stays round.
	var icon_scale := maxf(cup.global_transform.x.length(), cup.global_transform.y.length())
	global_transform = Transform2D(0.0, Vector2.ONE * icon_scale, 0.0, cup.to_global(rect.get_center()))
	z_as_relative = cup.z_as_relative
	z_index = cup.z_index - 1
	if not is_equal_approx(radius, next_radius):
		radius = next_radius
		queue_redraw()


func contains_pointer(point: Vector2) -> bool:
	if not is_visible_in_tree(): return false
	var projection := get_global_transform_with_canvas()
	if is_zero_approx(projection.determinant()): return false
	return (projection.affine_inverse() * point).length_squared() <= radius * radius


func _draw() -> void:
	draw_circle(Vector2(0, 2), radius, Color(0.3, 0.23, 0.13, 0.12), true, -1.0, true)
	draw_circle(Vector2.ZERO, radius, Color("c5b48c"), true, -1.0, true)
	for ring in range(12):
		var amount := float(ring) / 11.0
		draw_circle(Vector2(0, -amount * radius * 0.15), (radius - 1.5) * (1.0 - amount * 0.64),
			Color("fff0ca").lightened(amount * 0.15), true, -1.0, true)
