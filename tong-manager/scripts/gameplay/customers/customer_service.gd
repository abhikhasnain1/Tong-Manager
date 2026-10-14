class_name CustomerService
extends Node
## Records a real serving attempt, then publishes its immutable customer response.
## Only accepted servings transfer ownership and reach the payment owner.

signal targets_changed
signal service_accepted(record: Dictionary)
signal service_resolved(record: Dictionary)

var screen: Node2D
var controller: InteractionController
var queue: CustomerQueueManager
var payments: CustomerPayments
var cup_returns: Node
var _zones: Dictionary = {}
var _records: Dictionary = {}
var _order_handoffs: Dictionary = {}
var _attempted_payloads: Dictionary = {}
var _served_cups: Dictionary = {}
var _returned_cup_receipts: Dictionary = {}
var _holding: Node2D
var _frame: Sprite2D
var _frame_image: Image
var _sequence := 0
var _committing := false


func configure(owner_screen: Node2D, interaction: InteractionController, customer_queue: CustomerQueueManager) -> void:
	screen = owner_screen
	controller = interaction
	queue = customer_queue
	_holding = Node2D.new()
	_holding.name = "ServedCups"
	_holding.visible = false
	add_child(_holding)
	_frame = screen.get_node("WorldRoot/FrameFront") as Sprite2D
	if _frame.texture != null:
		_frame_image = _frame.texture.get_image()
		if _frame_image != null and _frame_image.is_compressed(): _frame_image.decompress()
	queue.customer_spawned.connect(_on_spawned)
	queue.customer_removed.connect(_on_removed)
	_sync_targets()


func _process(_delta: float) -> void:
	# Also covers explicit queue stops/restarts and actors removed by callers.
	_sync_targets()


func _on_spawned(_customer: Customer, _entry: Dictionary) -> void:
	_sync_targets()


func _on_removed(_entry: Dictionary, _reason: StringName) -> void:
	_sync_targets()


func _sync_targets() -> void:
	if not _live(queue) or not _live(controller): return
	var actors := queue.get_active_customers()
	var changed := false
	for identity in _zones.keys():
		var zone: Variant = _zones[identity]
		if not _live(zone) or not actors.has(zone.customer):
			_zones.erase(identity)
			if is_instance_valid(zone):
				controller.unregister_drop_zone(zone)
				zone.clear_highlight()
				zone.queue_free()
			changed = true
	for actor in actors:
		if _zones.has(actor.get_instance_id()): continue
		var zone := CustomerServiceZone.new()
		zone.name = "CustomerHandoff"
		actor.add_child(zone)
		zone.configure(self, actor)
		_zones[actor.get_instance_id()] = zone
		changed = true
	if changed: targets_changed.emit()


func get_drop_targets() -> Array[DropZone]:
	var result: Array[DropZone] = []
	for zone: Variant in _zones.values():
		if _live(zone) and _live(zone.customer): result.append(zone)
	return result


func pick_customer_at(viewport_position: Vector2) -> Customer:
	var front := pick_visible_customer_at(viewport_position)
	return front if front != null and front.is_serve_enabled() else null


func pick_visible_customer_at(viewport_position: Vector2) -> Customer:
	if not _live(screen) or not _live(queue) or not viewport_position.is_finite(): return null
	# Modal export has its own input policy in the controller. Geometry must not
	# globally block it just because the full notebook is still open.
	if _live(_frame) and _frame.is_visible_in_tree() and _frame_image != null:
		var point := _frame.get_global_transform_with_canvas().affine_inverse() * viewport_position
		if Rect2(Vector2.ZERO, _frame_image.get_size()).has_point(point) and _frame_image.get_pixelv(Vector2i(point)).a > 0.1:
			return null
	for hanging: HangingSourceBody in screen.hanging_sources:
		if _live(hanging) and hanging.is_visible_in_tree() and hanging.contains_pointer(viewport_position): return null
	var front: Customer
	for actor in queue.get_active_customers():
		if not _belongs(actor) or not actor.is_visible_in_tree(): continue
		var world_point := actor.get_canvas_transform().affine_inverse() * viewport_position
		if not actor.contains_visual_point(world_point): continue
		if front == null or actor.z_index > front.z_index or (actor.z_index == front.z_index and actor.is_greater_than(front)):
			front = actor
	# Arriving/departing bodies still occlude a customer standing behind them.
	return front


func validate(zone: CustomerServiceZone, payload: HeldItemPayload, reservation_claimed := false) -> DropValidation:
	if (not _live(self) or not _live(screen) or not screen.is_ancestor_of(self)
		or not _belongs(queue) or not _belongs(controller) or not _live(zone)
		or zone.service != self or not _live(zone.customer)
		or _zones.get(zone.customer.get_instance_id()) != zone
		or not _belongs(zone.customer) or not zone.customer.is_ancestor_of(zone) or not zone.customer.is_serve_enabled()):
		return DropValidation.invalid("This customer is no longer waiting")
	var order := queue.get_order_for_customer(zone.customer)
	if order == null or order != zone.customer.order or order.closed or _order_handoffs.has(order.order_id):
		return DropValidation.invalid("This order is no longer waiting")
	if (payload == null or not controller.can_address_drop_zone(payload, zone)
		or (not controller.is_modal_export_active() and controller.current_mode != InteractionController.MODE_INTERACT)
		or not _belongs(payload.world_node)):
		return DropValidation.invalid("Use a cup or a ready snack from this stall")
	if _attempted_payloads.has(payload.get_instance_id()):
		return DropValidation.invalid("This serving attempt is already recorded")
	if payload.metadata.get("category") == &"cup":
		var cup := payload.world_node as Cup
		if (cup == null or not cup.assigned_order_id.is_empty() or payload.source != &"cup"
			or payload.quantity != 1 or payload.item_id != StringName(cup.name)
			or payload.metadata.has("portion") or bool(payload.metadata.get("transient", false))):
			return DropValidation.invalid("Use the original held cup")
		var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
		if handle == null or not _live(handle.surface) or not handle.surface.is_registered(cup):
			return DropValidation.invalid("This cup is no longer on the table")
	elif payload.metadata.get("category") == &"ready_item":
		var portion := payload.metadata.get("portion") as IngredientPortion
		if (portion == null or portion.source_ref == null or not _belongs(portion.source_ref.get_ref())
			or portion.quantity != 1 or portion.unit != &"piece"
			or payload.item_id != portion.item_id or payload.quantity != portion.quantity
			or payload.metadata.get("item_id") != portion.item_id or payload.metadata.get("unit") != portion.unit
			or payload.metadata.get("quantity") != portion.quantity or payload.metadata.get("source_id") != portion.source_id
			or payload.metadata.get("cleanup_callback") != Callable(portion, "cancel")
			or not bool(payload.metadata.get("transient", false))):
			return DropValidation.invalid("Use the original held snack")
		if not reservation_claimed and not portion.is_available():
			return DropValidation.invalid("This snack is no longer available")
	else:
		return DropValidation.invalid("Serve a cup or a ready snack")
	var evaluation := ServiceEvaluation.evaluate(order, _offered(payload))
	if evaluation.can_handoff: return DropValidation.valid()
	return DropValidation.invalid("Fill the cup before serving" if evaluation.failure_reason == &"empty_cup" else "This serving is unavailable")


func try_handoff(zone: CustomerServiceZone, payload: HeldItemPayload) -> bool:
	if _committing or not validate(zone, payload).is_valid: return false
	_committing = true
	_sequence += 1
	var handoff_id := StringName("handoff_%s_%s" % [get_instance_id(), _sequence])
	var self_ref: WeakRef = weakref(self)
	var portion := payload.metadata.get("portion") as IngredientPortion
	var order := queue.get_order_for_customer(zone.customer)
	var response := ServiceResult.create_evaluated(handoff_id, order, ServiceEvaluation.evaluate(order, _offered(payload)))
	var applied := false
	if response != null:
		# A refused piece is still only reserved. Do not enter the consumption
		# transaction; ordinary gesture cleanup releases the untouched portion.
		if portion != null and response.get_snapshot().accepted:
			applied = portion.commit(_commit_authority.bind(zone, payload, handoff_id, true))
		else:
			applied = _commit_authority(zone, payload, handoff_id, false)
	if self_ref.get_ref() == null: return applied
	_committing = false
	if applied:
		# Publish after controller cleanup, so observers cannot interrupt the
		# gesture which has already consumed stock or transferred cup ownership.
		_publish_committed.call_deferred(handoff_id)
	return applied


func _commit_authority(zone: CustomerServiceZone, payload: HeldItemPayload, handoff_id: StringName, reservation_claimed: bool) -> bool:
	if not validate(zone, payload, reservation_claimed).is_valid: return false
	var actor := zone.customer
	var order := queue.get_order_for_customer(actor)
	var evaluation := ServiceEvaluation.evaluate(order, _offered(payload))
	var result := ServiceResult.create_evaluated(handoff_id, order, evaluation)
	if result == null: return false
	var response := result.get_snapshot()
	if payload.metadata.get("portion") != null and bool(response.accepted) != reservation_claimed:
		return false
	var cup := payload.world_node as Cup
	if cup != null and response.accepted and not cup.commit_served(order.order_id): return false
	# These authority writes emit no signals. Re-entry can only see the complete
	# result once the provider publishes its committed stock change.
	var recorded := order.record_result(result)
	assert(recorded, "Validated handoff must record exactly once")
	if not recorded: return false
	var record := {"handoff_id": handoff_id, "order_id": order.order_id,
		"customer_id": order.customer_id, "request": order.get_request(),
		"price": order.get_request().price, "result": response,
		"payment_generation": payments.finance.generation if is_instance_valid(payments) and payments.finance != null else -1,
		"payment_binding": payments.get_binding_snapshot() if is_instance_valid(payments) else {},
		"served_cup_id": cup.get_instance_id() if cup != null and response.accepted else 0,
		"returned_cup_id": cup.get_instance_id() if cup != null and not response.accepted else 0}
	_records[handoff_id] = {"record": record, "result": result, "customer": weakref(actor), "published": false}
	_attempted_payloads[payload.get_instance_id()] = handoff_id
	if order.closed: _order_handoffs[order.order_id] = handoff_id
	if cup != null and response.accepted:
		_served_cups[order.order_id] = cup
		queue.hold_for_cup_return(order.order_id)
	# Queue the immutable receipt before callbacks can retire this scene. Its
	# run-owned consumer settles money after the input transaction has finished.
	if response.accepted and cup == null and is_instance_valid(payments):
		payments.enqueue_accepted(self, record, actor.bubble_anchor.get_global_transform_with_canvas().origin)
	if cup != null:
		if response.accepted:
			_retain_cup(cup)
			if _live(cup_returns): cup_returns.register_accepted_cup(record, actor, cup)
		else: controller.restore_drag_origin()
	return true


func _retain_cup(cup: Cup) -> void:
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle != null and _live(handle.surface): handle.surface.unregister_item(cup)
	for node in cup.find_children("*", "", true, false):
		if node is DropZone: controller.unregister_drop_zone(node)
	cup.input_pickable = false
	cup.process_mode = Node.PROCESS_MODE_DISABLED
	cup.hide()
	if _live(cup) and _live(_holding): cup.reparent(_holding, true)


func _publish_committed(handoff_id: StringName) -> void:
	if not _records.has(handoff_id) or _records[handoff_id].published: return
	var entry: Dictionary = _records[handoff_id]
	entry.published = true
	var record: Dictionary = entry.record.duplicate(true)
	var actor: Variant = (entry.customer as WeakRef).get_ref()
	var cup := get_served_cup(record.order_id)
	var self_ref: WeakRef = weakref(self)
	if _live(actor): actor.apply_service_result(entry.result)
	if self_ref.get_ref() == null: return
	if _live(cup): cup.notify_contents_changed()
	if self_ref.get_ref() == null: return
	targets_changed.emit()
	if self_ref.get_ref() == null: return
	service_resolved.emit(record.duplicate(true))
	if self_ref.get_ref() == null: return
	if record.result.accepted: service_accepted.emit(record.duplicate(true))


func get_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for entry: Dictionary in _records.values(): records.append(entry.record.duplicate(true))
	return records


func get_served_cup(order_id: StringName) -> Cup:
	var cup: Variant = _served_cups.get(order_id)
	return cup as Cup if _live(cup) else null


func get_receipt_customer(handoff_id: StringName) -> Customer:
	if not _records.has(handoff_id): return null
	var actor: Variant = (_records[handoff_id].customer as WeakRef).get_ref()
	return actor as Customer if _live(actor) else null


func is_payment_due(receipt: Dictionary) -> bool:
	var handoff_id: StringName = receipt.get("handoff_id", &"")
	if not _records.has(handoff_id) or _records[handoff_id].record != receipt:
		return false
	if not receipt.get("result", {}).get("accepted", false): return false
	return int(receipt.get("served_cup_id", 0)) == 0 or _returned_cup_receipts.has(handoff_id)


func authorize_returned_cup(owner: Node, order_id: StringName, cup: Cup, origin: Vector2) -> bool:
	if (not _live(owner) or owner != cup_returns or not _live(cup)
		or _served_cups.get(order_id) != cup or not owner.is_return_completed(order_id, cup)):
		return false
	var handoff_id: StringName = _order_handoffs.get(order_id, &"")
	if not _records.has(handoff_id) or _returned_cup_receipts.has(handoff_id): return false
	_returned_cup_receipts[handoff_id] = true
	_served_cups.erase(order_id)
	# The destination already owns the exact cup. This queues immutable payment
	# facts before observers can retire the serving scene; publication is deferred.
	if is_instance_valid(payments): payments.enqueue_accepted(self, _records[handoff_id].record, origin)
	return true


func _offered(payload: HeldItemPayload) -> Dictionary:
	if payload.world_node is Cup: return (payload.world_node as Cup).get_service_snapshot()
	var portion := payload.metadata.get("portion") as IngredientPortion
	return {"kind": &"ready_item", "item_id": portion.item_id, "quantity": portion.quantity, "unit": portion.unit} if portion != null else {}


func _belongs(node: Variant) -> bool:
	return _live(node) and _live(screen) and screen.is_ancestor_of(node)


static func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
