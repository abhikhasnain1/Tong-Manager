class_name GridPlaceable
extends Node

signal move_started(origin_cell: Vector2i)
signal move_previewed(cell: Vector2i, is_valid: bool)
signal move_committed(cell: Vector2i)
signal move_canceled(restored_cell: Vector2i)

@export var item_id: StringName
@export var footprint: PlaceableFootprint
@export_range(0, 3, 1) var rotation_quarters: int = 0
@export var reservation_state: StringName = TableGrid.STATE_OCCUPIED
@export_node_path("Node2D") var table_grid_path: NodePath
@export_node_path("Node2D") var world_node_path: NodePath
@export_node_path("Marker2D") var placement_anchor_path: NodePath

var current_cell := Vector2i(-1, -1)

var _table_grid: TableGrid
var _world_node: Node2D
var _placement_anchor: Marker2D
var _is_moving: bool = false
var _move_origin_cell := Vector2i(-1, -1)
var _move_origin_global_transform := Transform2D.IDENTITY


func _ready() -> void:
	_resolve_nodes()
	call_deferred(&"_register_initial_placement")


func register_current_placement() -> bool:
	if not _has_valid_configuration():
		return false
	var derived_cell := _table_grid.world_to_cell(_placement_anchor.global_position)
	if not _table_grid.reserve_footprint(
		item_id,
		footprint,
		derived_cell,
		rotation_quarters,
		reservation_state
	):
		return false
	current_cell = derived_cell
	return true


func begin_grid_move() -> bool:
	if _is_moving or not _has_valid_configuration() or current_cell.x < 0 or current_cell.y < 0:
		return false
	_move_origin_cell = current_cell
	_move_origin_global_transform = _world_node.global_transform
	_table_grid.clear_item(item_id)
	_table_grid.clear_preview()
	_is_moving = true
	move_started.emit(_move_origin_cell)
	return true


func preview_grid_move(world_anchor_position: Vector2) -> DropValidation:
	if not _is_moving:
		return DropValidation.invalid("table_grid.move_not_started")
	var candidate_cell := _table_grid.world_to_cell(world_anchor_position)
	var validation := _table_grid.preview_placement(footprint, candidate_cell, rotation_quarters)
	move_previewed.emit(candidate_cell, validation.is_valid)
	return validation


func preview_current_grid_move() -> DropValidation:
	if _placement_anchor == null:
		return DropValidation.invalid("table_grid.missing_placement_anchor")
	return preview_grid_move(_placement_anchor.global_position)


func commit_grid_move(world_anchor_position: Vector2) -> bool:
	if not _is_moving:
		return false
	var candidate_cell := _table_grid.world_to_cell(world_anchor_position)
	if not _table_grid.can_place(footprint, candidate_cell, rotation_quarters):
		_table_grid.preview_placement(footprint, candidate_cell, rotation_quarters)
		return false

	_snap_anchor_to_cell(candidate_cell)
	if not _table_grid.reserve_footprint(
		item_id,
		footprint,
		candidate_cell,
		rotation_quarters,
		reservation_state
	):
		return false

	current_cell = candidate_cell
	_is_moving = false
	_table_grid.clear_preview()
	move_committed.emit(current_cell)
	return true


func commit_current_grid_move() -> bool:
	if _placement_anchor == null:
		return false
	return commit_grid_move(_placement_anchor.global_position)


func cancel_grid_move() -> void:
	if not _is_moving:
		return
	_world_node.global_transform = _move_origin_global_transform
	var restored := _table_grid.reserve_footprint(
		item_id,
		footprint,
		_move_origin_cell,
		rotation_quarters,
		reservation_state
	)
	assert(restored, "GridPlaceable failed to restore its previous reservation.")
	current_cell = _move_origin_cell
	_is_moving = false
	_table_grid.clear_preview()
	move_canceled.emit(current_cell)


func is_grid_move_active() -> bool:
	return _is_moving


func _register_initial_placement() -> void:
	assert(
		register_current_placement(),
		"GridPlaceable initial footprint must fit at the cell derived from its placement anchor."
	)


func _resolve_nodes() -> void:
	_table_grid = get_node_or_null(table_grid_path) as TableGrid
	_world_node = get_node_or_null(world_node_path) as Node2D
	_placement_anchor = get_node_or_null(placement_anchor_path) as Marker2D
	assert(_table_grid != null, "GridPlaceable requires a TableGrid reference.")
	assert(_world_node != null, "GridPlaceable requires a movable Node2D reference.")
	assert(_placement_anchor != null, "GridPlaceable requires a Marker2D placement anchor.")
	assert(item_id != &"", "GridPlaceable requires a non-empty item_id.")
	assert(footprint != null, "GridPlaceable requires a PlaceableFootprint resource.")
	assert(
		reservation_state == TableGrid.STATE_OCCUPIED
		or reservation_state == TableGrid.STATE_TRAY_AREA,
		"GridPlaceable reservation_state must be an occupied grid state."
	)


func _has_valid_configuration() -> bool:
	return (
		_table_grid != null
		and _world_node != null
		and _placement_anchor != null
		and item_id != &""
		and footprint != null
	)


func _snap_anchor_to_cell(cell: Vector2i) -> void:
	var target_anchor_position := _table_grid.cell_corner_to_world(cell)
	_world_node.global_position += target_anchor_position - _placement_anchor.global_position
