class_name TablePlacementDropZone
extends DropZone

var handle: TablePlaceable
var _highlighted := false
var _valid := false


func _init() -> void:
	name = "TablePlacementDropZone"
	input_pickable = false
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return is_instance_valid(handle) and handle.owns_payload(payload)


func accepts(payload: HeldItemPayload) -> DropValidation:
	if not is_relevant_to(payload):
		return DropValidation.invalid("placement.arrange_drag_required")
	return handle.validate_placement()


func apply_drop(payload: HeldItemPayload) -> void:
	try_apply_drop(payload)


func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid or not handle.commit(payload):
		return false
	clear_highlight()
	drop_applied.emit(payload)
	return true


func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	queue_redraw()


func clear_highlight() -> void:
	_highlighted = false
	queue_redraw()


func _draw() -> void:
	if not _highlighted or not is_instance_valid(handle) or not is_instance_valid(handle.surface):
		return
	var color := VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT
	var viewport_scale := get_global_transform_with_canvas().get_scale().abs()
	var line_width := 2.0 / maxf(0.001, minf(viewport_scale.x, viewport_scale.y))
	for surface_polygon in handle.surface.get_candidate_polygons(handle.item):
		var polygon := PackedVector2Array()
		for point in surface_polygon:
			polygon.append(to_local(handle.surface.to_global(point)))
		if polygon.size() < 3:
			continue
		draw_colored_polygon(polygon, Color(color, 0.16))
		polygon.append(polygon[0])
		draw_polyline(polygon, Color(color, 1.0), line_width, true)
