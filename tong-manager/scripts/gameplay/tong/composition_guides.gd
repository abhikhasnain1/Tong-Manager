extends Node2D

const SAFE_RECT := Rect2(96.0, 0.0, 1728.0, 1080.0)
const CUSTOMER_ZONE := Rect2(270.0, 150.0, 1320.0, 570.0)
const TOOL_ZONE := Rect2(40.0, 690.0, 1840.0, 385.0)
const TRAY_ZONE := Rect2(850.0, 735.0, 725.0, 300.0)


func _draw() -> void:
	draw_rect(SAFE_RECT, Color(0.2, 0.9, 1.0, 0.85), false, 3.0)
	draw_rect(CUSTOMER_ZONE, Color(0.9, 0.4, 1.0, 0.8), false, 3.0)
	draw_rect(TOOL_ZONE, Color(1.0, 0.72, 0.2, 0.8), false, 3.0)
	draw_rect(TRAY_ZONE, Color(0.3, 1.0, 0.45, 0.9), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(110.0, 34.0), "16:10 crop-safe boundary", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.2, 0.9, 1.0))
	draw_string(ThemeDB.fallback_font, CUSTOMER_ZONE.position + Vector2(8.0, 28.0), "customer lane", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.9, 0.4, 1.0))
	draw_string(ThemeDB.fallback_font, TOOL_ZONE.position + Vector2(8.0, 30.0), "workstation", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(1.0, 0.72, 0.2))
	draw_string(ThemeDB.fallback_font, TRAY_ZONE.position + Vector2(8.0, 28.0), "tray 3x2 / polygon table occupancy", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.3, 1.0, 0.45))
