class_name TrayStation
extends Node2D

signal cup_occupancy_changed
signal table_placement_committed(cell: Vector2i, cells: Array[Vector2i])

const TABLE_CATEGORY := &"tray_station"
const CUP_CATEGORY := &"cup"
const SMALL_ITEM_CATEGORY := &"small_item"
const RESERVATION_ID := &"tray_station"
const INVALID_CELL := Vector2i(-1, -1)
const ORGANIZE_GHOST_ALPHA := 0.42

@export var tool_def: Resource
@export var cup_scene: PackedScene
@export_node_path("Node") var interaction_controller_path: NodePath
@export_node_path("Node2D") var table_grid_path: NodePath

@onready var tray_body: Area2D = $TrayBody
@onready var interaction_anchor: Marker2D = $InteractionAnchor
@onready var table_placement_anchor: Marker2D = $TablePlacementAnchor
@onready var internal_grid: TrayGrid = $InternalGrid
@onready var cup_slots: Node2D = $CupSlots
@onready var cups: Node2D = $Cups
@onready var table_drop_zone: TrayTableDropZone = $TableDropZone
@onready var internal_drop_zone: TrayInternalDropZone = $InternalDropZone

var _interaction_controller: InteractionController
var _table_grid: TableGrid
var _table_footprint := PlaceableFootprint.new()
var _slot_occupants: Dictionary = {}
var _home_parent: Node
var _committed_cell := INVALID_CELL


func _ready() -> void:
	_interaction_controller = get_node_or_null(interaction_controller_path) as InteractionController
	_table_grid = get_node_or_null(table_grid_path) as TableGrid
	assert(tool_def != null, "TrayStation requires a tool definition.")
	assert(cup_scene != null, "TrayStation requires a Cup scene.")
	assert(_interaction_controller != null, "TrayStation requires an InteractionController.")
	assert(_table_grid != null, "TrayStation requires a TableGrid.")
	assert(tool_def.tray_grid_size.x > 0 and tool_def.tray_grid_size.y > 0, "Tray grid size must be positive.")
	assert(tool_def.tray_table_footprint.x > 0 and tool_def.tray_table_footprint.y > 0, "Tray table footprint must be positive.")
	assert(tool_def.tray_capacity > 0, "Tray capacity must be positive.")
	assert(
		tool_def.tray_capacity <= tool_def.tray_grid_size.x * tool_def.tray_grid_size.y,
		"Tray capacity cannot exceed its internal grid."
	)

	_home_parent = get_parent()
	_table_footprint.size = tool_def.tray_table_footprint
	internal_grid.configure(tool_def.tray_grid_size)
	_connect_interactions()
	_spawn_initial_cups()
	_reserve_initial_table_placement()
	internal_grid.set_interact_mode(_interaction_controller.current_mode == InteractionController.MODE_INTERACT)
	_update_mode_visual(_interaction_controller.current_mode)
	_register_drop_zones()


func get_available_clean_cup() -> Cup:
	for cell in _ordered_cells():
		var occupant: Variant = _slot_occupants.get(cell)
		if occupant is Cup and (occupant as Cup).state == Cup.CupState.CLEAN:
			return occupant as Cup
	return null


func consume_cup(cup: Cup) -> bool:
	if cup == null:
		return false
	var occupied_cells := _cells_for_item(cup)
	if occupied_cells.is_empty():
		return false
	_clear_item_cells(cup)
	if cup.get_parent() == cups:
		cups.remove_child(cup)
	cup_occupancy_changed.emit()
	return true


func return_clean_cup(cup: Cup) -> bool:
	if cup == null or cup.state != Cup.CupState.CLEAN or not _cells_for_item(cup).is_empty():
		return false
	for cell in _ordered_cells():
		if _slot_occupants.has(cell):
			continue
		_place_node_at_cells(cup, [cell])
		_ensure_cup_interaction(cup)
		cup_occupancy_changed.emit()
		return true
	return false


func can_place_inside(payload: HeldItemPayload, origin_cell: Vector2i) -> bool:
	if payload == null:
		return false
	var category := StringName(payload.metadata.get("category", &""))
	if category != CUP_CATEGORY and category != SMALL_ITEM_CATEGORY:
		return false
	var item := payload.world_node as Node2D
	if item == null:
		return false
	var footprint_size: Vector2i = payload.metadata.get("footprint_size", Vector2i.ONE)
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		return false
	for cell in _cells_from(origin_cell, footprint_size):
		if not internal_grid.is_cell_in_bounds(cell):
			return false
		if _slot_occupants.has(cell) and _slot_occupants[cell] != item:
			return false
	return true


func place_inside(payload: HeldItemPayload, origin_cell: Vector2i) -> bool:
	if not can_place_inside(payload, origin_cell):
		return false
	var item := payload.world_node as Node2D
	var footprint_size: Vector2i = payload.metadata.get("footprint_size", Vector2i.ONE)
	var target_cells := _cells_from(origin_cell, footprint_size)
	_clear_item_cells(item)
	_place_node_at_cells(item, target_cells)
	if item is Cup:
		_ensure_cup_interaction(item as Cup)
	cup_occupancy_changed.emit()
	return true


func commit_table_placement(origin_cell: Vector2i) -> bool:
	if not _table_grid.can_place(_table_footprint, origin_cell):
		return false
	var target_cells := _table_footprint.cells_from(origin_cell)
	if not _table_grid.reserve_cells(RESERVATION_ID, target_cells, TableGrid.STATE_TRAY_AREA):
		return false
	if get_parent() != _home_parent:
		reparent(_home_parent, true)
	_register_drop_zones()
	var target_anchor_position := _average_table_cell_position(target_cells)
	global_position += target_anchor_position - table_placement_anchor.global_position
	_committed_cell = origin_cell
	table_placement_committed.emit(_committed_cell, target_cells.duplicate())
	return true


func get_table_grid() -> TableGrid:
	return _table_grid


func get_table_footprint() -> PlaceableFootprint:
	return _table_footprint


func get_interaction_controller() -> InteractionController:
	return _interaction_controller


func get_internal_grid() -> TrayGrid:
	return internal_grid


func get_table_placement_anchor_world_position() -> Vector2:
	return table_placement_anchor.global_position


func get_committed_table_cell() -> Vector2i:
	return _committed_cell


func get_committed_table_cells() -> Array[Vector2i]:
	return _table_grid.get_cells_for_item(RESERVATION_ID)


func align_table_drag_preview(origin_cell: Vector2i) -> void:
	if not _interaction_controller.is_dragging():
		return
	if _interaction_controller.current_payload.world_node != self:
		return
	var target_cells := _table_footprint.cells_from(origin_cell)
	var target_anchor_position := _average_table_cell_position(target_cells)
	global_position += target_anchor_position - table_placement_anchor.global_position


func get_slot_count() -> int:
	return internal_grid.grid_size.x * internal_grid.grid_size.y


func get_cup_count() -> int:
	var count := 0
	for child in cups.get_children():
		if child is Cup:
			count += 1
	return count


func get_occupied_slot_count() -> int:
	return _slot_occupants.size()


func get_internal_cells_for_item(item: Node2D) -> Array[Vector2i]:
	return _cells_for_item(item)


func _connect_interactions() -> void:
	tray_body.input_event.connect(_on_tray_input_event)
	tray_body.mouse_entered.connect(_on_tray_mouse_entered)
	tray_body.mouse_exited.connect(_on_hover_exited)
	_interaction_controller.drag_canceled.connect(_on_drag_canceled)
	_interaction_controller.mode_changed.connect(_on_mode_changed)


func _spawn_initial_cups() -> void:
	for index in tool_def.tray_capacity:
		var cup := cup_scene.instantiate() as Cup
		assert(cup != null, "TrayStation cup_scene root must be Cup.")
		cup.name = "Cup%d" % index
		var cell := Vector2i(index % internal_grid.grid_size.x, index / internal_grid.grid_size.x)
		_place_node_at_cells(cup, [cell])
		_ensure_cup_interaction(cup)


func _reserve_initial_table_placement() -> void:
	var dimensions := _table_footprint.dimensions()
	var initial_cell := _table_grid.world_to_footprint_origin(
		table_placement_anchor.global_position,
		dimensions
	)
	var reserved := _table_grid.reserve_footprint(
		RESERVATION_ID,
		_table_footprint,
		initial_cell,
		0,
		TableGrid.STATE_TRAY_AREA
	)
	assert(reserved, "TrayStation initial 4x3 table reservation is invalid.")
	_committed_cell = initial_cell


func _begin_table_drag(viewport_position: Vector2) -> bool:
	if _interaction_controller.current_mode != InteractionController.MODE_ORGANIZE:
		return false
	if _interaction_controller.is_dragging():
		return false
	_table_grid.clear_item(RESERVATION_ID)
	var payload := HeldItemPayload.new(
		&"table_grid",
		RESERVATION_ID,
		1,
		self,
		{
			"category": TABLE_CATEGORY,
			"footprint_size": _table_footprint.dimensions(),
		}
	)
	if _interaction_controller.start_drag(payload, self, viewport_position):
		_register_drop_zones()
		# Reparenting this station temporarily removes its owned zones from the tree.
		# Refresh once they are registered again so the first drag frame already
		# shows—and snaps to—the complete table footprint.
		_interaction_controller.update_drag(viewport_position)
		return true
	_restore_table_reservation()
	return false


func _begin_cup_drag(cup: Cup, viewport_position: Vector2) -> bool:
	if _interaction_controller.current_mode != InteractionController.MODE_INTERACT:
		return false
	if _cells_for_item(cup).is_empty() or _interaction_controller.is_dragging():
		return false
	var payload := HeldItemPayload.new(
		&"tray",
		StringName(cup.name),
		1,
		cup,
		{
			"category": CUP_CATEGORY,
			"footprint_size": Vector2i.ONE,
		}
	)
	return _interaction_controller.start_drag(payload, cup, viewport_position)


func _on_tray_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if _begin_table_drag(mouse_event.position):
		get_viewport().set_input_as_handled()


func _on_cup_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int,
	cup: Cup
) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if _begin_cup_drag(cup, mouse_event.position):
		get_viewport().set_input_as_handled()


func _on_tray_mouse_entered() -> void:
	if _interaction_controller.is_dragging():
		return
	if _interaction_controller.current_mode == InteractionController.MODE_ORGANIZE:
		get_node("/root/CursorService").set_state(&"hover_actionable")


func _on_cup_mouse_entered(cup: Cup) -> void:
	if _interaction_controller.is_dragging() or _cells_for_item(cup).is_empty():
		return
	if _interaction_controller.current_mode == InteractionController.MODE_INTERACT:
		get_node("/root/CursorService").set_state(&"hover_actionable")


func _on_hover_exited() -> void:
	if not _interaction_controller.is_dragging():
		get_node("/root/CursorService").reset()


func _on_drag_canceled(payload: HeldItemPayload) -> void:
	if payload != null and payload.item_id == RESERVATION_ID:
		_register_drop_zones()
		_restore_table_reservation()


func _on_mode_changed(mode: StringName) -> void:
	internal_grid.set_interact_mode(mode == InteractionController.MODE_INTERACT)
	_update_mode_visual(mode)
	_register_drop_zones()
	get_node("/root/CursorService").reset()


func _update_mode_visual(mode: StringName) -> void:
	modulate.a = ORGANIZE_GHOST_ALPHA if mode == InteractionController.MODE_ORGANIZE else 1.0


func _restore_table_reservation() -> void:
	if _committed_cell == INVALID_CELL:
		return
	var restored := _table_grid.reserve_footprint(
		RESERVATION_ID,
		_table_footprint,
		_committed_cell,
		0,
		TableGrid.STATE_TRAY_AREA
	)
	assert(restored, "TrayStation failed to restore its previous table reservation.")


func _ensure_cup_interaction(cup: Cup) -> void:
	var input_callable := _on_cup_input_event.bind(cup)
	if not cup.input_event.is_connected(input_callable):
		cup.input_event.connect(input_callable)
	var entered_callable := _on_cup_mouse_entered.bind(cup)
	if not cup.mouse_entered.is_connected(entered_callable):
		cup.mouse_entered.connect(entered_callable)
	if not cup.mouse_exited.is_connected(_on_hover_exited):
		cup.mouse_exited.connect(_on_hover_exited)


func _place_node_at_cells(item: Node2D, cells_to_occupy: Array[Vector2i]) -> void:
	if item.get_parent() == null:
		cups.add_child(item)
	elif item.get_parent() != cups:
		item.reparent(cups, true)
	item.global_position = internal_grid.average_cell_world_position(cells_to_occupy)
	for cell in cells_to_occupy:
		_slot_occupants[cell] = item


func _clear_item_cells(item: Node2D) -> void:
	for cell in _cells_for_item(item):
		_slot_occupants.erase(cell)


func _cells_for_item(item: Node2D) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _slot_occupants:
		if _slot_occupants[cell] == item:
			result.append(cell)
	return result


func _ordered_cells() -> Array[Vector2i]:
	return _cells_from(Vector2i.ZERO, internal_grid.grid_size)


func _cells_from(origin_cell: Vector2i, dimensions: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in dimensions.y:
		for x in dimensions.x:
			result.append(origin_cell + Vector2i(x, y))
	return result


func _average_table_cell_position(cells_to_average: Array[Vector2i]) -> Vector2:
	var total := Vector2.ZERO
	for cell in cells_to_average:
		total += _table_grid.cell_to_world(cell)
	return total / cells_to_average.size()


func _register_drop_zones() -> void:
	if not is_instance_valid(_interaction_controller):
		return
	_interaction_controller.unregister_drop_zone(table_drop_zone)
	_interaction_controller.unregister_drop_zone(internal_drop_zone)
	if _interaction_controller.current_mode == InteractionController.MODE_ORGANIZE:
		_interaction_controller.register_drop_zone(table_drop_zone)
	else:
		_interaction_controller.register_drop_zone(internal_drop_zone)


func _exit_tree() -> void:
	if is_instance_valid(_interaction_controller):
		_interaction_controller.unregister_drop_zone(table_drop_zone)
		_interaction_controller.unregister_drop_zone(internal_drop_zone)
