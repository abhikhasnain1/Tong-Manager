extends Node2D

const AUTHORED_SIZE := Vector2(1920.0, 1080.0)
const CROP_SAFE_RECT := Rect2(96.0, 0.0, 1728.0, 1080.0)

@export var tool_def: Resource
@export var day_config: Resource

@onready var world_root: Node2D = %WorldRoot
@onready var composition_guides: Node2D = %CompositionGuides
@onready var cursor_service: Node = get_node("/root/CursorService")


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_authored_world)
	cursor_service.bind_hover_target($WorldRoot/ToolLayer/KhataStation/KhataHotspot)
	_fit_authored_world()
	_verify_layout_contract()


func set_composition_guides_visible(is_visible: bool) -> void:
	composition_guides.visible = is_visible


func _fit_authored_world() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cover_scale := maxf(viewport_size.x / AUTHORED_SIZE.x, viewport_size.y / AUTHORED_SIZE.y)
	world_root.scale = Vector2.ONE * cover_scale
	world_root.position = (viewport_size - AUTHORED_SIZE * cover_scale) * 0.5


func _verify_layout_contract() -> void:
	assert(tool_def != null, "TongDayScreen requires a ToolDef resource.")
	assert(day_config != null, "TongDayScreen requires a DayConfig resource.")
	assert(tool_def.tray_capacity > 0, "Tray capacity must be positive.")
	assert(
		tool_def.tray_capacity <= tool_def.tray_grid_size.x * tool_def.tray_grid_size.y,
		"Tray capacity cannot exceed its internal grid."
	)
	assert(
		tool_def.tray_table_footprint.x > 0 and tool_def.tray_table_footprint.y > 0,
		"Tray table footprint must be positive."
	)
	var tray_station := $WorldRoot/ToolLayer/TrayStation as TrayStation
	assert(tray_station != null, "TongDayScreen requires the functional TrayStation scene.")
	assert(tray_station.get_cup_count() == tool_def.tray_capacity, "Tray cup count must follow ToolDef.")
	assert(
		tray_station.get_slot_count() == tool_def.tray_grid_size.x * tool_def.tray_grid_size.y,
		"Tray slot count must follow ToolDef."
	)
	assert(
		tray_station.get_committed_table_cells().size()
		== tool_def.tray_table_footprint.x * tool_def.tray_table_footprint.y,
		"Tray reservation must match its ToolDef table footprint."
	)
	assert(tool_def.burner_count == 2, "The demo stove exposes two configurable burners.")
	for marker in get_tree().get_nodes_in_group("critical_interaction_anchor"):
		var authored_position := world_root.to_local(marker.global_position)
		assert(
			CROP_SAFE_RECT.has_point(authored_position),
			"%s at %s is outside the 16:10 crop-safe area." % [marker.get_path(), authored_position]
		)
