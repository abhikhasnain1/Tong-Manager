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
	var tray := $WorldRoot/ToolLayer/TrayStation as TrayStation
	for node in get_tree().get_nodes_in_group(&"table_placeables"):
		if is_ancestor_of(node):
			var handle := node as TablePlaceable
			if handle.item is Cup:
				continue
			var configured := handle.configure(table_surface, $InteractionController)
			assert(configured,
				"Invalid initial table placement: %s" % handle.get_parent().name)
			if handle.item != tray:
				handle.set_available_surfaces([table_surface, tray.interior_surface])
	for cup in get_cups():
		var configured := configure_cup(cup)
		assert(configured, "Invalid initial cup placement: %s" % cup.name)


func get_cups() -> Array[Cup]:
	var result: Array[Cup] = []
	for node in get_tree().get_nodes_in_group(&"cups"):
		if node is Cup and is_ancestor_of(node) and not node.is_queued_for_deletion():
			result.append(node)
	return result


func configure_cup(cup: Cup) -> bool:
	if (not is_instance_valid(cup) or not is_ancestor_of(cup) or cup.is_queued_for_deletion()
		or not is_instance_valid(table_surface)):
		return false
	var tray := $WorldRoot/ToolLayer/TrayStation as TrayStation
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle == null:
		return false
	# Reconfiguration must not overwrite ownership during a drag or transfer.
	if not is_instance_valid(handle.surface) or not handle.surface.is_registered(cup):
		var initial := tray.interior_surface if cup.get_parent() == tray.get_contents() else table_surface
		if not handle.configure(initial, $InteractionController):
			return false
		cup.capacity_ml = float(tool_def.cup_volume_ml)
	handle.set_available_surfaces([table_surface, tray.interior_surface])
	cup.bind_controller($InteractionController)
	return true


func _verify_layout_contract() -> void:
	assert(tool_def != null, "TongDayScreen requires a ToolDef resource.")
	assert(day_config != null, "TongDayScreen requires a DayConfig resource.")
	assert(tool_def.starting_cup_count >= 0, "Starting cup supply cannot be negative.")
	var tray_station := $WorldRoot/ToolLayer/TrayStation as TrayStation
	assert(tray_station != null, "TongDayScreen requires the functional TrayStation scene.")
	assert(get_cups().size() == tool_def.starting_cup_count, "Starting cup supply must follow ToolDef.")
	assert(table_surface.is_registered(tray_station), "Tray requires a committed table footprint.")
	assert(tool_def.burner_count == 2, "The demo stove exposes two configurable burners.")
	for marker in get_tree().get_nodes_in_group("critical_interaction_anchor"):
		var authored_position := world_root.to_local(marker.global_position)
		assert(
			CROP_SAFE_RECT.has_point(authored_position),
			"%s at %s is outside the 16:10 crop-safe area." % [marker.get_path(), authored_position]
		)
