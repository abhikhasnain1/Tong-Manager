class_name WaterFillDropZone
extends DropZone

var target: Kettle
var controller: InteractionController
var _highlighted := false
var _valid := false


func _init() -> void:
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)
	zone_id = &"kettle_water_fill"
	snap_radius = 65.0


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and is_instance_valid(payload.world_node) and payload.world_node is WaterDrum


func accepts(payload: HeldItemPayload) -> DropValidation:
	if (not is_relevant_to(payload) or not is_instance_valid(target) or not is_inside_tree()
		or is_queued_for_deletion() or not target.is_inside_tree() or target.is_queued_for_deletion()
		or not target.is_ancestor_of(self)):
		return DropValidation.invalid("water.kettle_unavailable")
	if (not is_instance_valid(controller) or controller.current_mode != InteractionController.MODE_INTERACT
		or controller.current_payload != payload or controller.current_drag_node != payload.world_node):
		return DropValidation.invalid("water.active_drag_required")
	var drum := payload.world_node as WaterDrum
	if not drum.is_active_payload(payload) or not drum.supply.can_fill(int(payload.metadata.get("water_token", 0)), target):
		return DropValidation.invalid("water.empty_or_plain_water_kettle_required")
	return DropValidation.valid()


func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	var drum := payload.world_node as WaterDrum
	var accepted := drum.supply.fill_kettle(int(payload.metadata.get("water_token", 0)), target)
	drum.finish_transfer(payload)
	if accepted > 0.0:
		drop_applied.emit(payload)


func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	queue_redraw()


func clear_highlight() -> void:
	_highlighted = false
	queue_redraw()


func _draw() -> void:
	if _highlighted:
		draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT, 4.0, true)
