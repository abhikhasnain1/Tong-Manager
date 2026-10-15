class_name Burner
extends Node2D

signal heat_changed(level: int)

@export var config: BrewingConfig = preload("res://data/balance/brewing_level_1.tres")
# Optional presentation only. The normal scene keeps its existing flame drawing.
var flame_art: Texture2D:
	set(value):
		flame_art = value
		queue_redraw()
var heat_level := 0
var seated_kettle: Kettle
var controller: InteractionController
var _flame_time := 0.0

func can_seat(kettle: Kettle) -> bool:
	return is_instance_valid(kettle) and not kettle.is_pouring and (not is_instance_valid(seated_kettle) or seated_kettle == kettle)

func seat(kettle: Kettle) -> bool:
	if not can_seat(kettle):
		return false
	if is_instance_valid(kettle.current_burner) and kettle.current_burner != self:
		kettle.current_burner.call("release", kettle)
	seated_kettle = kettle
	kettle.current_burner = self
	var tool_layer := get_parent().get_parent()
	if kettle.get_parent() != tool_layer:
		kettle.reparent(tool_layer, true)
	kettle.global_position = to_global(Vector2(-25.0, -107.0))
	kettle.finish_seating()
	return true

func release(kettle: Kettle) -> void:
	if seated_kettle == kettle:
		seated_kettle = null
	if is_instance_valid(kettle) and kettle.current_burner == self:
		kettle.current_burner = null

func set_heat(level: int) -> void:
	heat_level = clampi(level, 0, mini(3, config.heat_levels.size() - 1))
	heat_changed.emit(heat_level)
	queue_redraw()

func _process(delta: float) -> void:
	if flame_art != null and heat_level > 0:
		_flame_time += delta
		queue_redraw()
	if is_instance_valid(seated_kettle) and seated_kettle.current_burner == self:
		seated_kettle.apply_heat(delta, config.heat_levels[heat_level])
	else:
		seated_kettle = null

func _draw() -> void:
	if heat_level == 0:
		return
	if flame_art != null:
		_draw_flame_art()
		return
	var flame_color := [Color.TRANSPARENT, Color(.25,.65,1,.8), Color(1,.65,.15,.85), Color(1,.35,.08,.95)][heat_level] as Color
	for i in 14:
		var angle := TAU * i / 14.0
		var base := Vector2(cos(angle) * 100.0, sin(angle) * 55.0)
		var top := base + Vector2(2, -6 - heat_level * 5)
		draw_colored_polygon(PackedVector2Array([base-Vector2(3,0),top,base+Vector2(3,0)]),flame_color)


func _draw_flame_art() -> void:
	# Regions from the existing three-flame sheet, ordered low to high heat.
	var regions: Array[Rect2] = [Rect2(1145, 190, 216, 270), Rect2(590, 130, 290, 380), Rect2(0, 0, 420, 520)]
	var region := regions[clampi(heat_level - 1, 0, 2)]
	var height := [22.0, 33.0, 46.0][clampi(heat_level - 1, 0, 2)] as float
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var base := Vector2(cos(angle) * 100.0, sin(angle) * 55.0)
		var flicker := 1.0 + sin(_flame_time * 7.0 + float(i) * 1.7) * 0.06
		var size := Vector2(height * region.size.x / region.size.y, height * flicker)
		draw_texture_rect_region(flame_art, Rect2(base - Vector2(size.x * 0.5, size.y), size), region)
