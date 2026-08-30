@tool
extends Node2D

const VALID_OUTLINE := Color(0.25, 1.0, 0.4, 0.95)
const INVALID_OUTLINE := Color(1.0, 0.25, 0.25, 0.95)
const TRAY_OUTLINE := Color(1.0, 0.82, 0.28, 0.95)

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
			var fill := Color.TRANSPARENT
			var outline := Color.TRANSPARENT
			match state:
				TableGrid.STATE_VALID_PREVIEW:
					fill = TableGrid.VALID_FILL
					outline = VALID_OUTLINE
				TableGrid.STATE_INVALID_PREVIEW:
					fill = TableGrid.INVALID_FILL
					outline = INVALID_OUTLINE
				TableGrid.STATE_TRAY_AREA:
					fill = TableGrid.TRAY_FILL
					outline = TRAY_OUTLINE
				_:
					continue
			var polygon := _table_grid.get_cell_polygon(cell)
			draw_colored_polygon(polygon, fill)
			var closed := PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]])
			draw_polyline(closed, outline, 2.5, true)


func _on_grid_changed() -> void:
	queue_redraw()
