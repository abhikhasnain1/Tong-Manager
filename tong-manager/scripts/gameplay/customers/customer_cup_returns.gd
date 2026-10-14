class_name CustomerCupReturns
extends Node
## Same-cup custody after accepted drinks. Full surfaces defer return without
## changing patience, service history, stock, or the quoted payment.

signal return_changed(order_id: StringName)
signal cup_returned(order_id: StringName, cup: Cup)

@export var config: CupReturnConfig = preload("res://data/balance/cup_returns.tres")
const RETRY_SECONDS := 0.4

var screen: Node2D
var controller: InteractionController
var queue: CustomerQueueManager
var service: CustomerService
var transfers: Node
var _display: Node2D
var _world: Node2D
var _entries: Dictionary = {}
var _advancing := false


func configure(owner_screen: Node2D, interaction: InteractionController, customer_queue: CustomerQueueManager,
		customer_service: CustomerService, cup_transfers: Node) -> void:
	if is_instance_valid(screen) and screen.visibility_changed.is_connected(_resume_return_completions):
		screen.visibility_changed.disconnect(_resume_return_completions)
	screen = owner_screen
	screen.visibility_changed.connect(_resume_return_completions)
	controller = interaction
	queue = customer_queue
	service = customer_service
	transfers = cup_transfers
	_world = screen.get_node("WorldRoot") as Node2D
	_display = service.get_node_or_null("CupReturnDisplay") as Node2D
	if _display == null:
		_display = Node2D.new()
		_display.name = "CupReturnDisplay"
		_display.z_index = 11 # Above customer bodies, behind the counter and tools.
		service.add_child(_display)
	service.cup_returns = self
	for receipt in service.get_records():
		var cup := service.get_served_cup(receipt.order_id)
		if cup != null: register_accepted_cup(receipt, service.get_receipt_customer(receipt.handoff_id), cup)


func register_accepted_cup(receipt: Dictionary, actor: Customer, cup: Cup) -> bool:
	if not _context_live() or not _live(cup) or not screen.is_ancestor_of(cup): return false
	var order_id: StringName = receipt.get("order_id", &"")
	if (_entries.has(order_id) or receipt not in service.get_records()
		or service.get_served_cup(order_id) != cup or cup.state != Cup.CupState.SERVED
		or not receipt.get("result", {}).get("accepted", false)):
		return false
	var basis := _world.global_transform.affine_inverse() * cup.global_transform
	var entry := {"order_id": order_id, "handoff_id": receipt.handoff_id, "cup": weakref(cup),
		"actor": weakref(actor) if is_instance_valid(actor) else null, "phase": &"drinking",
		"drinking_remaining": config.safe_drinking_seconds(), "attention_remaining": config.safe_attention_seconds(),
		"retry_remaining": 0.0, "basis": basis, "last_position": basis.origin,
		"started_frame": Engine.get_process_frames(), "origin": Vector2.ZERO}
	_entries[order_id] = entry
	cup.reparent(_display, true)
	cup.input_pickable = false
	cup.process_mode = Node.PROCESS_MODE_DISABLED
	cup.hide()
	queue.hold_for_cup_return(order_id)
	_position_entry(entry, cup)
	return true


func _process(delta: float) -> void:
	_advance(delta, true)


func advance(delta: float) -> void:
	_advance(delta, false)


func _advance(delta: float, automatic: bool) -> void:
	if _advancing or not _context_live() or not is_finite(delta) or delta < 0.0: return
	_advancing = true
	var self_ref: WeakRef = weakref(self)
	for order_id in _entries.keys():
		var entry: Dictionary = _entries[order_id]
		if entry.phase == &"returned":
			if entry.get("completion_pending", false): _finish_return(order_id)
			if self_ref.get_ref() == null: return
			if not _context_live(): break
			continue
		if entry.phase == &"missing": continue
		var cup: Variant = entry.cup.get_ref()
		if not _live(cup) or not screen.is_ancestor_of(cup):
			entry.phase = &"missing"
			continue
		if transfers.is_transferring(cup):
			# The collection clock stays live; only automatic custody transfer is
			# deferred while the player's gesture owns the cup.
			entry.attention_remaining = maxf(0.0, entry.attention_remaining - delta)
			if entry.attention_remaining <= 0.0: entry.phase = &"waiting_for_space"
			continue
		_position_entry(entry, cup)
		if automatic and entry.started_frame == Engine.get_process_frames(): continue
		var remaining_delta := delta
		if entry.phase == &"drinking":
			remaining_delta = maxf(0.0, delta - entry.drinking_remaining)
			entry.drinking_remaining = maxf(0.0, entry.drinking_remaining - delta)
			if entry.drinking_remaining > 0.0: continue
			# Stage the owner phase first; cup observers see coherent dirty custody.
			entry.phase = &"attention"
			var changed: bool = cup.finish_consumption()
			if self_ref.get_ref() == null: return
			if not _context_live(): break
			if not changed or not _live(cup):
				entry.phase = &"missing"
				continue
			cup.show()
			var actor: Variant = _actor(entry)
			if _live(actor): actor.show_cup_return(true)
			return_changed.emit(order_id)
			if self_ref.get_ref() == null: return
			if not _context_live(): break
			if remaining_delta <= 0.0: continue
		entry.attention_remaining = maxf(0.0, entry.attention_remaining - remaining_delta)
		if entry.attention_remaining > 0.0: continue
		entry.phase = &"waiting_for_space"
		entry.retry_remaining = maxf(0.0, entry.retry_remaining - remaining_delta)
		if entry.retry_remaining > 0.0: continue
		entry.retry_remaining = RETRY_SECONDS
		if transfers.try_place_on_free_surface(cup): _commit_return(cup, order_id)
		if self_ref.get_ref() == null: return
		if not _context_live(): break
	_advancing = false


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries.values():
		var cup: Variant = entry.cup.get_ref()
		result.append({"order_id": entry.order_id, "handoff_id": entry.handoff_id, "phase": entry.phase,
			"drinking_remaining": entry.drinking_remaining, "attention_remaining": entry.attention_remaining,
			"cup_id": cup.get_instance_id() if is_instance_valid(cup) else 0,
			"customer_present": _live(_actor(entry))})
	return result


func get_dirty_return_cup(order_id: StringName) -> Cup:
	if not _entries.has(order_id): return null
	var entry: Dictionary = _entries[order_id]
	var cup: Variant = entry.cup.get_ref()
	return cup as Cup if _live(cup) and entry.phase in [&"attention", &"waiting_for_space"] else null


func get_return_pick_point(order_id: StringName) -> Vector2:
	var cup := get_dirty_return_cup(order_id)
	return cup.get_global_transform_with_canvas().origin if cup != null else Vector2.INF


func begin_return(order_id: StringName, viewport_point: Vector2) -> bool:
	var cup := get_dirty_return_cup(order_id)
	if (not _context_live() or not screen.is_visible_in_tree() or cup == null or not viewport_point.is_finite()
		or controller.current_mode != InteractionController.MODE_INTERACT or not controller.can_start_world_action()
		or controller.is_pointer_over_ui_at(viewport_point)):
		return false
	return transfers.begin_transfer(cup, viewport_point, self, _validate_return.bind(order_id), _commit_return.bind(order_id))


func _validate_return(cup: Cup, order_id: StringName) -> bool:
	return (_context_live() and get_dirty_return_cup(order_id) == cup
		and screen.is_ancestor_of(cup) and service.get_served_cup(order_id) == cup and cup.state == Cup.CupState.DIRTY)


func is_return_completed(order_id: StringName, cup: Cup) -> bool:
	return (_entries.has(order_id) and _entries[order_id].phase == &"returned"
		and _entries[order_id].cup.get_ref() == cup)


func _commit_return(cup: Cup, order_id: StringName) -> void:
	if not _validate_return(cup, order_id): return
	var entry: Dictionary = _entries[order_id]
	entry.phase = &"returned"
	entry.completion_pending = true
	# The transfer has committed placement/bucket custody before this callback.
	# Authorize the immutable receipt now; money and departure publish later.
	service.authorize_returned_cup(self, order_id, cup, entry.origin)
	_finish_return.call_deferred(order_id)


func _finish_return(order_id: StringName) -> void:
	if not _context_live() or not _entries.has(order_id) or _entries[order_id].phase != &"returned": return
	var entry: Dictionary = _entries[order_id]
	if not entry.get("completion_pending", false): return
	var actor: Variant = _actor(entry)
	# Customer.leave intentionally refuses hidden actors. Keep its departure
	# pending while custody/payment are already committed, then resume on show.
	if _live(actor) and not actor.is_visible_in_tree(): return
	if _live(actor): actor.show_cup_return(false)
	if not _context_live() or (_live(actor) and not actor.is_visible_in_tree()): return
	entry.completion_pending = false
	var self_ref: WeakRef = weakref(self)
	queue.complete_cup_return(order_id)
	if self_ref.get_ref() == null or not _context_live(): return
	var cup: Variant = entry.cup.get_ref()
	if _live(cup): cup_returned.emit(order_id, cup)
	if self_ref.get_ref() != null: return_changed.emit(order_id)


func _resume_return_completions() -> void:
	if not _context_live() or not screen.is_visible_in_tree(): return
	for order_id in _entries:
		if _entries[order_id].get("completion_pending", false):
			_finish_return.call_deferred(order_id)


func _position_entry(entry: Dictionary, cup: Cup) -> void:
	var actor: Variant = _actor(entry)
	if _live(actor):
		var offset := config.attention_offset if config.attention_offset.is_finite() else Vector2(62, -154)
		entry.last_position = _world.to_local(actor.get_cup_return_position(offset))
	var transform: Transform2D = _world.global_transform * entry.basis
	transform.origin = _world.to_global(entry.last_position)
	cup.global_transform = transform
	entry.origin = cup.get_global_transform_with_canvas().origin


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	if not _context_live() or not screen.is_visible_in_tree() or not controller.can_start_world_action(): return
	var front := service.pick_visible_customer_at(event.position)
	for order_id in _entries:
		var cup := get_dirty_return_cup(order_id)
		if cup == null or not cup.is_visible_in_tree(): continue
		var actor: Variant = _actor(_entries[order_id])
		if front != null and front != actor: continue
		var sprite := cup.get_node("Sprite2D") as Sprite2D
		var transform := sprite.get_global_transform_with_canvas()
		if not transform.is_finite() or is_zero_approx(transform.determinant()): continue
		if not sprite.get_rect().has_point(transform.affine_inverse() * event.position): continue
		# The front counter/hanging items also own input before the offered cup.
		if _live(actor) and front != actor: continue
		if begin_return(order_id, event.position):
			get_viewport().set_input_as_handled()
			return


func _actor(entry: Dictionary) -> Variant:
	var reference: Variant = entry.actor
	var actor: Variant = reference.get_ref() if reference is WeakRef else null
	return actor if _live(actor) and actor.order != null and actor.order.order_id == entry.order_id else null


func _context_live() -> bool:
	# Visibility only gates input. Consumption/return authority must complete
	# even when an observer hides the retained screen during its notification.
	return (_live(self) and _live(screen) and screen.is_ancestor_of(self)
		and _live(service) and service.cup_returns == self and _live(queue) and _live(controller)
		and _live(transfers) and _live(_display) and _live(_world)
		and screen.is_ancestor_of(service) and screen.is_ancestor_of(queue)
		and screen.is_ancestor_of(controller) and screen.is_ancestor_of(transfers)
		and service.is_ancestor_of(_display) and screen.is_ancestor_of(_world))


static func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
