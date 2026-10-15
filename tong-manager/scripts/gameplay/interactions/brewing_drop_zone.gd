class_name BrewingDropZone
extends DropZone

var target: Node2D
var controller: InteractionController
var is_cup_target := false
var _highlighted := false
var _valid := false

func _init() -> void:
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return (payload != null and is_instance_valid(payload.world_node) and payload.world_node is Kettle
		and not (is_cup_target and bool(payload.metadata.get("kettle_move", false))))

func get_probe_position(payload: HeldItemPayload, viewport_position: Vector2) -> Vector2:
	if is_cup_target and is_relevant_to(payload):
		return (payload.world_node as Kettle).get_pour_probe_viewport()
	return viewport_position

func accepts(payload: HeldItemPayload) -> DropValidation:
	if (payload == null or not is_instance_valid(target) or not is_instance_valid(payload.world_node)
		or not payload.world_node is Kettle or not is_inside_tree() or not target.is_inside_tree()
		or target.is_queued_for_deletion() or not target.is_ancestor_of(self)):
		return DropValidation.invalid("brewing.kettle_required")
	var moving := bool(payload.metadata.get("kettle_move", false)) and not is_cup_target and is_instance_valid(controller) and controller.direct_mouse_gestures
	var intended_mode := InteractionController.MODE_ORGANIZE if moving else InteractionController.MODE_INTERACT
	if not is_instance_valid(controller) or controller.current_mode != intended_mode:
		return DropValidation.invalid("brewing.use_mode_required")
	var kettle := payload.world_node as Kettle
	var valid := kettle.can_pour_into(target as Cup) if is_cup_target else bool(target.call("can_seat", kettle))
	return DropValidation.valid() if valid else DropValidation.invalid("brewing.target_unavailable")

func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	var kettle := payload.world_node as Kettle
	var applied := true
	if is_cup_target:
		kettle.finish_cup_interaction()
	else:
		applied = bool(target.call("seat", kettle))
	if applied:
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
		draw_arc(Vector2.ZERO, 28.0 if is_cup_target else 60.0, 0, TAU, 40, VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT, 4.0, true)
