class_name TableGrid
extends Node2D

signal organize_mode_changed(enabled: bool)
signal placement_preview_changed(is_valid: bool, cells: Array[Vector2i])
signal reservation_changed(item_id: StringName, cells: Array[Vector2i])

const STATE_EMPTY := &"empty"
const STATE_OCCUPIED := &"occupied"
const STATE_VALID_PREVIEW := &"valid_preview"
const STATE_INVALID_PREVIEW := &"invalid_preview"
const STATE_TRAY_AREA := &"tray_area"

const EMPTY_FILL := Color(1.0, 1.0, 1.0, 0.025)
const EMPTY_OUTLINE := Color(1.0, 1.0, 1.0, 0.35)
const OCCUPIED_FILL := Color(0.12, 0.14, 0.18, 0.5)
const VALID_FILL := Color(0.25, 1.0, 0.4, 0.42)
const INVALID_FILL := Color(1.0, 0.25, 0.25, 0.42)
const TRAY_FILL := Color(1.0, 0.78, 0.2, 0.26)

@export var origin := Vector2.ZERO
@export var cell_size := Vector2(64.0, 48.0)
@export var grid_size := Vector2i(12, 5)
@export_node_path("Node") var interaction_controller_path: NodePath
@export var reserve_authored_tray: bool = true
@export var authored_tray_cell := Vector2i.ZERO
@export var authored_tray_footprint: PlaceableFootprint

var organize_mode_enabled: bool = false
var occupied_cells: Dictionary = {}

var _item_cells: Dictionary = {}
var _preview_cells: Array[Vector2i] = []
var _preview_is_valid: bool = false


func _ready() -> void:
	assert(cell_size.x > 0.0 and cell_size.y > 0.0, "TableGrid cell_size must be positive.")
	assert(grid_size.x > 0 and grid_size.y > 0, "TableGrid grid_size must be positive.")

	var interaction_controller := get_node_or_null(interaction_controller_path) as InteractionController
	assert(interaction_controller != null, "TableGrid requires an InteractionController reference.")
	interaction_controller.mode_changed.connect(_on_interaction_mode_changed)
	set_organize_mode(interaction_controller.current_mode == InteractionController.MODE_ORGANIZE)

	if reserve_authored_tray:
		assert(authored_tray_footprint != null, "TableGrid requires the authored tray footprint.")
		assert(
			reserve_footprint(&"tray", authored_tray_footprint, authored_tray_cell, 0, STATE_TRAY_AREA),
			"The authored tray footprint must fit inside the table grid."
		)


func world_to_cell(world_position: Vector2) -> Vector2i:
	var grid_position := to_local(world_position) - origin
	return Vector2i(floori(grid_position.x / cell_size.x), floori(grid_position.y / cell_size.y))


func cell_to_world(cell: Vector2i) -> Vector2:
	var local_center := origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
	return to_global(local_center)


func can_place(footprint: PlaceableFootprint, cell: Vector2i, rotation_quarters: int = 0) -> bool:
	if footprint == null or footprint.size.x <= 0 or footprint.size.y <= 0:
		return false
	if not footprint.supports_rotation(rotation_quarters):
		return false
	for target_cell in footprint.cells_from(cell, rotation_quarters):
		if not is_cell_in_bounds(target_cell) or occupied_cells.has(target_cell):
			return false
	return true


func reserve_cells(
	item_id: StringName,
	cells: Array[Vector2i],
	state: StringName = STATE_OCCUPIED
) -> bool:
	if item_id.is_empty() or cells.is_empty():
		return false
	if state != STATE_OCCUPIED and state != STATE_TRAY_AREA:
		return false

	var unique_cells: Array[Vector2i] = []
	for cell in cells:
		if not is_cell_in_bounds(cell) or unique_cells.has(cell):
			return false
		if occupied_cells.has(cell) and occupied_cells[cell]["item_id"] != item_id:
			return false
		unique_cells.append(cell)

	_remove_item_cells(item_id)
	for cell in unique_cells:
		occupied_cells[cell] = {"item_id": item_id, "state": state}
	_item_cells[item_id] = unique_cells.duplicate()
	queue_redraw()
	reservation_changed.emit(item_id, unique_cells.duplicate())
	return true


func reserve_footprint(
	item_id: StringName,
	footprint: PlaceableFootprint,
	cell: Vector2i,
	rotation_quarters: int = 0,
	state: StringName = STATE_OCCUPIED
) -> bool:
	if footprint == null or not footprint.supports_rotation(rotation_quarters):
		return false
	return reserve_cells(item_id, footprint.cells_from(cell, rotation_quarters), state)


func clear_item(item_id: StringName) -> void:
	if not _item_cells.has(item_id):
		return
	_remove_item_cells(item_id)
	queue_redraw()
	var empty_cells: Array[Vector2i] = []
	reservation_changed.emit(item_id, empty_cells)


func preview_placement(
	footprint: PlaceableFootprint,
	cell: Vector2i,
	rotation_quarters: int = 0
) -> DropValidation:
	_preview_cells.clear()
	if footprint != null:
		_preview_cells = footprint.cells_from(cell, rotation_quarters)
	_preview_is_valid = can_place(footprint, cell, rotation_quarters)
	queue_redraw()
	placement_preview_changed.emit(_preview_is_valid, _preview_cells.duplicate())
	if _preview_is_valid:
		return DropValidation.valid()
	return DropValidation.invalid("table_grid.placement_blocked")


func preview_world_placement(
	footprint: PlaceableFootprint,
	world_position: Vector2,
	rotation_quarters: int = 0
) -> DropValidation:
	return preview_placement(footprint, world_to_cell(world_position), rotation_quarters)


func clear_preview() -> void:
	if _preview_cells.is_empty():
		return
	_preview_cells.clear()
	_preview_is_valid = false
	queue_redraw()
	var empty_cells: Array[Vector2i] = []
	placement_preview_changed.emit(false, empty_cells)


func set_organize_mode(enabled: bool) -> void:
	if organize_mode_enabled == enabled and visible == enabled:
		return
	organize_mode_enabled = enabled
	visible = enabled
	if not enabled:
		clear_preview()
	queue_redraw()
	organize_mode_changed.emit(enabled)


func get_cell_state(cell: Vector2i) -> StringName:
	if _preview_cells.has(cell):
		return STATE_VALID_PREVIEW if _preview_is_valid else STATE_INVALID_PREVIEW
	if occupied_cells.has(cell):
		return occupied_cells[cell]["state"]
	return STATE_EMPTY


func get_cells_for_item(item_id: StringName) -> Array[Vector2i]:
	if not _item_cells.has(item_id):
		return []
	var result: Array[Vector2i] = []
	result.assign(_item_cells[item_id])
	return result


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _on_interaction_mode_changed(mode: StringName) -> void:
	set_organize_mode(mode == InteractionController.MODE_ORGANIZE)


func _remove_item_cells(item_id: StringName) -> void:
	if not _item_cells.has(item_id):
		return
	for cell in _item_cells[item_id]:
		if occupied_cells.has(cell) and occupied_cells[cell]["item_id"] == item_id:
			occupied_cells.erase(cell)
	_item_cells.erase(item_id)


func _draw() -> void:
	if not organize_mode_enabled:
		return
	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(cell) * cell_size, cell_size)
			draw_rect(rect, _fill_for_state(get_cell_state(cell)), true)
			draw_rect(rect, EMPTY_OUTLINE, false, 1.5)


func _fill_for_state(state: StringName) -> Color:
	match state:
		STATE_OCCUPIED:
			return OCCUPIED_FILL
		STATE_VALID_PREVIEW:
			return VALID_FILL
		STATE_INVALID_PREVIEW:
			return INVALID_FILL
		STATE_TRAY_AREA:
			return TRAY_FILL
		_:
			return EMPTY_FILL
