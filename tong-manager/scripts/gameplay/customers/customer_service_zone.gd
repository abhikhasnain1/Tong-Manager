class_name CustomerServiceZone
extends DropZone

var service: CustomerService
var customer: Customer


func _init() -> void:
	input_pickable = false
	snap_radius = 1.0
	var debug := Sprite2D.new()
	debug.name = "DebugPreview"
	debug.visible = false
	add_child(debug)


func configure(owner_service: CustomerService, actor: Customer) -> void:
	service = owner_service
	customer = actor
	zone_id = &"customer_handoff"
	service.controller.register_drop_zone(self)


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and payload.metadata.get("category") in [&"cup", &"ready_item"]


func get_probe_position(_payload: HeldItemPayload, viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().origin if is_instance_valid(service) and service.pick_customer_at(viewport_position) == customer else Vector2(INF, INF)


func accepts(payload: HeldItemPayload) -> DropValidation:
	return service.validate(self, payload) if is_instance_valid(service) else DropValidation.invalid("Customer service is unavailable")


func try_apply_drop(payload: HeldItemPayload) -> bool:
	return is_instance_valid(service) and service.try_handoff(self, payload)


func on_rejected_release(_payload: HeldItemPayload, validation: DropValidation) -> void:
	if is_instance_valid(service) and is_instance_valid(service.controller):
		service.controller.report_hint(validation.reason_key)


func set_highlight(valid: bool) -> void:
	if is_instance_valid(customer): customer.set_drop_highlight(true, Color("8cdb95") if valid else Color("e29d8f"))


func clear_highlight() -> void:
	if is_instance_valid(customer): customer.set_drop_highlight(false)


func _exit_tree() -> void:
	clear_highlight()
	if is_instance_valid(service) and is_instance_valid(service.controller): service.controller.unregister_drop_zone(self)
