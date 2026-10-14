class_name CupTransferDropZone
extends DropZone

var transfers: CupTransfer
var _highlighted := false
var _valid := false


func _init() -> void:
	name = "CupReturnPlacement"
	snap_radius = 100000.0
	input_pickable = false
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.hide()
	add_child(preview)


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return is_instance_valid(transfers) and transfers.owns_payload(payload)


func accepts(payload: HeldItemPayload) -> DropValidation:
	return transfers.validate_surface(payload) if is_relevant_to(payload) else DropValidation.invalid("Pick up a returned cup")


func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid or not transfers.commit_to_surface(payload): return false
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
	if not _highlighted or not is_instance_valid(transfers.controller.current_drag_node): return
	var cup := transfers.controller.current_drag_node as Cup
	if cup == null: return
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	var tint := VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT
	for shape in handle.get_footprints():
		var polygon := PackedVector2Array()
		for point in shape: polygon.append(to_local(cup.to_global(point)))
		draw_colored_polygon(polygon, tint)
