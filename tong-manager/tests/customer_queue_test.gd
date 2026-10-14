extends SceneTree
## Schedule compilation and queue lifecycle; no inventory/service matching fixture.

var checks := 0
var failures: Array[String] = []
var catalog: Node
var stage: Node2D
var actors: Node2D
var manager: CustomerQueueManager
var slots: Array[Marker2D] = []
var sequence := 0


func _init() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func day(count := 3, gap := 1.0, patience := 10.0, capacity := 2) -> DayConfig:
	var value := DayConfig.new()
	value.customer_count_min = 4
	value.customer_count_max = 5
	var schedule := CustomerSchedule.new()
	schedule.id = &"core_authored"
	schedule.mode = CustomerSchedule.Mode.AUTHORED
	schedule.max_active = capacity
	for index in count:
		var entry := CustomerArrivalDef.new()
		entry.id = StringName("entry_%d" % index)
		entry.due_seconds = float(index) * gap
		entry.customer = catalog.get_customer(&"customer_a" if index % 2 == 0 else &"customer_b")
		entry.request = catalog.get_order_request(&"tea_cha_no_sugar" if index % 2 == 0 else &"ready_banana")
		entry.patience_override = patience
		schedule.arrivals.append(entry)
	value.customer_schedule = schedule
	return value


func start(value: DayConfig) -> bool:
	sequence += 1
	return manager.start(value, 42, StringName("core_run_%d" % sequence))


func setup() -> void:
	stage = Node2D.new()
	root.add_child(stage)
	actors = Node2D.new()
	stage.add_child(actors)
	slots.clear()
	for index in 3:
		var slot := Marker2D.new()
		slot.position = Vector2(200 + index * 250, 500)
		stage.add_child(slot)
		slots.append(slot)
	manager = CustomerQueueManager.new()
	stage.add_child(manager)
	manager.set_process(false)
	manager.reduced_motion = true
	check(manager.configure(slots, actors, catalog), "Queue configures authored slots and parent")


func compilation() -> void:
	var value := day()
	var schedule := value.customer_schedule
	check(schedule.validate(value, catalog).is_empty(), "Authored schedule validates shared profiles and requests")
	var compiled := schedule.compile(value, catalog, 42, &"repeatable")
	check(compiled.ok and compiled.total == 3, "Authored entries override generated 4-5 count")
	check(compiled == schedule.compile(value, catalog, 42, &"repeatable"), "Same seed and run ID reproduce exactly")
	var ids: Dictionary = {}
	for entry: Dictionary in compiled.entries:
		check(not ids.has(entry.order_id), "Each repeated profile visit has a distinct order ID")
		ids[entry.order_id] = true
		check(entry.customer_id in [&"customer_a", &"customer_b"], "Order customer identity remains the profile identity")
		check(OrderState.create(entry.order_id, entry.customer_id, entry.request, 0.0) != null, "Compiled request is a complete valid order snapshot")
	compiled.entries[0].request.kettle_portion_counts[&"black_tea"] = 99
	check(schedule.compile(value, catalog, 42, &"repeatable").entries[0].request.kettle_portion_counts[&"black_tea"] == 1, "Compiled request mutation cannot change shared recipe metadata")
	var saved_id := schedule.id
	schedule.id = &" "
	check(not schedule.validate(value, catalog).is_empty(), "Blank schedule IDs reject")
	schedule.id = saved_id
	schedule.max_active = 0
	check(not schedule.validate(value, catalog).is_empty(), "Zero capacity rejects")
	schedule.max_active = 2
	for bad in [-1.0, INF, NAN]:
		schedule.timeout_reaction_seconds = bad
		check(not schedule.validate(value, catalog).is_empty(), "Invalid reaction timing rejects")
	schedule.timeout_reaction_seconds = 0.8
	var entry := schedule.arrivals[1]
	entry.id = schedule.arrivals[0].id
	check(not schedule.validate(value, catalog).is_empty(), "Duplicate arrival IDs reject")
	entry.id = &"entry_1"
	for bad in [-1.0, INF, NAN]:
		entry.due_seconds = bad
		check(not schedule.validate(value, catalog).is_empty(), "Malformed due time rejects")
		entry.patience_override = bad
		check(not schedule.validate(value, catalog).is_empty(), "Malformed patience rejects")
	entry.due_seconds = 1.0
	entry.patience_override = 10.0
	entry.customer = (catalog.get_customer(&"customer_b") as CustomerDef).duplicate() as CustomerDef
	check(not schedule.validate(value, catalog).is_empty(), "Noncanonical copied profile propagates validation failure")
	entry.customer = catalog.get_customer(&"customer_b")
	entry.request = (catalog.get_order_request(&"ready_banana") as OrderRequestDef).duplicate() as OrderRequestDef
	check(not schedule.validate(value, catalog).is_empty(), "Noncanonical copied request rejects")
	entry.request = catalog.get_order_request(&"ready_banana")
	var profile: CustomerDef = catalog.get_customer(&"customer_b")
	var old_patience := profile.patience_seconds
	profile.patience_seconds = 0.0
	check(not schedule.validate(value, catalog).is_empty(), "Nested invalid profile diagnostics propagate")
	profile.patience_seconds = old_patience
	check(not schedule.compile(value, catalog, 42, &"").ok, "Missing runtime identity rejects")
	var generated: DayConfig = load("res://data/balance/demo_day_1.tres")
	var totals: Dictionary = {}
	for seed_value in 20:
		var result := generated.customer_schedule.compile(generated, catalog, seed_value, &"seed_test")
		check(result.ok and result.total in [4, 5], "Generated schedule follows current DayConfig count range")
		totals[result.total] = true
		for index in result.entries.size():
			check(is_equal_approx(result.entries[index].due_seconds, 3.0 + index * 15.0), "Generated arrivals retain editable stagger")
	check(totals.has(4) and totals.has(5), "Seeded examples exercise both generated daily totals")
	for path in ["res://data/examples/customer_days/authored_day_1.tres", "res://data/examples/customer_days/authored_day_2.tres"]:
		var example := load(path) as DayConfig
		check(example != null and example.customer_schedule.validate(example, catalog).is_empty(), "Authored example loads and validates")
		var result := example.customer_schedule.compile(example, catalog, 1, &"example")
		check(result.total == example.customer_schedule.arrivals.size(), "Authored example length is its sole count authority")
	value = day()
	schedule = value.customer_schedule
	schedule.mode = CustomerSchedule.Mode.GENERATED
	schedule.customer_pool.assign([catalog.get_customer(&"customer_a")])
	value.customer_count_min = 5
	value.customer_count_max = 4
	check(not schedule.validate(value, catalog).is_empty(), "Reversed generated counts reject")
	value.customer_count_min = 0
	value.customer_count_max = 0
	check(schedule.compile(value, catalog, 0, &"empty").total == 0, "An explicit zero-count generated day is valid")


func lifecycle() -> void:
	var value := day(4, 2.0, 100.0)
	check(start(value), "Queue starts a valid authored run")
	manager.advance(0.0)
	check(manager.get_active_entries().size() == 1 and manager.get_active_entries()[0].phase == &"waiting", "Reduced-motion arrival settles into a waiting phase")
	var first := manager.get_active_customers()[0]
	check(first.state == Customer.State.ORDERING, "Assigned-order arrival accepts ORDERING as resting state")
	check(first.global_position.is_equal_approx(slots[0].global_position), "Spawn uses the authored slot anchor")
	check(first.scale == Vector2(1.4, 1.4), "Spawn uses editable accepted actor scale")
	check(manager.get_active_entries()[0].patience_remaining == 100.0, "Initial binding and arrival do not charge patience")
	manager.advance(2.0)
	check(manager.get_active_entries().size() == 2, "Staggered second arrival fills capacity")
	manager.advance(20.0)
	check(manager.get_snapshot().spawned == 2 and manager.get_snapshot().pending == 2, "Full queue defers all due entries without reroll or extra spawn")
	first.leave()
	check(manager.get_active_entries().size() == 1, "Completed departure releases exactly one slot")
	manager.advance(0.0)
	check(manager.get_snapshot().spawned == 3, "Earliest deferred entry takes the freed slot")
	var second := manager.get_active_customers()[0]
	second.leave()
	manager.advance(0.0)
	check(manager.get_snapshot().spawned == 3, "Overdue backlog cannot burst immediately after another departure")
	manager.advance(1.99)
	check(manager.get_snapshot().spawned == 3, "Actual deferred spawn preserves the next authored gap")
	manager.advance(0.01)
	check(manager.get_snapshot().spawned == 4, "Next deferred entry starts after its full scheduled gap")
	var snap := manager.get_snapshot()
	snap.active[0].patience_remaining = 9999.0
	snap.active[0].request.quantity = 99
	check(manager.get_active_entries()[0].patience_remaining < 100.0 and manager.get_active_entries()[0].request.quantity == 1, "Queue snapshots are detached")
	var completed := {"count": 0}
	var on_complete := func(_summary: Dictionary): completed.count += 1
	manager.queue_completed.connect(on_complete)
	for actor in manager.get_active_customers(): actor.leave()
	manager.advance(1000.0)
	check(manager.get_snapshot().completed and completed.count == 1 and manager.get_snapshot().removed == 4, "Exhausted queue completes exactly once after all departures")
	manager.queue_completed.disconnect(on_complete)
	var used: StringName = manager.get_snapshot().run_id
	manager.reset()
	check(not manager.start(value, 42, used), "Reset does not permit reuse of prior run/order identities")
	check(start(day(1)), "Fresh run follows reset")
	manager.advance(0.0)
	var retained := manager.get_active_customers()[0]
	var malformed := day(1)
	malformed.customer_schedule.max_active = 99
	check(not start(malformed) and manager.get_active_customers()[0] == retained, "Invalid start preserves the current active run")
	manager.stop()
	check(not retained.visible and not manager.get_snapshot().running and manager.get_active_customers().is_empty(), "Stop immediately hides and retires actors before deferred deletion")
	check(manager.get_snapshot().total == 1 and manager.get_snapshot().history.size() == 1, "Stop retains a detached run summary")
	check(start(day(3, 0.0, 100.0, 3)), "Alternate authored capacity works with three slots")
	manager.advance(0.0)
	check(manager.get_active_customers().size() == 1, "At most one zero-gap entry spawns per advance")
	manager.advance(0.0)
	manager.advance(0.0)
	check(manager.get_active_customers().size() == 3, "Configured capacity is not hardcoded to two")
	manager.reset()


func timeout_and_authority() -> void:
	var counts := {"timeout": 0, "removed": 0}
	var timeout_observer := func(_actor: Customer, _entry: Dictionary): counts.timeout += 1
	var remove_observer := func(_entry: Dictionary, _reason: StringName): counts.removed += 1
	manager.customer_timed_out.connect(timeout_observer)
	manager.customer_removed.connect(remove_observer)
	check(start(day(1, 0.0, 2.0)), "Timeout run starts")
	manager.advance(0.0)
	var actor := manager.get_active_customers()[0]
	var order := manager.get_order_for_customer(actor)
	manager.advance(2.0)
	check(counts.timeout == 1 and manager.get_active_entries()[0].phase == &"timeout_reaction", "Expiry emits once and enters visible reaction phase")
	check(not actor.is_serve_enabled() and actor.state == Customer.State.LEAVING, "Timeout immediately retires serve eligibility")
	check(actor.emotion_icon.visible and actor.get_presentation_snapshot().emotion == &"unhappy", "Disappointed icon is visible before travel hides feedback")
	check(actor.get_presentation_text() == "Waited too long", "Optional dialogue names timeout without a service result")
	check(not order.fulfilled and order.get_results().is_empty() and actor.get_presentation_snapshot().review_count == 0, "Timeout creates no fulfillment, service result or bad review")
	manager.advance(0.79)
	check(manager.get_active_entries().size() == 1 and counts.removed == 0, "Reaction retains its slot for configured duration")
	manager.advance(0.02)
	manager.advance(10.0)
	check(counts.timeout == 1 and counts.removed == 1 and manager.get_snapshot().completed, "Timeout departure frees once and completes")
	check(start(day(1, 0.0, 2.0)), "Accepted-order run starts")
	manager.advance(0.0)
	actor = manager.get_active_customers()[0]
	order = actor.order
	var accepted := ServiceResult.create(&"accepted", order.order_id, order.customer_id, order.request_kind, true, true)
	check(actor.apply_service_result(accepted), "Existing cold accepted result seam is usable")
	manager.advance(100.0)
	check(counts.timeout == 1 and order.fulfilled and order.get_results().size() == 1, "Accepted order stops patience and cannot become a timeout")
	check(manager.get_active_entries()[0].phase == &"served_reaction", "Accepted service holds its reaction before departure")
	manager.advance(manager.served_reaction_seconds)
	check(order.get_accepted_result().bad_review and manager.get_snapshot().history[0].reason == &"fulfilled", "Queue preserves cold service outcome without duplicating it")
	check(start(day(1, 0.0, 1.0)), "Synchronous acceptance race run starts")
	manager.advance(0.0)
	var race_actor := manager.get_active_customers()[0]
	var race_order := race_actor.order
	var race_accept := ServiceResult.create(&"race_accept", race_order.order_id, race_order.customer_id, race_order.request_kind, true)
	var accept_on_retire := func(state: Customer.State):
		if state == Customer.State.LEAVING: race_order.record_result(race_accept)
	race_actor.state_changed.connect(accept_on_retire)
	manager.advance(1.0)
	check(race_order.fulfilled and counts.timeout == 1 and manager.get_snapshot().history[0].reason == &"fulfilled", "An authoritative acceptance in a synchronous retirement callback cannot emit timeout too")
	manager.customer_timed_out.disconnect(timeout_observer)
	manager.customer_removed.disconnect(remove_observer)


func snapshots_and_removal() -> void:
	var value := day(2, 1.0, 20.0)
	check(start(value), "Snapshot run starts")
	value.customer_schedule.arrivals[0].patience_override = 1.0
	value.customer_schedule.arrivals[1].due_seconds = 999.0
	var profile: CustomerDef = catalog.get_customer(&"customer_b")
	var label := profile.display_name_key
	profile.display_name_key = "edited_after_compile"
	manager.advance(0.0)
	manager.advance(1.0)
	check(manager.get_active_entries().size() == 2 and manager.get_active_entries()[0].patience_seconds == 20.0, "Authored timing and patience edits do not mutate compiled run")
	check(manager.get_active_customers()[1].customer_def.display_name_key == label, "Profile display metadata is copied before later visits spawn")
	profile.display_name_key = label
	var removed: Variant = manager.get_active_customers()[0]
	removed.free()
	manager.advance(0.0)
	check(manager.get_active_customers().size() == 1 and manager.get_snapshot().history.size() == 1, "Immediate actor free recovers capacity safely")
	manager.stop()
	check(start(day(2, 1.0, 20.0)), "Slot removal run starts")
	manager.advance(0.0)
	stage.remove_child(slots[0])
	manager.advance(1.0)
	check(manager.get_active_entries().size() == 1 and manager.get_active_entries()[0].slot_index == 1, "Removed occupied slot retires actor and remaining slot recovers capacity")
	stage.add_child(slots[0])
	manager.reset()
	var restart := {"done": false}
	var replacement := day(1)
	var callback := func(_actor: Customer, _entry: Dictionary):
		if not restart.done:
			restart.done = true
			start(replacement)
	manager.customer_spawned.connect(callback)
	check(start(day(3)), "Reentry run starts")
	manager.advance(0.0)
	check(restart.done and manager.get_snapshot().total == 1 and manager.get_snapshot().spawned == 0, "Spawn observer restart cannot corrupt the replacement run")
	manager.customer_spawned.disconnect(callback)
	manager.advance(0.0)
	check(manager.get_active_customers().size() == 1, "Replacement run remains usable after synchronous callback")
	var foreign := Node2D.new()
	root.add_child(foreign)
	var current_id: StringName = manager.get_snapshot().run_id
	check(not manager.configure(slots, foreign, catalog) and manager.get_snapshot().run_id == current_id and manager.get_active_customers().size() == 1, "Invalid reconfiguration cannot retire the current run")
	foreign.free()
	stage.remove_child(actors)
	manager.advance(0.0)
	check(not manager.get_snapshot().running and manager.get_active_customers().is_empty(), "Removed active parent stops the run without orphan timers")
	stage.add_child(actors)
	check(start(day(1)), "A restored configured parent permits an explicit new run")
	manager.advance(0.0)
	stage.remove_child(manager)
	check(not manager.get_snapshot().running and manager.get_active_customers().is_empty(), "Manager exit clears active actors and stops progression")
	stage.add_child(manager)
	manager.set_process(false)
	manager.advance(100.0)
	check(manager.get_active_customers().is_empty(), "Reentry never silently resumes an old run")
	var cut_slot := func(node: Node):
		if node is Customer and is_instance_valid(slots[0]): slots[0].free()
	node_added.connect(cut_slot)
	check(start(day(1)), "Spawn-callback slot removal run starts")
	manager.advance(0.0)
	node_added.disconnect(cut_slot)
	check(manager.get_active_customers().is_empty() and manager.get_snapshot().history.size() == 1, "Slot freed during actor insertion safely retires that visit")
	var replacement_slot := Marker2D.new()
	replacement_slot.position = Vector2(200, 500)
	stage.add_child(replacement_slot)
	slots[0] = replacement_slot
	check(manager.configure(slots, actors, catalog), "Fresh authored slot can be explicitly configured after removal")


func arrival_boundary() -> void:
	manager.reduced_motion = false
	check(start(day(1, 0.0, 5.0)), "Animated arrival run starts")
	manager.advance(0.0)
	var actor := manager.get_active_customers()[0]
	actor.set_process(false)
	manager.advance(4.0)
	check(manager.get_active_entries()[0].phase == &"arriving" and manager.get_active_entries()[0].patience_remaining == 5.0, "No patience is charged while arrival is in progress")
	actor._process(0.5)
	manager.advance(1.0)
	check(manager.get_active_entries()[0].patience_remaining == 5.0, "Partial arrival still does not charge patience")
	actor._process(1.0)
	manager._process(0.5)
	check(manager.get_active_entries()[0].phase == &"waiting" and manager.get_active_entries()[0].patience_remaining == 5.0, "Same automatic frame as completed arrival excludes pre-arrival delta")
	manager.advance(1.0)
	check(manager.get_active_entries()[0].patience_remaining == 4.0, "Explicit post-arrival advance charges once")
	actor.leave()
	manager.advance(100.0)
	check(manager.get_active_entries().size() == 1 and manager.get_active_entries()[0].phase == &"leaving", "Departing actor retains slot until motion completion")
	actor._process(2.0)
	check(manager.get_active_entries().is_empty() and manager.get_snapshot().completed, "Animated departure completion releases capacity")
	manager.reduced_motion = true


func run() -> void:
	await process_frame
	catalog = root.get_node("Catalog")
	setup()
	compilation()
	lifecycle()
	timeout_and_authority()
	snapshots_and_removal()
	arrival_boundary()
	manager.reset()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Customer queue: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
