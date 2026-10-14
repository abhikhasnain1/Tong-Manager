extends SceneTree
## Pure matching/review evidence, independent of live drag ownership and payment.

var catalog: Node
var checks := 0
var failures: Array[String] = []
var next_id := 0


func _init() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func order(request_id: StringName = &"tea_cha_no_sugar") -> OrderState:
	next_id += 1
	return catalog.create_order(StringName("evaluation_%d" % next_id), &"customer_a", request_id, 0.0)


func batch(stage: StringName = &"ready", count := 1, boiled := true) -> Dictionary:
	return {"state": stage, "infused_counts": {&"black_tea": count}, "used_boiling_water": boiled, "batch_volume": 1500.0}


func cup(additions: Dictionary = {}) -> Dictionary:
	return {
		"kind": &"cup", "lifecycle": &"filled", "volume": 250.0, "capacity": 250.0,
		"liquid_id": &"black_tea", "temperature": 70.0, "cold_threshold": 45.0,
		"ingredient_amounts": additions.duplicate(true), "brew_batches": [batch()],
		"brew_history_complete": true,
	}


func snack(item: StringName = &"banana") -> Dictionary:
	return {"kind": &"ready_item", "item_id": item, "quantity": 1, "unit": &"piece"}


func accepted(evaluation: Dictionary, expected: Array, label: String) -> void:
	check(evaluation.can_handoff and evaluation.failure_reason == &"", label + ": physical handoff accepted")
	check(evaluation.reasons == expected, label + ": exact ordered reasons")
	check(evaluation.bad_review == not expected.is_empty(), label + ": one review decision")


func check_recipes() -> void:
	for id: StringName in [&"tea_cha_no_sugar", &"tea_cha", &"tea_dudh_cha_no_sugar", &"tea_dudh_cha"]:
		var pending := order(id)
		var desired: Dictionary = pending.get_request().cup_portion_counts
		var offered := cup(desired)
		accepted(ServiceEvaluation.evaluate(pending, offered), [], String(id))
		check(not pending.fulfilled and pending.get_results().is_empty(), "Evaluation does not record or complete an order")
		offered.temperature = 45.0
		accepted(ServiceEvaluation.evaluate(pending, offered), [&"cold_tea"], "Cold " + String(id))
		offered.temperature = 45.001
		accepted(ServiceEvaluation.evaluate(pending, offered), [], "Above configurable cold threshold")
		offered.volume = 225.0
		accepted(ServiceEvaluation.evaluate(pending, offered), [], "Exact saved serving minimum")
		offered.volume = 224.9
		accepted(ServiceEvaluation.evaluate(pending, offered), [&"insufficient_volume"], "Underfilled drink still served")
		var extra: Dictionary = desired.duplicate()
		extra[&"sugar"] = float(extra.get(&"sugar", 0.0)) + 1.0
		accepted(ServiceEvaluation.evaluate(pending, cup(extra)), [&"wrong_ingredients"], "Extra spoon accepted and reviewed")
	var sugar := order(&"tea_cha")
	accepted(ServiceEvaluation.evaluate(sugar, cup({&"sugar": 0.5})), [&"wrong_ingredients"], "Inherited half spoon is not a full spoon")
	accepted(ServiceEvaluation.evaluate(sugar, cup({&"sugar": 0.5 + 0.5})), [], "Direct and inherited amounts use one combined read model")
	accepted(ServiceEvaluation.evaluate(sugar, cup({&"sugar": 1.0 + 0.0000001})), [], "Small absolute arithmetic tolerance")
	accepted(ServiceEvaluation.evaluate(sugar, cup({&"sugar": 1.0001})), [&"wrong_ingredients"], "Amount mismatch outside tolerance")
	accepted(ServiceEvaluation.evaluate(order(), cup({&"sugar": 0.00000001})), [&"wrong_ingredients"], "Unexpected tiny positive ingredient never disappears")
	var zero_entries := ServiceEvaluation.evaluate(order(), cup({&"sugar": 0.0, &"condensed_milk": 0}))
	accepted(zero_entries, [], "Zero carried entries do not make a real drink unservable")
	check(zero_entries.served.ingredient_amounts.is_empty(), "Exact zero entries normalize away")
	var no_liquid := cup({&"sugar": 0.0})
	no_liquid.volume = 0.0
	check(ServiceEvaluation.evaluate(order(), no_liquid).failure_reason == &"empty_cup", "Zero ingredient entries cannot make an empty vessel nonempty")
	var saved := sugar.get_request()
	saved.kettle_portion_counts[&"black_tea"] = 5
	saved.cup_portion_counts[&"sugar"] = 10000000
	var custom := OrderState.create(&"custom_batch", &"customer_a", saved, 0.0)
	var large := cup({&"sugar": 10000000.0})
	large.brew_batches = [batch(&"ready", 5)]
	accepted(ServiceEvaluation.evaluate(custom, large), [], "Designer five-bag recipe uses captured batch counts")
	large.ingredient_amounts[&"sugar"] += 1.0
	accepted(ServiceEvaluation.evaluate(custom, large), [&"wrong_ingredients"], "Absolute tolerance cannot hide extra spoon at large counts")


func check_brew_history() -> void:
	var pending := order()
	for entry: Array in [
		[batch(&"underbrewed"), [&"underbrewed"]],
		[batch(&"oversteeped"), [&"oversteeped"]],
		[batch(&"ready", 5), [&"wrong_brew_ingredients"]],
		[batch(&"ready", 1, false), [&"not_boiled"]],
	]:
		var offered := cup()
		offered.brew_batches = [entry[0]]
		accepted(ServiceEvaluation.evaluate(pending, offered), entry[1], "Captured brew quality")
	var blended := cup()
	blended.brew_batches = [batch(), batch(&"underbrewed", 2, false), batch(&"oversteeped")]
	blended.temperature = 20.0
	accepted(ServiceEvaluation.evaluate(pending, blended), [&"underbrewed", &"oversteeped", &"wrong_brew_ingredients", &"not_boiled", &"cold_tea"], "All positive contributions reviewed once per reason")
	blended.brew_batches.append(batch(&"underbrewed", 2, false))
	check(ServiceEvaluation.evaluate(pending, blended).reasons.size() == 5, "Repeated batch evidence does not multiply review reasons")
	var unknown := cup()
	unknown.brew_batches = []
	accepted(ServiceEvaluation.evaluate(pending, unknown), [&"unknown_brew"], "Legacy unknown nonwater liquid remains serveable")
	unknown.brew_batches = [batch()]
	unknown.brew_history_complete = false
	accepted(ServiceEvaluation.evaluate(pending, unknown), [&"unknown_brew"], "Unknown top-up cannot be hidden by a known contribution")
	var oversized := cup()
	oversized.brew_batches[0].batch_volume = 1501.0
	accepted(ServiceEvaluation.evaluate(pending, oversized), [&"oversized_batch"], "Original batch volume compares to saved recipe maximum")
	oversized.brew_batches[0].erase("batch_volume")
	accepted(ServiceEvaluation.evaluate(pending, oversized), [&"unknown_brew"], "Missing original batch volume is unknown provenance")
	for malformed: Variant in [null, {}, {"state": &"invented"}, batch(&"ready", 0), {"state": &"ready", "infused_counts": {&"black_tea": 1.0}, "used_boiling_water": true}]:
		unknown = cup()
		unknown.brew_batches = [batch(), malformed]
		accepted(ServiceEvaluation.evaluate(pending, unknown), [&"unknown_brew"], "Malformed provenance is unknown quality, not rejection")
	var water := cup()
	water.liquid_id = &"water"
	water.brew_batches = []
	water.temperature = 20.0
	accepted(ServiceEvaluation.evaluate(pending, water), [&"wrong_liquid"], "Known water is neither unknown brew nor cold tea")
	water.brew_batches = [{"state": &"water", "infused_counts": {}, "used_boiling_water": false, "batch_volume": 1500.0}]
	accepted(ServiceEvaluation.evaluate(pending, water), [&"wrong_liquid", &"wrong_brew_ingredients", &"not_boiled"], "Water contribution retains known batch evidence")
	var copied := ServiceEvaluation.evaluate(pending, blended)
	blended.brew_batches[0].infused_counts[&"black_tea"] = 99
	check(copied.served.brew_batches[0].infused_counts[&"black_tea"] == 1, "Offered batch containers are copied")
	copied.served.ingredient_amounts[&"sugar"] = 99
	check(blended.ingredient_amounts.is_empty(), "Editing evaluation cannot change original cup contents")


func mixed_recipe(with_cup_sugar := false) -> OrderState:
	var recipe_id: StringName = &"cha" if with_cup_sugar else &"cha_no_sugar"
	var original: Resource = catalog.recipes[recipe_id]
	var configured := original.duplicate(true)
	configured.kettle_portion_counts[&"sugar"] = 1
	configured.kettle_portion_units[&"sugar"] = &"spoonful"
	configured.base_item_ids.append(&"sugar")
	catalog.recipes[recipe_id] = configured
	var pending := order(StringName("tea_" + String(recipe_id)))
	catalog.recipes[recipe_id] = original
	check(pending != null, "Catalog accepts authored recipe with kettle sugar and optional separate cup sugar")
	return pending


func mixed_cup(original_dose: float, direct_sugar := 0.0) -> Dictionary:
	var inherited := original_dose * 250.0 / 1500.0
	var offered := cup({&"sugar": inherited + direct_sugar})
	offered.inherited_ingredient_amounts = {&"sugar": inherited}
	offered.brew_batches[0].mixed_counts = {&"sugar": original_dose}
	return offered


func check_kettle_mixed_recipes() -> void:
	var kettle_only := mixed_recipe()
	if kettle_only == null: return
	var offered := mixed_cup(1.0)
	accepted(ServiceEvaluation.evaluate(kettle_only, offered), [], "Requested kettle sugar is assessed as one batch dose, not an extra fractional cup spoon")
	var partial := offered.duplicate(true)
	partial.brew_batches[0].mixed_counts[&"sugar"] = (2.0 / 3.0) * 1500.0 / 1000.0
	accepted(ServiceEvaluation.evaluate(kettle_only, partial), [], "Equivalent original dose remains correct after earlier partial pours")
	accepted(ServiceEvaluation.evaluate(kettle_only, mixed_cup(2.0)), [&"wrong_brew_ingredients"], "Extra kettle sugar remains a batch mismatch")
	accepted(ServiceEvaluation.evaluate(kettle_only, mixed_cup(0.5)), [&"wrong_brew_ingredients"], "Insufficient kettle sugar remains a batch mismatch")
	accepted(ServiceEvaluation.evaluate(kettle_only, cup()), [&"wrong_brew_ingredients"], "Missing requested kettle sugar")
	accepted(ServiceEvaluation.evaluate(kettle_only, mixed_cup(1.0, 1.0)), [&"wrong_ingredients"], "Unrequested direct cup spoon is not hidden by a valid batch dose")
	var both := mixed_recipe(true)
	if both == null: return
	accepted(ServiceEvaluation.evaluate(both, mixed_cup(1.0, 1.0)), [], "One kettle sugar plus one direct cup sugar are assessed independently")
	accepted(ServiceEvaluation.evaluate(both, mixed_cup(1.0)), [&"wrong_ingredients"], "Batch sugar cannot replace separately requested cup sugar")
	accepted(ServiceEvaluation.evaluate(both, mixed_cup(1.0, 2.0)), [&"wrong_ingredients"], "Extra direct sugar remains counted when recipe also has kettle sugar")
	var unwanted := mixed_cup(1.0)
	unwanted.ingredient_amounts[&"condensed_milk"] = 0.25
	unwanted.inherited_ingredient_amounts[&"condensed_milk"] = 0.25
	unwanted.brew_batches[0].mixed_counts[&"condensed_milk"] = 1.5
	accepted(ServiceEvaluation.evaluate(kettle_only, unwanted), [&"wrong_ingredients", &"wrong_brew_ingredients"], "Unexpected kettle ingredient remains visible in both actual cup and batch evidence")
	accepted(ServiceEvaluation.evaluate(order(&"tea_cha"), mixed_cup(1.0)), [&"wrong_ingredients", &"wrong_brew_ingredients"], "Default recipe retains its cup spoon amount and separate kettle recipe")
	var legacy := cup({&"sugar": 1.0})
	legacy.inherited_ingredient_amounts = {&"sugar": 1.0}
	accepted(ServiceEvaluation.evaluate(order(&"tea_cha"), legacy), [], "Combined amounts remain the default read model when item is not requested in kettle")
	var result := ServiceResult.create_evaluated(&"mixed_record", both, ServiceEvaluation.evaluate(both, mixed_cup(1.0, 1.0)))
	check(result != null and not result.get_snapshot().bad_review, "Result factory reassesses the same kettle/cup distinction")
	var snapshot := result.get_snapshot()
	check(snapshot.served.ingredient_amounts[&"sugar"] > 1.0 and snapshot.served.inherited_ingredient_amounts[&"sugar"] > 0.0,
		"Recorded delivery preserves full actual combined and inherited quantities")
	snapshot.served.brew_batches[0].mixed_counts[&"sugar"] = 99.0
	check(result.get_snapshot().served.brew_batches[0].mixed_counts[&"sugar"] == 1.0, "Recorded mixed concentration is defensively copied")
	var malformed := mixed_cup(1.0)
	malformed.inherited_ingredient_amounts[&"sugar"] = 2.0
	check(not ServiceEvaluation.evaluate(kettle_only, malformed).can_handoff, "Inherited quantity cannot exceed total actual amount")
	malformed = mixed_cup(1.0)
	malformed.brew_batches[0].mixed_counts[&"sugar"] = NAN
	accepted(ServiceEvaluation.evaluate(kettle_only, malformed), [&"unknown_brew"], "Malformed mixed provenance is unknown quality without hard rejection")
	check(catalog.validate_customer_orders().is_empty(), "Authored recipe fixtures restore shipped Catalog resources")


func check_live_mixed_transfer() -> void:
	var pending := mixed_recipe(true)
	if pending == null: return
	var kettle := preload("res://scenes/gameplay/tools/Kettle.tscn").instantiate() as Kettle
	root.add_child(kettle)
	kettle.set_process(false)
	check(kettle.add_water(1500.0) == 1500.0, "Real configured batch receives water")
	kettle.temperature = kettle.config.boiling_temperature
	check(kettle.apply_ingredient(&"black_tea", 1, &"infuse", &"black_tea"), "Real batch receives its infusing ingredient")
	check(kettle.apply_ingredient(&"sugar", 1, &"mix"), "Real batch receives configured mixed sugar")
	kettle.advance_brewing(kettle.config.steep_seconds)
	var first_evidence: Dictionary = {}
	for index in range(2):
		var receiver := preload("res://scenes/gameplay/tools/Cup.tscn").instantiate() as Cup
		root.add_child(receiver)
		receiver.set_process(false)
		check(receiver.apply_ingredient(&"sugar", 1, &"mix"), "Real cup receives its separate direct spoon")
		check(kettle.start_pour(receiver), "Real configured batch begins a partial pour")
		kettle.update_pour(250.0 / kettle.config.pour_rate_ml)
		kettle.stop_pour()
		var evidence := receiver.get_service_snapshot()
		check(is_equal_approx(evidence.inherited_ingredient_amounts[&"sugar"], 1.0 / 6.0), "Live cup inherits the actual fractional batch share")
		accepted(ServiceEvaluation.evaluate(pending, evidence), [], "Real partial pour matches authored kettle and cup sugar doses")
		if index == 0: first_evidence = evidence
		receiver.free()
	check(is_equal_approx(kettle.volume_ml, 1000.0), "Two real partial pours preserve remaining batch volume")
	check(first_evidence.brew_batches[0].mixed_counts[&"sugar"] == 1.0, "Earlier evidence retains original mixed dose after later pour")
	kettle.free()


func check_crossed_orders() -> void:
	accepted(ServiceEvaluation.evaluate(order(&"ready_banana"), snack()), [], "Requested banana")
	accepted(ServiceEvaluation.evaluate(order(&"ready_biscuits"), snack(&"biscuits")), [], "Requested biscuit")
	accepted(ServiceEvaluation.evaluate(order(&"ready_banana"), snack(&"biscuits")), [&"wrong_item"], "Different ready piece")
	accepted(ServiceEvaluation.evaluate(order(), snack()), [&"wrong_item_kind"], "Snack instead of tea")
	accepted(ServiceEvaluation.evaluate(order(&"ready_banana"), cup()), [&"wrong_item_kind"], "Drink instead of snack")
	var cold := cup()
	cold.temperature = 20.0
	accepted(ServiceEvaluation.evaluate(order(&"ready_banana"), cold), [&"wrong_item_kind", &"cold_tea"], "Cold drink quality remains distinct from requested snack")
	var dry := cup({&"sugar": 1.0})
	dry.volume = 0.0
	dry.liquid_id = &""
	dry.brew_batches = []
	accepted(ServiceEvaluation.evaluate(order(&"tea_cha"), dry), [&"wrong_liquid", &"insufficient_volume"], "Ingredient-only contents remain nonempty")


func check_invalid_offers() -> void:
	var pending := order()
	for mutation: Dictionary in [
		{"kind": &"kettle"}, {"lifecycle": &"served"}, {"lifecycle": &"dirty"}, {"lifecycle": &"unknown"},
		{"volume": NAN}, {"volume": INF}, {"volume": -1.0}, {"volume": 251.0}, {"capacity": 0.0},
		{"temperature": NAN}, {"cold_threshold": INF}, {"liquid_id": &""}, {"liquid_id": null},
		{"ingredient_amounts": {&"sugar": -1.0}}, {"ingredient_amounts": {&"sugar": NAN}},
		{"ingredient_amounts": null},
	]:
		var offered := cup()
		offered.merge(mutation, true)
		var result := ServiceEvaluation.evaluate(pending, offered)
		check(not result.can_handoff and not result.bad_review and result.reasons.is_empty(), "Physical malformed/unavailable cup has no review: " + str(mutation))
	for offered: Dictionary in [{}, {"kind": &"ready_item"}, {"kind": &"ready_item", "item_id": &"banana", "unit": &"piece", "quantity": 0},
		{"kind": &"ready_item", "item_id": &"banana", "unit": &"spoonful", "quantity": 1}]:
		check(not ServiceEvaluation.evaluate(pending, offered).can_handoff, "Malformed ready payload rejected")
	var empty := cup()
	empty.volume = 0.0
	check(ServiceEvaluation.evaluate(pending, empty).failure_reason == &"empty_cup", "A stale base ID alone cannot make a cup nonempty")
	check(not ServiceEvaluation.evaluate(null, cup()).can_handoff, "Missing order")
	check(not ServiceEvaluation.evaluate(OrderState.new(), cup()).can_handoff, "Uninitialized order")


func check_results() -> void:
	var pending := order()
	var offered := cup({&"sugar": 2.0})
	offered.temperature = 20.0
	offered.brew_batches = [batch(&"oversteeped", 5, false)]
	var assessment := ServiceEvaluation.evaluate(pending, offered)
	var recorded := ServiceResult.create_evaluated(&"handoff_one", pending, assessment)
	check(recorded != null, "Evaluated mismatches create an accepted result")
	var data := recorded.get_snapshot()
	check(data.accepted and data.fulfilled and data.bad_review and data.unhappy, "Multiple problems still produce one accepted unhappy review outcome")
	check(data.reasons.size() == 5 and data.request_kind == &"tea" and data.served_kind == &"cup", "Structured reasons retain requested and served kinds")
	check(pending.record_result(recorded) and pending.fulfilled, "Accepted imperfect drink completes once")
	check(not pending.record_result(recorded) and pending.get_results().size() == 1, "Repeated result cannot duplicate outcome")
	check(not ServiceEvaluation.evaluate(pending, offered).can_handoff, "Completed order cannot accept another item")
	check(ServiceResult.create_evaluated(&"stale", pending, assessment) == null, "Previously valid assessment cannot reopen completed order")
	data.served.brew_batches[0].infused_counts[&"black_tea"] = 99
	data.reasons.clear()
	check(recorded.get_snapshot().reasons.size() == 5 and recorded.get_snapshot().served.brew_batches[0].infused_counts[&"black_tea"] == 5, "Result getters detach nested evidence")
	check(pending.get_accepted_result().reasons.size() == 5, "Order retains its own accepted evidence")
	for pair: Array in [[&"tea_cha", snack()], [&"ready_banana", cup()]]:
		var crossed := order(pair[0])
		var result := ServiceResult.create_evaluated(&"crossed", crossed, ServiceEvaluation.evaluate(crossed, pair[1]))
		check(result != null and crossed.record_result(result), "Crossed-kind delivery records against requested-kind identity")
		check(crossed.get_accepted_result().bad_review, "Crossed-kind order fulfilled with bad review")
	var fresh := order()
	var tampered := ServiceEvaluation.evaluate(fresh, offered)
	tampered.reasons = []
	tampered.bad_review = false
	tampered.cold_at_handoff = false
	var checked := ServiceResult.create_evaluated(&"tampered", fresh, tampered)
	check(checked != null and checked.get_snapshot().bad_review and checked.get_snapshot().reasons.size() == 5, "Factory derives evidence instead of trusting altered flags")
	check(ServiceResult.create_evaluated(&"wrong_order", order(), tampered) == null, "Assessment cannot transfer between order identities")
	check(ServiceResult.create_evaluated(&"", fresh, tampered) == null, "Handoff requires stable identity")
	var rejected := ServiceResult.create(&"legacy_reject", fresh.order_id, fresh.customer_id, fresh.request_kind, false, false, &"unavailable")
	check(rejected != null and fresh.record_result(rejected) and not fresh.fulfilled, "Legacy structural rejection leaves order open")
	check(not rejected.get_snapshot().bad_review and rejected.get_snapshot().reasons.is_empty(), "Rejected handoff has no bad review")
	var legacy := ServiceResult.create(&"legacy_cold", fresh.order_id, fresh.customer_id, &"tea", true, true)
	check(legacy.get_snapshot().reason == &"cold_tea" and legacy.get_snapshot().bad_review, "Legacy cold factory remains compatible")


func run() -> void:
	catalog = root.get_node("Catalog")
	var state := root.get_node("GameState")
	check(state.ensure_inventory(), "Fixture initializes stock")
	state.ensure_water_day()
	var stock: Dictionary = state.inventory.quantities
	var water: float = state.water_supply.remaining_ml
	check_recipes()
	check_brew_history()
	check_kettle_mixed_recipes()
	check_live_mixed_transfer()
	check_crossed_orders()
	check_invalid_offers()
	check_results()
	check(state.inventory.quantities == stock and state.water_supply.remaining_ml == water, "Pure evaluation/result operations never mutate supplies")
	print("SERVICE_EVALUATION: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
