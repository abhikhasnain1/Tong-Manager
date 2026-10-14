class_name CustomerPresentation
extends Resource
## Visual settings only. Order matching, patience and money belong to consumers.

@export var canvas_size := Vector2(280.0, 360.0)
@export_range(0.1, 5.0, 0.05) var total_duration := 1.15
@export_range(0.0, 1.0, 0.01) var turn_max_seconds := 0.42
@export_range(0.0, 0.8, 0.01) var turn_fraction := 0.30
@export_range(0.1, 1.0, 0.01) var far_scale := 0.84
@export_range(0.0, 0.3, 0.005) var travel_distance_ratio := 0.08
@export_range(0.0, 0.05, 0.001) var bob_height_ratio := 0.011
@export_range(0, 5, 1) var bob_cycles := 2
@export_range(0.0, 8.0, 0.25) var outline_width := 2.5
@export var outline_color := Color("f4d77e")
@export_range(20.0, 64.0, 1.0) var bubble_size := 44.0
@export var bubble_position := Vector2(86.0, -340.0)
@export var dialogue_position := Vector2(0.0, -192.0)
@export_range(11, 28, 1) var dialogue_font_size := 17
@export var font: Font
## Optional custom turn art. Four regions: quarter, profile, rear-quarter, back.
## Each region is cropped to the pose, centered horizontally and fit by height.
@export var turn_sheet: Texture2D
@export var turn_regions: Array[Rect2] = []


func safe_canvas_size() -> Vector2:
	if not canvas_size.is_finite(): return Vector2(280.0, 360.0)
	return Vector2(maxf(40.0, canvas_size.x), maxf(40.0, canvas_size.y))


func safe_duration() -> float:
	return maxf(0.01, total_duration) if is_finite(total_duration) else 1.15
