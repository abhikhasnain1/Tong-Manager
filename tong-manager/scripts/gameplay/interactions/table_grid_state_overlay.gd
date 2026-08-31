@tool
extends Node2D

const VALID_OUTLINE := Color(0.25, 1.0, 0.4, 0.95)
const INVALID_OUTLINE := Color(1.0, 0.25, 0.25, 0.95)

var _table_grid: TableGrid


func _ready() -> void:
	_table_grid = get_parent() as TableGrid
	assert(_table_grid != null, "TableGrid state overlay must be a child of TableGrid.")
	_table_grid.organize_mode_changed.connect(_on_grid_changed.unbind(1))
	_table_grid.placement_preview_changed.connect(_on_grid_changed.unbind(2))
	_table_grid.reservation_changed.connect(_on_grid_changed.unbind(2))
	queue_redraw()


func _draw() -> void:
	if _table_grid == null or (not _table_grid.organize_mode_enabled and not Engine.is_editor_hint()):
		return
	for y in _table_grid.grid_size.y:
		for x in _table_grid.grid_size.x:
			var cell := Vector2i(x, y)
			var state := _table_grid.get_cell_state(cell)
			var outline := Color.TRANSPARENT
			match state:
				TableGrid.STATE_VALID_PREVIEW:
					outline = VALID_OUTLINE
				TableGrid.STATE_INVALID_PREVIEW:
					outline = INVALID_OUTLINE
				_:
					continue
			var polygon := _table_grid.get_cell_polygon(cell)
			var closed := PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]])
			draw_polyline(closed, outline, 2.5, true)


func _on_grid_changed() -> void:
	queue_redraw()
