extends Node2D

const AUTHORED_SIZE := Vector2(1920.0, 1080.0)
const CROP_SAFE_RECT := Rect2(96.0, 0.0, 1728.0, 1080.0)

@export var tool_def: Resource
@export var day_config: Resource

@onready var world_root: Node2D = %WorldRoot
@onready var composition_guides: Node2D = %CompositionGuides
@onready var cursor_service: Node = get_node("/root/CursorService")
@onready var table_surface: PlacementSurface = $WorldRoot/DropZoneRoot/TablePlacementSurface


func _ready() -> void:
	get_viewport().physics_object_picking_sort = true
	get_viewport().size_changed.connect(_fit_authored_world)
	var interaction := $InteractionController as InteractionController
	var hud := $HUDLayer/RootUI as TongHud
	interaction.mode_changed.connect(hud.set_mode)
	hud.set_mode(interaction.current_mode)
	cursor_service.bind_hover_target($WorldRoot/ToolLayer/KhataStation/KhataHotspot)
	_fit_authored_world()
	_configure_table_placement()
	_verify_layout_contract()


func set_composition_guides_visible(is_visible: bool) -> void:
	composition_guides.visible = is_visible


func _fit_authored_world() -> void:
	var interaction := get_node_or_null("InteractionController") as InteractionController
	if is_instance_valid(interaction) and interaction.is_dragging():
		interaction.cancel_drag()
	var viewport_size := get_viewport().get_visible_rect().size
	var cover_scale := maxf(viewport_size.x / AUTHORED_SIZE.x, viewport_size.y / AUTHORED_SIZE.y)
	world_root.scale = Vector2.ONE * cover_scale
	world_root.position = (viewport_size - AUTHORED_SIZE * cover_scale) * 0.5


func _configure_table_placement() -> void:
	for node in get_tree().get_nodes_in_group(&"table_placeables"):
		if is_ancestor_of(node):
			var handle := node as TablePlaceable
			var configured := handle.configure(table_surface, $InteractionController)
			assert(configured,
				"Invalid initial table placement: %s" % handle.get_parent().name)


func _verify_layout_contract() -> void:
	assert(tool_def != null, "TongDayScreen requires a ToolDef resource.")
	assert(day_config != null, "TongDayScreen requires a DayConfig resource.")
	assert(tool_def.tray_capacity > 0, "Tray capacity must be positive.")
	assert(
		tool_def.tray_capacity <= tool_def.tray_grid_size.x * tool_def.tray_grid_size.y,
		"Tray capacity cannot exceed its internal grid."
	)
	var tray_station := $WorldRoot/ToolLayer/TrayStation as TrayStation
	assert(tray_station != null, "TongDayScreen requires the functional TrayStation scene.")
	assert(tray_station.get_cup_count() == tool_def.tray_capacity, "Tray cup count must follow ToolDef.")
	assert(
		tray_station.get_slot_count() == tool_def.tray_grid_size.x * tool_def.tray_grid_size.y,
		"Tray slot count must follow ToolDef."
	)
	assert(table_surface.is_registered(tray_station), "Tray requires a committed table footprint.")
	assert(tool_def.burner_count == 2, "The demo stove exposes two configurable burners.")
	for marker in get_tree().get_nodes_in_group("critical_interaction_anchor"):
		var authored_position := world_root.to_local(marker.global_position)
		assert(
			CROP_SAFE_RECT.has_point(authored_position),
			"%s at %s is outside the 16:10 crop-safe area." % [marker.get_path(), authored_position]
		)
