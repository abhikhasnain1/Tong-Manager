class_name TrayTableDropZone
extends DropZone

const CATEGORY := &"tray_station"
const CELL_SWITCH_HYSTERESIS := 0.08

var _station: TrayStation
var _candidate_payload: HeldItemPayload
var _candidate_grid_position := Vector2.ZERO
var _candidate_cells: Array[Vector2i] = []
var _candidate_in_bounds := false


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

	_refresh_candidate(payload)
	if not _candidate_in_bounds:
		return DropValidation.invalid("table_grid.footprint_outside_bounds")
	if _station.get_table_grid().can_place_cells(_candidate_cells):
		return DropValidation.valid()
	return DropValidation.invalid("table_grid.placement_blocked")


func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	if not _station.commit_table_placement(_candidate_cells):
		return
	clear_highlight()
	drop_applied.emit(payload)


func set_highlight(_valid: bool) -> void:
	if _station == null:
		return
	_station.get_table_grid().preview_cells(_candidate_cells, _candidate_in_bounds)


func clear_highlight() -> void:
	if _station != null:
		_station.get_table_grid().clear_preview()
	_candidate_payload = null
	_candidate_grid_position = Vector2.ZERO
	_candidate_cells.clear()
	_candidate_in_bounds = false


func _refresh_candidate(payload: HeldItemPayload) -> void:
	var table_grid := _station.get_table_grid()
	var grid_position := table_grid.world_to_grid_position(
		_station.get_table_placement_anchor_world_position()
	)
	var proposed_grid_position := _snap_to_phase(
		grid_position,
		_station.get_table_snap_phase()
	)
	if _candidate_payload != payload:
		_candidate_payload = payload
		_candidate_grid_position = proposed_grid_position
	else:
		_candidate_grid_position = _stabilize_candidate(
			proposed_grid_position,
			grid_position
		)
	_station.align_table_drag_preview(_candidate_grid_position)
	_candidate_cells = _station.get_table_footprint_cells()
	_candidate_in_bounds = _station.is_table_footprint_in_bounds()


func _snap_to_phase(grid_position: Vector2, phase: Vector2) -> Vector2:
	return Vector2(
		roundf(grid_position.x - phase.x) + phase.x,
		roundf(grid_position.y - phase.y) + phase.y
	)


func _stabilize_candidate(
	proposed_grid_position: Vector2,
	grid_position: Vector2
) -> Vector2:
	var result := _candidate_grid_position
	var switch_distance := 0.5 + CELL_SWITCH_HYSTERESIS
	if absf(grid_position.x - _candidate_grid_position.x) >= switch_distance:
		result.x = proposed_grid_position.x
	if absf(grid_position.y - _candidate_grid_position.y) >= switch_distance:
		result.y = proposed_grid_position.y
	return result
