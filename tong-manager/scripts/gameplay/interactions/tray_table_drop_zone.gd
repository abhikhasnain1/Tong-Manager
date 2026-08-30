class_name TrayTableDropZone
extends DropZone

const CATEGORY := &"tray_station"
const CELL_SWITCH_HYSTERESIS := 0.08

var _station: TrayStation
var _candidate_payload: HeldItemPayload
var _candidate_cell := Vector2i(-1, -1)


func _ready() -> void:
	_station = get_parent() as TrayStation
	assert(_station != null, "TrayTableDropZone must be a child of TrayStation.")


func accepts(payload: HeldItemPayload) -> DropValidation:
	if payload == null or _station == null:
		return DropValidation.invalid("drop.missing_payload")
	if _station.get_interaction_controller().current_mode != InteractionController.MODE_ORGANIZE:
		return DropValidation.invalid("tray.organize_mode_required")
	if StringName(payload.metadata.get("category", &"")) != CATEGORY:
		return DropValidation.invalid("drop.category_not_accepted")
	if payload.world_node != _station:
		return DropValidation.invalid("tray.wrong_station")

	var table_grid := _station.get_table_grid()
	var footprint := _station.get_table_footprint()
	var dimensions := footprint.dimensions()
	var anchor_position := _station.get_table_placement_anchor_world_position()
	var proposed_cell := table_grid.world_to_footprint_origin(anchor_position, dimensions)
	var grid_position := table_grid.world_to_grid_position(anchor_position)
	if _candidate_payload != payload:
		_candidate_payload = payload
		_candidate_cell = proposed_cell
	else:
		_candidate_cell = _stabilize_candidate(proposed_cell, grid_position, dimensions)
	if table_grid.can_place(footprint, _candidate_cell):
		return DropValidation.valid()
	return DropValidation.invalid("table_grid.placement_blocked")


func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	if not _station.commit_table_placement(_candidate_cell):
		return
	clear_highlight()
	drop_applied.emit(payload)


func set_highlight(_valid: bool) -> void:
	if _station == null:
		return
	_station.align_table_drag_preview(_candidate_cell)
	_station.get_table_grid().preview_placement(
		_station.get_table_footprint(),
		_candidate_cell
	)


func clear_highlight() -> void:
	if _station != null:
		_station.get_table_grid().clear_preview()
	_candidate_payload = null
	_candidate_cell = Vector2i(-1, -1)


func _stabilize_candidate(
	proposed_cell: Vector2i,
	grid_position: Vector2,
	footprint_size: Vector2i
) -> Vector2i:
	var result := _candidate_cell
	var current_center := Vector2(_candidate_cell) + Vector2(footprint_size) * 0.5
	var switch_distance := 0.5 + CELL_SWITCH_HYSTERESIS
	if absf(grid_position.x - current_center.x) >= switch_distance:
		result.x = proposed_cell.x
	if absf(grid_position.y - current_center.y) >= switch_distance:
		result.y = proposed_cell.y
	return result
