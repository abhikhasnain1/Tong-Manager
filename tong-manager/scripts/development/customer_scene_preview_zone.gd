extends DropZone
## Only accepts synthetic review tokens. Production serving is a separate command.

var customer: Customer
var controller: InteractionController
var preview: Node
var customer_index := 0


func _init() -> void:
	input_pickable = false
	snap_radius = 1.0
	var debug := Sprite2D.new()
	debug.name = "DebugPreview"
	debug.visible = false
	add_child(debug)


func configure(owner_preview: Node, target: Customer, index: int, interaction: InteractionController) -> void:
	preview = owner_preview
	customer = target
	customer_index = index
	controller = interaction
	zone_id = &"customer_scene_fixture"
	controller.register_drop_zone(self)


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return is_instance_valid(preview) and payload != null and payload.source == &"customer_scene_fixture" and payload.metadata.get("preview_id") == preview.get_instance_id()


func get_probe_position(_payload: HeldItemPayload, viewport_position: Vector2) -> Vector2:
	if is_instance_valid(preview) and preview.pick_customer_at(viewport_position) == customer_index:
		return get_global_transform_with_canvas().origin
	return Vector2(INF, INF)


func accepts(payload: HeldItemPayload) -> DropValidation:
	if (not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(preview)
		or not preview.is_inside_tree() or preview.is_queued_for_deletion()
		or not is_instance_valid(customer) or not customer.is_inside_tree()
		or customer.is_queued_for_deletion() or not customer.is_visible_in_tree()
		or not customer.is_serve_enabled() or not preview.is_ancestor_of(customer)):
		return DropValidation.invalid("This sample customer is unavailable")
	if (not is_relevant_to(payload) or not is_instance_valid(controller)
		or controller.current_mode != InteractionController.MODE_INTERACT
		or controller.current_payload != payload or not controller.is_dragging()
		or controller.is_world_input_blocked()):
		return DropValidation.invalid("Use a sample token from the review panel")
	return DropValidation.valid()


func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid:
		return false
	var applied: bool = preview.simulate_result(customer_index, StringName(payload.metadata.get("sample_kind", &"")))
	if applied:
		drop_applied.emit(payload)
	return applied


func set_highlight(_valid: bool) -> void:
	if is_instance_valid(customer): customer.set_drop_highlight(true)


func clear_highlight() -> void:
	if is_instance_valid(customer): customer.set_drop_highlight(false)


func _enter_tree() -> void:
	_register_after_enter.call_deferred()


func _register_after_enter() -> void:
	if (is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(controller)
		and controller.is_inside_tree() and is_instance_valid(preview)
		and is_instance_valid(customer) and preview.is_ancestor_of(customer)):
		controller.register_drop_zone(self)


func _exit_tree() -> void:
	clear_highlight()
	if is_instance_valid(controller): controller.unregister_drop_zone(self)
