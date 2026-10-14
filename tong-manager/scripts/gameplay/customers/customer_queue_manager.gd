class_name CustomerQueueManager
extends Node
## One selected day's queue. Scheduling never evaluates service or changes supplies.

signal customer_spawned(customer: Customer, entry_snapshot: Dictionary)
signal customer_timed_out(customer: Customer, entry_snapshot: Dictionary)
signal customer_removed(entry_snapshot: Dictionary, reason: StringName)
signal queue_completed(summary: Dictionary)

@export var customer_scene: PackedScene = preload("res://scenes/gameplay/customers/Customer.tscn")
@export var actor_scale := Vector2(1.4, 1.4)
@export var reduced_motion := false
@export_range(0.0, 5.0, 0.05) var served_reaction_seconds := 0.9
@export_range(0.0, 5.0, 0.05) var refused_reaction_seconds := 0.25

var _slots: Array[Marker2D] = []
var _active_parent: Node2D
var _catalog: Node
var _context: Node
var _plan: Array[Dictionary] = []
var _active: Dictionary = {}
var _history: Array[Dictionary] = []
var _errors := PackedStringArray()
var _running := false
var _completed := false
var _advancing := false
var _generation := 0
var _run_counter := 0
var _used_run_ids: Dictionary = {}
var _run_id: StringName
var _schedule_id: StringName
var _mode := 0
var _seed := 0
var _capacity := 0
var _reaction_seconds := 0.8
var _elapsed := 0.0
var _next := 0
var _last_spawn := 0.0
var _last_due := 0.0


func configure(slots: Array[Marker2D], active_parent: Node2D, catalog: Node) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not _node_live(active_parent) or not _node_live(catalog) or slots.is_empty(): return false
	var context := get_parent()
	if not _node_live(context) or not context.is_ancestor_of(active_parent): return false
	var seen: Dictionary = {}
	for slot in slots:
		if not _node_live(slot) or not context.is_ancestor_of(slot) or seen.has(slot.get_instance_id()): return false
		seen[slot.get_instance_id()] = true
	reset()
	_slots = slots.duplicate()
	_active_parent = active_parent
	_catalog = catalog
	_context = get_parent()
	return _context_live()


func start(day: Resource, seed_value: int = 0, run_id: StringName = &"") -> bool:
	_errors.clear()
	if not _context_live() or day == null or customer_scene == null:
		_errors.append("Queue needs a live configured scene and DayConfig")
		return false
	if not actor_scale.is_finite() or actor_scale.x <= 0.0 or actor_scale.y <= 0.0:
		_errors.append("Customer scale must be finite and positive")
		return false
	var schedule := day.get("customer_schedule") as CustomerSchedule
	if schedule == null:
		_errors.append("DayConfig needs a CustomerSchedule")
		return false
	var identity := run_id if not run_id.is_empty() else StringName("queue_%s_%s" % [get_instance_id(), _run_counter + 1])
	if _used_run_ids.has(identity):
		_errors.append("Run ID was already used; supply a fresh identity")
		return false
	var compiled := schedule.compile(day, _catalog, seed_value, identity)
	_errors = compiled.errors.duplicate()
	if not compiled.ok: return false
	if compiled.max_active > _live_slot_count():
		_errors.append("Queue capacity exceeds the available authored slots")
		return false
	var probe := customer_scene.instantiate()
	if not probe is Customer:
		probe.free()
		_errors.append("Customer scene must have a Customer root")
		return false
	probe.free()
	stop()
	_run_counter += 1
	_used_run_ids[identity] = true
	_run_id = identity
	_schedule_id = compiled.id
	_mode = compiled.mode
	_seed = seed_value
	_capacity = compiled.max_active
	_reaction_seconds = compiled.timeout_reaction_seconds
	_plan.assign(compiled.entries.duplicate(true))
	_history.clear()
	_next = 0
	_elapsed = 0.0
	_last_spawn = 0.0
	_last_due = 0.0
	_completed = false
	_running = true
	_check_completed()
	return true


func stop() -> void:
	_generation += 1
	_running = false
	var old := _active.values()
	_active.clear()
	for entry: Dictionary in old:
		entry.phase = &"removed"
		entry.reason = &"stopped"
		_history.append(_entry_snapshot(entry))
		_dispose_actor(entry.actor)


func reset() -> void:
	stop()
	_plan.clear()
	_history.clear()
	_errors.clear()
	_run_id = &""
	_schedule_id = &""
	_elapsed = 0.0
	_next = 0
	_capacity = 0
	_completed = false


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	_advance(delta, true)


func advance(delta: float) -> void:
	_advance(delta, false)


func _advance(delta: float, automatic: bool) -> void:
	if not _running or _advancing or not is_finite(delta) or delta < 0.0: return
	if not is_finite(_elapsed + delta): return
	if not _context_live() or _live_slot_count() == 0:
		stop()
		return
	_advancing = true
	var epoch := _generation
	_elapsed += delta
	for key in _active.keys():
		if epoch != _generation or not _running: break
		if not _active.has(key): continue
		var entry: Dictionary = _active[key]
		if not _actor_live(entry.actor) or not _slot_live(entry.slot_index) or entry.actor.order != entry.order:
			_remove_entry(key, &"removed", epoch)
			continue
		var actor: Customer = entry.actor
		if actor.state == Customer.State.LEAVING and entry.phase != &"timeout_reaction": entry.phase = &"leaving"
		if entry.phase == &"waiting":
			_consume_recorded_responses(entry, automatic)
			if entry.order.closed:
				var accepted: bool = entry.order.fulfilled
				entry.reason = &"fulfilled" if accepted else &"refused"
				entry.phase = &"served_reaction" if accepted else &"refused_reaction"
				var duration := served_reaction_seconds if accepted else refused_reaction_seconds
				entry.reaction_remaining = maxf(0.0, duration) if is_finite(duration) else (0.9 if accepted else 0.25)
				if entry.reaction_remaining <= 0.0: _begin_departure(entry)
				continue
			# Arrival can finish before this node processes the same frame. That
			# frame's delta includes travel time, so begin charging next frame.
			if automatic and entry.waiting_frame == Engine.get_process_frames(): continue
			entry.patience_remaining = maxf(0.0, entry.patience_remaining - delta)
			if entry.patience_remaining <= 0.0:
				entry.phase = &"timeout_reaction"
				entry.reason = &"timeout"
				entry.reaction_remaining = _reaction_seconds
				if not actor.prepare_timeout_departure():
					if _entry_current(key, actor, epoch): _remove_entry(key, &"removed", epoch)
					continue
				if not _entry_current(key, actor, epoch): continue
				if entry.order.closed:
					entry.reason = &"fulfilled" if entry.order.fulfilled else &"refused"
					_begin_departure(entry)
					continue
				customer_timed_out.emit(actor, _entry_snapshot(entry))
				if _entry_current(key, actor, epoch) and _reaction_seconds <= 0.0: _begin_departure(entry)
		elif entry.phase in [&"timeout_reaction", &"served_reaction", &"refused_reaction"]:
			entry.reaction_remaining = maxf(0.0, entry.reaction_remaining - delta)
			if entry.reaction_remaining <= 0.0: _begin_departure(entry)
	if epoch == _generation and _running:
		_spawn_due(epoch)
		if epoch == _generation: _check_completed()
	_advancing = false


func _consume_recorded_responses(entry: Dictionary, automatic: bool) -> void:
	# Consume authoritative attempts, not optional presentation callbacks. A
	# replayed refusal cannot repeatedly reset the same visit's patience.
	for result: Dictionary in entry.order.get_results():
		if entry.handled_responses.has(result.handoff_id): continue
		entry.handled_responses[result.handoff_id] = true
		if result.get("response") == &"refuse_retry" and result.get("remake_patience") == &"reset":
			entry.patience_remaining = entry.patience_seconds
			if automatic: entry.waiting_frame = Engine.get_process_frames()


func get_snapshot() -> Dictionary:
	return {"run_id": _run_id, "schedule_id": _schedule_id, "mode": _mode, "seed": _seed,
		"running": _running, "completed": _completed, "elapsed": _elapsed, "total": _plan.size(),
		"spawned": _next, "removed": _history.size(), "pending": _plan.size() - _next,
		"max_active": _capacity, "active": get_active_entries(), "history": _history.duplicate(true),
		"errors": _errors.duplicate()}


func get_active_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _active.values(): result.append(_entry_snapshot(entry))
	return result


func get_active_customers() -> Array[Customer]:
	var result: Array[Customer] = []
	for entry: Dictionary in _active.values():
		if _actor_live(entry.actor): result.append(entry.actor)
	return result


func get_order_for_customer(customer: Variant) -> OrderState:
	for entry: Dictionary in _active.values():
		if entry.actor == customer and _actor_live(customer): return entry.order
	return null


func _spawn_due(epoch: int) -> void:
	if _next >= _plan.size() or _active.size() >= _capacity: return
	var source: Dictionary = _plan[_next]
	var due: float = source.due_seconds
	if _next > 0: due = maxf(due, _last_spawn + source.due_seconds - _last_due)
	if _elapsed < due: return
	var slot_index := _free_slot()
	if slot_index < 0: return
	var actor := customer_scene.instantiate() as Customer
	if actor == null:
		_errors.append("Customer scene changed to an incompatible root")
		stop()
		return
	var order := OrderState.create(source.order_id, source.customer_id, source.request, _elapsed, source.service_policy)
	if order == null:
		actor.free()
		_errors.append("Compiled order is invalid")
		stop()
		return
	var entry := source.duplicate(true)
	entry.merge({"actor": actor, "order": order, "slot_index": slot_index, "phase": &"arriving",
		"spawned_at": _elapsed, "patience_remaining": source.patience_seconds,
		"reaction_remaining": 0.0, "arrival_started": false, "waiting_frame": -1, "reason": &"", "handled_responses": {}})
	_active[entry.visit_id] = entry
	_next += 1
	_last_spawn = _elapsed
	_last_due = source.due_seconds
	actor.auto_arrive = false
	actor.reduced_motion = reduced_motion
	actor.customer_def = _profile_from_snapshot(source.profile)
	actor.state_changed.connect(_on_actor_state.bind(entry.visit_id, actor, epoch))
	actor.departure_finished.connect(_on_departure.bind(entry.visit_id, actor, epoch))
	actor.tree_exiting.connect(_on_actor_exit.bind(entry.visit_id, actor, epoch))
	_active_parent.add_child(actor)
	if not _entry_current(entry.visit_id, actor, epoch):
		_remove_entry(entry.visit_id, &"removed", epoch)
		return
	actor.global_position = _slots[slot_index].global_position
	actor.scale = actor_scale
	if not actor.set_order(order) or not _entry_current(entry.visit_id, actor, epoch):
		_remove_entry(entry.visit_id, &"removed", epoch)
		return
	entry.arrival_started = true
	actor.arrive()
	if _entry_current(entry.visit_id, actor, epoch): customer_spawned.emit(actor, _entry_snapshot(entry))


func _on_actor_state(state: Customer.State, key: StringName, actor: Variant, epoch: int) -> void:
	if not _entry_current(key, actor, epoch): return
	var entry: Dictionary = _active[key]
	if state == Customer.State.LEAVING:
		if entry.phase != &"timeout_reaction": entry.phase = &"leaving"
	elif entry.arrival_started and entry.phase == &"arriving" and state in [Customer.State.WAITING, Customer.State.ORDERING, Customer.State.SERVED, Customer.State.REFUSED]:
		entry.phase = &"waiting"
		entry.waiting_frame = Engine.get_process_frames()


func _on_departure(key: StringName, actor: Variant, epoch: int) -> void:
	if _entry_current(key, actor, epoch):
		var reason: StringName = _active[key].reason
		_remove_entry(key, &"departed" if reason.is_empty() else reason, epoch)


func _on_actor_exit(key: StringName, actor: Variant, epoch: int) -> void:
	if epoch == _generation and _active.has(key) and _active[key].actor == actor:
		_remove_entry(key, &"removed", epoch)


func _begin_departure(entry: Dictionary) -> void:
	entry.phase = &"leaving"
	entry.actor.leave()


func _remove_entry(key: StringName, reason: StringName, epoch: int) -> void:
	if epoch != _generation or not _active.has(key): return
	var entry: Dictionary = _active[key]
	_active.erase(key)
	entry.phase = &"removed"
	entry.reason = reason
	var snapshot := _entry_snapshot(entry)
	_history.append(snapshot)
	_dispose_actor(entry.actor)
	if epoch != _generation: return
	customer_removed.emit(snapshot.duplicate(true), reason)
	if epoch == _generation: _check_completed()


func _check_completed() -> void:
	if not _running or _completed or _next < _plan.size() or not _active.is_empty(): return
	_completed = true
	_running = false
	queue_completed.emit(get_snapshot())


func _entry_snapshot(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result.erase("actor")
	result.erase("order")
	result.erase("profile")
	result.erase("arrival_started")
	result.erase("waiting_frame")
	result.erase("handled_responses")
	result["fulfilled"] = entry.order.fulfilled
	result["closed"] = entry.order.closed
	result["service_result"] = entry.order.get_accepted_result()
	result["terminal_result"] = entry.order.get_terminal_result()
	result["service_attempts"] = entry.order.get_results()
	return result


func _entry_current(key: StringName, actor: Variant, epoch: int) -> bool:
	return (epoch == _generation and _running and _active.has(key) and _active[key].actor == actor
		and _actor_live(actor) and _context_live() and _slot_live(_active[key].slot_index))


func _context_live() -> bool:
	return (is_inside_tree() and not is_queued_for_deletion() and _node_live(_context)
		and _context == get_parent() and _node_live(_active_parent) and _context.is_ancestor_of(_active_parent)
		and _node_live(_catalog))


func _actor_live(actor: Variant) -> bool:
	return _node_live(actor) and _node_live(_active_parent) and actor.get_parent() == _active_parent


func _slot_live(index: int) -> bool:
	return index >= 0 and index < _slots.size() and _node_live(_slots[index]) and _node_live(_context) and _context.is_ancestor_of(_slots[index])


func _live_slot_count() -> int:
	var count := 0
	for index in _slots.size():
		if _slot_live(index): count += 1
	return count


func _free_slot() -> int:
	for index in _slots.size():
		if not _slot_live(index): continue
		var occupied := false
		for entry: Dictionary in _active.values():
			if entry.slot_index == index: occupied = true
		if not occupied: return index
	return -1


static func _node_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


static func _dispose_actor(actor: Variant) -> void:
	if is_instance_valid(actor) and actor is Customer and not actor.is_queued_for_deletion():
		actor.hide()
		actor.queue_free()


static func _profile_from_snapshot(data: Dictionary) -> CustomerDef:
	var profile := CustomerDef.new()
	profile.id = data.id
	profile.display_name_key = data.display_name_key
	profile.sprite_texture = data.sprite_texture
	profile.patience_seconds = data.patience_seconds
	profile.dialogue_profile = data.dialogue_profile
	profile.unhappy_response = data.unhappy_response
	profile.remake_patience = data.remake_patience
	return profile
