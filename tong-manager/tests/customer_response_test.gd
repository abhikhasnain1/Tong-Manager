extends SceneTree
## Designer response policies, immutable attempts, and queue patience/exit rules.

var checks := 0
var failures: Array[String] = []
var catalog: Node
var stage: Node2D
var actors: Node2D
var manager: CustomerQueueManager
var sequence := 0


func _init() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func policy(response: StringName, patience: StringName = &"continue") -> Dictionary:
	return {"unhappy_response": response, "remake_patience": patience}


func order(response: StringName = &"accept", patience: StringName = &"continue") -> OrderState:
	sequence += 1
	var request: Dictionary = catalog.get_order_request(&"tea_cha_no_sugar").snapshot(catalog)
	return OrderState.create(StringName("response_order_%d" % sequence), &"customer_a", request, 0.0, policy(response, patience))


func cup(cold := false) -> Dictionary:
	return {"kind": &"cup", "lifecycle": &"filled", "volume": 250.0, "capacity": 250.0,
		"liquid_id": &"black_tea", "temperature": 20.0 if cold else 70.0, "cold_threshold": 45.0,
		"ingredient_amounts": {}, "brew_history_complete": true,
		"brew_batches": [{"state": &"ready", "infused_counts": {&"black_tea": 1},
			"used_boiling_water": true, "batch_volume": 1500.0}]}


func evaluated(value: OrderState, wrong := true) -> ServiceResult:
	sequence += 1
	var offered := {"kind": &"ready_item", "item_id": &"banana", "unit": &"piece", "quantity": 1} if wrong else cup()
	return ServiceResult.create_evaluated(StringName("response_attempt_%d" % sequence), value, ServiceEvaluation.evaluate(value, offered))


func day(response := 0, patience := 0, count := 1) -> DayConfig:
	var value := DayConfig.new()
	var schedule := CustomerSchedule.new()
	schedule.id = &"response_schedule"
	schedule.mode = CustomerSchedule.Mode.AUTHORED
	schedule.max_active = 1
	for index in count:
		var entry := CustomerArrivalDef.new()
		entry.id = StringName("response_visit_%d" % index)
		entry.customer = catalog.get_customer(&"customer_a")
		entry.request = catalog.get_order_request(&"tea_cha_no_sugar")
		entry.patience_override = 10.0
		entry.unhappy_response_override = response
		entry.remake_patience_override = patience
		schedule.arrivals.append(entry)
	value.customer_schedule = schedule
	return value


func start(value: DayConfig) -> Customer:
	sequence += 1
	manager.reduced_motion = true
	check(manager.start(value, 19, StringName("response_run_%d" % sequence)), "Response schedule starts")
	manager.advance(0.0)
	var current := manager.get_active_customers()
	check(current.size() == 1, "One arrival owns the single slot")
	return current[0] if not current.is_empty() else null


func check_data() -> void:
	var profile: CustomerDef = catalog.get_customer(&"customer_a")
	var old_response := profile.unhappy_response
	var old_patience := profile.remake_patience
	check(profile.get_service_policy() == policy(&"accept"), "Existing profiles retain the previous accept behavior")
	profile.unhappy_response = CustomerDef.UnhappyResponse.REFUSE_RETRY
	profile.remake_patience = CustomerDef.RemakePatience.RESET
	var direct: OrderState = catalog.create_order(&"catalog_response", profile.id, &"tea_cha_no_sugar", 0.0)
	check(direct != null and direct.get_service_policy() == policy(&"refuse_retry", &"reset"), "Catalog orders capture the profile policy")
	var value := day(-1, -1)
	var compiled := value.customer_schedule.compile(value, catalog, 2, &"policy_copy")
	check(compiled.ok and compiled.entries[0].service_policy == policy(&"refuse_retry", &"reset"), "Authored visits inherit both profile choices")
	value.customer_schedule.arrivals[0].unhappy_response_override = CustomerDef.UnhappyResponse.REFUSE_LEAVE
	value.customer_schedule.arrivals[0].remake_patience_override = CustomerDef.RemakePatience.CONTINUE
	var overridden := value.customer_schedule.compile(value, catalog, 2, &"override_copy")
	check(overridden.entries[0].service_policy == policy(&"refuse_leave"), "A day entry independently overrides response and remake patience")
	profile.unhappy_response = CustomerDef.UnhappyResponse.ACCEPT
	profile.remake_patience = CustomerDef.RemakePatience.CONTINUE
	check(direct.get_service_policy() == policy(&"refuse_retry", &"reset") and compiled.entries[0].service_policy == policy(&"refuse_retry", &"reset"), "Later designer edits cannot rewrite compiled visits or existing orders")
	var copied := direct.get_service_policy()
	copied.unhappy_response = &"accept"
	var snapshot := direct.get_snapshot()
	snapshot.service_policy.remake_patience = &"continue"
	check(direct.get_service_policy() == policy(&"refuse_retry", &"reset"), "Policy getters are defensive copies")
	for invalid in [-2, 3, 99]:
		value.customer_schedule.arrivals[0].unhappy_response_override = invalid
		check(not value.customer_schedule.validate(value, catalog).is_empty(), "Invalid authored response fails validation")
	value.customer_schedule.arrivals[0].unhappy_response_override = -1
	for invalid in [-2, 2, 99]:
		value.customer_schedule.arrivals[0].remake_patience_override = invalid
		check(not value.customer_schedule.validate(value, catalog).is_empty(), "Invalid authored timer choice fails validation")
	var request := direct.get_request()
	for invalid: Dictionary in [{"unhappy_response": &"invented", "remake_patience": &"continue"},
		{"unhappy_response": 1, "remake_patience": &"continue"}, {"unhappy_response": &"accept"},
		{"unhappy_response": &"accept", "remake_patience": &"reset", "random": true}]:
		check(OrderState.create(&"bad_policy", profile.id, request, 0.0, invalid) == null, "Malformed direct policy cannot enter an order")
	var default_order := OrderState.create(&"legacy_default", profile.id, request, 0.0)
	check(default_order.get_service_policy() == policy(&"accept"), "The existing four-argument constructor remains compatible")
	profile.unhappy_response = old_response
	profile.remake_patience = old_patience
	var generated := day()
	generated.customer_count_min = 1
	generated.customer_count_max = 1
	generated.customer_schedule.mode = CustomerSchedule.Mode.GENERATED
	generated.customer_schedule.customer_pool.assign([profile])
	check(generated.customer_schedule.compile(generated, catalog, 4, &"generated_policy").entries[0].service_policy == profile.get_service_policy(), "Generated visits use the same profile policy")


func check_results() -> void:
	for response: StringName in [&"accept", &"refuse_leave", &"refuse_retry"]:
		var value := order(response)
		var wrong := evaluated(value)
		var data := wrong.get_snapshot()
		check(data.response == response and data.accepted == (response == &"accept") and data.fulfilled == data.accepted, "Bad service derives the configured response")
		check(data.bad_review and data.unhappy and data.reasons == [&"wrong_item_kind"] and data.served_kind == &"ready_item", "Every valid attempt retains factual dissatisfaction and delivered identity")
		check(not value.closed and not value.fulfilled and value.get_results().is_empty(), "Evaluation alone cannot mutate the order")
		check(value.record_result(wrong), "One valid response records")
		check(value.closed == (response != &"refuse_retry") and value.fulfilled == (response == &"accept"), "Terminal refusal and accepted fulfillment remain distinct")
		check(not value.record_result(wrong) and value.get_results().size() == 1, "Exact attempt replay never adds history")
		data.response = &"accept"
		data.reasons.clear()
		check(value.get_results()[0].response == response and value.get_results()[0].reasons == [&"wrong_item_kind"], "Outcome facts remain immutable")
		if response == &"refuse_retry":
			var accepted := evaluated(value, false)
			check(accepted != null and accepted.get_snapshot().response == &"accept" and value.record_result(accepted), "A correct remake accepts the same pending order")
			check(value.closed and value.fulfilled and value.get_results().size() == 2, "Retry history precedes one terminal acceptance")
		else:
			check(not ServiceEvaluation.evaluate(value, cup()).can_handoff and evaluated(value) == null, "Closed orders reject later attempts before policy resolution")
		var correct_order := order(response)
		var correct := evaluated(correct_order, false)
		check(correct.get_snapshot().accepted and not correct.get_snapshot().bad_review, "Correct service always accepts regardless of unhappy policy")
		var cold_order := order(response)
		var cold := ServiceResult.create_evaluated(StringName("cold_" + String(response)), cold_order, ServiceEvaluation.evaluate(cold_order, cup(true)))
		check(cold.get_snapshot().response == response and cold.get_snapshot().cold_at_handoff and cold.get_snapshot().reasons == [&"cold_tea"], "Cold uses the same response policy with real temperature evidence")
	var legacy := order(&"refuse_leave")
	var rejected := ServiceResult.create(&"legacy_rejection", legacy.order_id, legacy.customer_id, legacy.request_kind, false, false, &"wrong_item")
	check(rejected.get_snapshot().response == &"refuse_retry" and not rejected.get_snapshot().bad_review, "Legacy structural-rejection fixture remains a no-review retry")
	check(legacy.record_result(rejected) and not legacy.closed, "Legacy rejection does not close the order")


func actor_for(value: OrderState) -> Customer:
	var actor := load("res://scenes/gameplay/customers/Customer.tscn").instantiate() as Customer
	actor.customer_def = catalog.get_customer(value.customer_id)
	actor.reduced_motion = true
	stage.add_child(actor)
	check(actor.set_order(value), "Actor binds its original order")
	actor.arrive()
	return actor


func check_actor() -> void:
	for response: StringName in [&"refuse_leave", &"refuse_retry"]:
		var value := order(response)
		var actor := actor_for(value)
		var result := evaluated(value)
		check(value.record_result(result), "Service may record before its optional presentation")
		check(actor.is_serve_enabled() == (response == &"refuse_retry"), "Terminal refusal is immediately nonserveable before presentation")
		check(actor.apply_service_result(result) and not actor.apply_service_result(result), "Refusal presents exactly once")
		check(actor.get_presentation_snapshot().review_count == 1 and actor.get_presentation_snapshot().emotion in [&"wrong", &"unhappy"], "Refusal has one factual unhappy reaction")
		check(actor.state == (Customer.State.REFUSED if response == &"refuse_leave" else Customer.State.ORDERING), "Refusal presentation distinguishes leaving from waiting")
		actor.reset_presentation()
		check(not actor.apply_service_result(result) and actor.order == value and actor.is_serve_enabled() == (response == &"refuse_retry"), "Presentation reset preserves response identity and eligibility")
		if response == &"refuse_retry":
			var accepted := evaluated(value, false)
			check(actor.apply_service_result(accepted) and value.fulfilled and actor.get_presentation_snapshot().review_count == 1, "Correct remake accepts without duplicating the earlier bad-review fact")
		else:
			check(not actor.prepare_timeout_departure(), "Terminal refusal cannot be relabelled a patience timeout")
			for near_end in [0.999, 0.999999, 0.99999999, 0.9999999999999999, 1.0]:
				actor._blend_turn(near_end)
				check(actor.get_presentation_snapshot().turn_frame <= 3, "Near-final turn rounding stays inside the final atlas pose")
		actor.free()


func check_queue() -> void:
	for patience in [CustomerDef.RemakePatience.CONTINUE, CustomerDef.RemakePatience.RESET]:
		var actor := start(day(CustomerDef.UnhappyResponse.REFUSE_RETRY, patience))
		manager.advance(3.0)
		check(is_equal_approx(manager.get_active_entries()[0].patience_remaining, 7.0), "Patience counts down after actual arrival")
		var value := actor.order
		var refused := evaluated(value)
		check(value.record_result(refused), "Queue receives an authoritative retry before presentation")
		manager.advance(0.0)
		var expected := 7.0 if patience == CustomerDef.RemakePatience.CONTINUE else 10.0
		check(is_equal_approx(manager.get_active_entries()[0].patience_remaining, expected), "Queue applies the saved retry timer choice without presentation")
		check(manager.get_active_entries()[0].phase == &"waiting" and not value.closed and actor.is_serve_enabled(), "Retry retains the same pending slot/order")
		check(actor.apply_service_result(refused), "Delayed retry feedback can still present")
		manager.advance(2.0)
		check(is_equal_approx(manager.get_active_entries()[0].patience_remaining, expected - 2.0), "Repeated queue processing does not reset a handled retry")
		check(not actor.apply_service_result(refused) and not value.record_result(refused), "Neither presentation nor authority can replay the refusal")
		manager.advance(0.0)
		check(is_equal_approx(manager.get_active_entries()[0].patience_remaining, expected - 2.0), "Replay cannot extend the wait")
		var second := evaluated(value)
		check(value.record_result(second), "A different attempt can be refused again")
		manager.advance(0.0)
		check(is_equal_approx(manager.get_active_entries()[0].patience_remaining, expected - 2.0 if patience == 0 else 10.0), "A genuine second retry follows the same designer choice")
		var accepted := evaluated(value, false)
		check(value.record_result(accepted), "Correct remake records one acceptance")
		manager.advance(0.0)
		check(manager.get_active_entries()[0].phase == &"served_reaction" and value.fulfilled, "Acceptance stops waiting and enters the normal served reaction")
		var remaining: float = manager.get_active_entries()[0].patience_remaining
		manager.advance(0.1)
		check(manager.get_active_entries()[0].patience_remaining == remaining, "Accepted order no longer loses patience")
		manager.stop()
	var actor := start(day(CustomerDef.UnhappyResponse.REFUSE_LEAVE, CustomerDef.RemakePatience.CONTINUE, 2))
	manager.advance(4.0)
	var value := actor.order
	var refused := evaluated(value)
	check(value.record_result(refused) and actor.apply_service_result(refused), "Terminal refusal records and presents")
	actor.reduced_motion = false
	actor.set_process(false)
	manager.advance(0.0)
	var snapshot := manager.get_active_entries()[0]
	check(snapshot.phase == &"refused_reaction" and snapshot.closed and not snapshot.fulfilled and snapshot.reason == &"refused", "Refusal has a separate terminal reaction without fulfillment")
	check(is_equal_approx(snapshot.reaction_remaining, 0.25) and snapshot.patience_remaining == 6.0, "Short refusal cue uses its own tuning and retires patience")
	manager.advance(0.24)
	check(manager.get_snapshot().spawned == 1 and not actor.get_presentation_snapshot().moving, "Reaction retains the occupied slot")
	manager.advance(0.02)
	check(actor.state == Customer.State.LEAVING and actor.get_presentation_snapshot().moving and manager.get_snapshot().spawned == 1, "Normal departure starts without freeing the occupied slot")
	actor._process(3.0)
	check(manager.get_active_customers().is_empty() and manager.get_snapshot().history[0].reason == &"refused", "Completed departure records refusal distinctly from timeout or fulfillment")
	manager.advance(0.0)
	check(manager.get_snapshot().spawned == 2, "A later customer can arrive only after the refusal departure finishes")
	manager.stop()
	actor = start(day(CustomerDef.UnhappyResponse.REFUSE_RETRY))
	value = actor.order
	check(value.record_result(evaluated(value)), "A refusal can precede the normal patience timeout")
	manager.advance(11.0)
	check(manager.get_active_entries()[0].phase == &"timeout_reaction" and not value.closed and not value.fulfilled, "Unremade retry expires as timeout without inventing acceptance")
	manager.advance(1.0)
	check(manager.get_snapshot().history[0].reason == &"timeout" and value.get_results().size() == 1, "Timeout adds no extra service attempt or review")
	manager.stop()
	var frozen := day(CustomerDef.UnhappyResponse.REFUSE_RETRY, CustomerDef.RemakePatience.RESET)
	actor = start(frozen)
	frozen.customer_schedule.arrivals[0].unhappy_response_override = CustomerDef.UnhappyResponse.REFUSE_LEAVE
	frozen.customer_schedule.arrivals[0].remake_patience_override = CustomerDef.RemakePatience.CONTINUE
	check(actor.order.get_service_policy() == policy(&"refuse_retry", &"reset"), "Live visit policy is independent of later day edits")
	manager.stop()


func run() -> void:
	catalog = root.get_node("Catalog")
	stage = Node2D.new()
	root.add_child(stage)
	actors = Node2D.new()
	stage.add_child(actors)
	var slot := Marker2D.new()
	stage.add_child(slot)
	manager = CustomerQueueManager.new()
	stage.add_child(manager)
	manager.set_process(false)
	check(manager.configure([slot], actors, catalog), "Response fixture configures the normal queue")
	check_data()
	check_results()
	check_actor()
	check_queue()
	stage.queue_free()
	await process_frame
	print("CUSTOMER_RESPONSE: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
