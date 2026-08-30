class_name TrayInternalDropZone
extends DropZone

const CATEGORY_CUP := &"cup"
const CATEGORY_SMALL_ITEM := &"small_item"
const CELL_SWITCH_HYSTERESIS := 0.08

var _station: TrayStation
var _candidate_payload: HeldItemPayload
var _candidate_cell := Vector2i(-1, -1)
var _footprint_size := Vector2i.ONE
var _display_cells: Array[Vector2i] = []


func _ready() -> void:
	_station = get_parent() as TrayStation
	assert(_station != null, "TrayInternalDropZone must be a child of TrayStation.")


func accepts(payload: HeldItemPayload) -> DropValidation:
	_display_cells.clear()
	if payload == null or _station == null:
		return DropValidation.invalid("drop.missing_payload")
	if _station.get_interaction_controller().current_mode != InteractionController.MODE_INTERACT:
		return DropValidation.invalid("tray.interact_mode_required")
	var category := StringName(payload.metadata.get("category", &""))
	if category != CATEGORY_CUP and category != CATEGORY_SMALL_ITEM:
		return DropValidation.invalid("drop.category_not_accepted")
	var drag_node := payload.world_node as Node2D
	if drag_node == null:
		return DropValidation.invalid("drop.missing_world_node")

	_footprint_size = payload.metadata.get("footprint_size", Vector2i.ONE)
	_footprint_size = Vector2i(maxi(1, _footprint_size.x), maxi(1, _footprint_size.y))
	var tray_grid := _station.get_internal_grid()
	var proposed_cell := tray_grid.world_to_footprint_origin(drag_node.global_position, _footprint_size)
	var grid_position := tray_grid.world_to_grid_position(drag_node.global_position)
	if _candidate_payload != payload:
		_candidate_payload = payload
		_candidate_cell = proposed_cell
	else:
		_candidate_cell = _stabilize_candidate(proposed_cell, grid_position, _footprint_size)
	var display_origin := tray_grid.clamp_origin(_candidate_cell, _footprint_size)
	_display_cells = _cells_from(display_origin, _footprint_size)
	if _station.can_place_inside(payload, _candidate_cell):
		return DropValidation.valid()
	return DropValidation.invalid("tray.slot_unavailable")


func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	if not _station.place_inside(payload, _candidate_cell):
		return
	clear_highlight()
	drop_applied.emit(payload)


func set_highlight(valid: bool) -> void:
	if _station != null:
		_station.get_internal_grid().set_preview(_display_cells, valid)


func clear_highlight() -> void:
	if _station != null:
		_station.get_internal_grid().clear_preview()
	_candidate_payload = null
	_candidate_cell = Vector2i(-1, -1)
	_footprint_size = Vector2i.ONE
	_display_cells.clear()


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


func _cells_from(origin_cell: Vector2i, dimensions: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in dimensions.y:
		for x in dimensions.x:
			cells.append(origin_cell + Vector2i(x, y))
	return cells
