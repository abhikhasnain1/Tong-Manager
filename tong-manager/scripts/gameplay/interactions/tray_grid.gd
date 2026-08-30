@tool
class_name TrayGrid
extends Node2D

const EMPTY_FILL := Color(1.0, 1.0, 1.0, 0.035)
const EMPTY_OUTLINE := Color(1.0, 1.0, 1.0, 0.58)
const VALID_FILL := Color(0.25, 1.0, 0.4, 0.22)
const INVALID_FILL := Color(1.0, 0.25, 0.25, 0.22)
const VALID_OUTLINE := Color(0.25, 1.0, 0.4, 0.95)
const INVALID_OUTLINE := Color(1.0, 0.25, 0.25, 0.95)

@export var grid_size := Vector2i(3, 2)
@export_node_path("Marker2D") var top_left_path: NodePath
@export_node_path("Marker2D") var top_right_path: NodePath
@export_node_path("Marker2D") var bottom_left_path: NodePath
@export_node_path("Marker2D") var bottom_right_path: NodePath
@export_node_path("Node2D") var cup_slots_path: NodePath

var _preview_cells: Array[Vector2i] = []
var _preview_is_valid := false
var _corner_cache := PackedVector2Array()


func _ready() -> void:
	_assert_contract()
	_corner_cache = get_authored_corners()
	_sync_slot_markers()
	if Engine.is_editor_hint():
		visible = true
		set_process(true)
		queue_redraw()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var current_corners := get_authored_corners()
	if current_corners == _corner_cache:
		return
	_corner_cache = current_corners
	_sync_slot_markers()
	queue_redraw()


func configure(configured_size: Vector2i) -> void:
	assert(configured_size.x > 0 and configured_size.y > 0, "TrayGrid size must be positive.")
	grid_size = configured_size
	_sync_slot_markers()
	queue_redraw()


func world_to_cell(world_position: Vector2) -> Vector2i:
	var grid_position := world_to_grid_position(world_position)
	return Vector2i(floori(grid_position.x), floori(grid_position.y))


func world_to_grid_position(world_position: Vector2) -> Vector2:
	return _local_to_grid_uv(to_local(world_position)) * Vector2(grid_size)


func world_to_footprint_origin(world_position: Vector2, footprint_size: Vector2i) -> Vector2i:
	var grid_position := world_to_grid_position(world_position)
	return Vector2i(
		roundi(grid_position.x - footprint_size.x * 0.5),
		roundi(grid_position.y - footprint_size.y * 0.5)
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	var grid_uv := (Vector2(cell) + Vector2(0.5, 0.5)) / Vector2(grid_size)
	return to_global(_grid_uv_to_local(grid_uv))


func average_cell_world_position(cells: Array[Vector2i]) -> Vector2:
	assert(not cells.is_empty(), "Cannot average an empty TrayGrid cell set.")
	var total := Vector2.ZERO
	for cell in cells:
		total += cell_to_world(cell)
	return total / cells.size()


func get_cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var top_left_uv := Vector2(cell) / Vector2(grid_size)
	var bottom_right_uv := Vector2(cell + Vector2i.ONE) / Vector2(grid_size)
	return PackedVector2Array([
		_grid_uv_to_local(top_left_uv),
		_grid_uv_to_local(Vector2(bottom_right_uv.x, top_left_uv.y)),
		_grid_uv_to_local(bottom_right_uv),
		_grid_uv_to_local(Vector2(top_left_uv.x, bottom_right_uv.y)),
	])


func get_authored_corners() -> PackedVector2Array:
	return PackedVector2Array([
		_corner_position(top_left_path),
		_corner_position(top_right_path),
		_corner_position(bottom_right_path),
		_corner_position(bottom_left_path),
	])


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func clamp_origin(origin_cell: Vector2i, footprint_size: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(origin_cell.x, 0, maxi(0, grid_size.x - footprint_size.x)),
		clampi(origin_cell.y, 0, maxi(0, grid_size.y - footprint_size.y))
	)


func set_preview(cells: Array[Vector2i], valid: bool) -> void:
	_preview_cells = cells.duplicate()
	_preview_is_valid = valid
	queue_redraw()


func clear_preview() -> void:
	_preview_cells.clear()
	_preview_is_valid = false
	queue_redraw()


func set_interact_mode(enabled: bool) -> void:
	visible = enabled
	if not enabled:
		clear_preview()
	queue_redraw()


func get_slot_marker(cell: Vector2i) -> Marker2D:
	if not is_cell_in_bounds(cell):
		return null
	var cup_slots := get_node_or_null(cup_slots_path) as Node2D
	if cup_slots == null:
		return null
	return cup_slots.get_node_or_null("CupSlot%d" % _cell_index(cell)) as Marker2D


func _draw() -> void:
	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var highlighted := _preview_cells.has(cell)
			var fill := EMPTY_FILL
			var outline := EMPTY_OUTLINE
			var outline_width := 2.0
			if highlighted:
				fill = VALID_FILL if _preview_is_valid else INVALID_FILL
				outline = VALID_OUTLINE if _preview_is_valid else INVALID_OUTLINE
				outline_width = 4.0
			var polygon := get_cell_polygon(cell)
			draw_colored_polygon(polygon, fill)
			var closed := PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]])
			draw_polyline(closed, outline, outline_width, true)
	if Engine.is_editor_hint():
		for corner in get_authored_corners():
			draw_circle(corner, 8.0, Color(0.15, 0.9, 1.0, 0.95), false, 2.0, true)


func _sync_slot_markers() -> void:
	var cup_slots := get_node_or_null(cup_slots_path) as Node2D
	if cup_slots == null:
		return
	for index in grid_size.x * grid_size.y:
		var marker := cup_slots.get_node_or_null("CupSlot%d" % index) as Marker2D
		if marker == null:
			marker = Marker2D.new()
			marker.name = "CupSlot%d" % index
			cup_slots.add_child(marker)
		var cell := Vector2i(index % grid_size.x, index / grid_size.x)
		marker.position = cup_slots.to_local(cell_to_world(cell))


func _cell_index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x


func _assert_contract() -> void:
	assert(grid_size.x > 0 and grid_size.y > 0, "TrayGrid size must be positive.")
	for path in [top_left_path, top_right_path, bottom_left_path, bottom_right_path]:
		assert(not path.is_empty(), "TrayGrid requires four authored corner marker paths.")
		assert(get_node_or_null(path) is Marker2D, "TrayGrid corner path must resolve to Marker2D: %s" % path)
	assert(get_node_or_null(cup_slots_path) is Node2D, "TrayGrid requires a CupSlots node.")


func _corner_position(path: NodePath) -> Vector2:
	var marker := get_node_or_null(path) as Marker2D
	return to_local(marker.global_position) if marker != null else Vector2.ZERO


func _grid_uv_to_local(grid_uv: Vector2) -> Vector2:
	var corners := get_authored_corners()
	var top := corners[0].lerp(corners[1], grid_uv.x)
	var bottom := corners[3].lerp(corners[2], grid_uv.x)
	return top.lerp(bottom, grid_uv.y)


func _local_to_grid_uv(local_position: Vector2) -> Vector2:
	var corners := get_authored_corners()
	var top_left := corners[0]
	var top_right := corners[1]
	var bottom_right := corners[2]
	var bottom_left := corners[3]
	var bounds := Rect2(top_left, Vector2.ZERO).expand(top_right).expand(bottom_right).expand(bottom_left)
	var uv := Vector2(
		(local_position.x - bounds.position.x) / maxf(bounds.size.x, 0.001),
		(local_position.y - bounds.position.y) / maxf(bounds.size.y, 0.001)
	)
	var base := top_left
	var horizontal := top_right - top_left
	var vertical := bottom_left - top_left
	var perspective := top_left - top_right - bottom_left + bottom_right

	for _iteration in 8:
		var estimated := base + horizontal * uv.x + vertical * uv.y + perspective * uv.x * uv.y
		var error := estimated - local_position
		if error.length_squared() < 0.0001:
			break
		var derivative_u := horizontal + perspective * uv.y
		var derivative_v := vertical + perspective * uv.x
		var determinant := derivative_u.x * derivative_v.y - derivative_u.y * derivative_v.x
		if absf(determinant) < 0.00001:
			break
		var correction_u := (error.x * derivative_v.y - error.y * derivative_v.x) / determinant
		var correction_v := (derivative_u.x * error.y - derivative_u.y * error.x) / determinant
		uv -= Vector2(correction_u, correction_v)
	return uv
