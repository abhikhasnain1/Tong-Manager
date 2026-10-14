extends SceneTree
## Pure request/profile/order data. Actual vessel matching and payment are separate.

const CUP := preload("res://scenes/gameplay/tools/Cup.tscn")
const TEAS: Array[StringName] = [&"cha_no_sugar", &"cha", &"dudh_cha_no_sugar", &"dudh_cha"]
const READY: Array[StringName] = [&"banana", &"biscuits"]
var catalog: Node
var state: Node
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func request(id: StringName) -> OrderRequestDef:
	return catalog.get_order_request(id) as OrderRequestDef


func make_order(identity: StringName, request_id: StringName = &"tea_cha") -> OrderState:
	return catalog.create_order(identity, &"customer_a", request_id, 12.5) as OrderState


func make_result(order: OrderState, identity: StringName, accepted: bool, cold := false, reason: StringName = &"") -> ServiceResult:
	return ServiceResult.create(identity, order.order_id, order.customer_id, order.request_kind, accepted, cold, reason)


func check_catalog_data() -> void:
	check(catalog.customers.size() == 2, "Catalog loads the two starter profiles")
	check(catalog.order_requests.size() == 6, "Catalog loads four tea and two ready-item definitions")
	check(catalog.items.size() == 9 and catalog.recipes.size() == 6, "Customer data adds no inventory items or recipes")
	check(catalog.validate_customer_orders().is_empty(), "All shipped customer/request data validates")
	var available: Array[CustomerDef] = catalog.get_available_customers()
	check(available.size() == 2, "Unrelated unsupported ginger/lemon recipes do not disable valid profiles")
	for profile: CustomerDef in available:
		check(profile.validate(catalog).is_empty() and profile.patience_seconds > 0.0, "Each profile has a valid nonempty pool and positive patience")
		check(profile.order_requests.size() == 6, "Each starter profile exposes all six editable options")
		var recipe_ids: Array[StringName] = profile.order_recipe_ids
		check(recipe_ids.size() == 4, "The legacy recipe list derives only the four tea requests")
		recipe_ids.clear()
		check(profile.order_recipe_ids.size() == 4, "Changing a derived recipe-ID list cannot rewrite its profile pool")
		for option: OrderRequestDef in profile.order_requests:
			check(option == request(option.id), "Profile pools reference the shared Catalog request resource")
	available.clear()
	check(catalog.get_available_customers().size() == 2, "Changing an available-profile array leaves Catalog intact")
	for recipe_id: StringName in TEAS:
		var option := request(StringName("tea_" + String(recipe_id)))
		var recipe: Resource = catalog.recipes[recipe_id]
		check(option != null and option.validate(catalog).is_empty(), "Supported tea request resolves: " + String(recipe_id))
		var data: Dictionary = option.snapshot(catalog)
		check(data.kind == &"tea" and data.recipe_id == recipe_id and String(data.item_id).is_empty(), "Tea request has exactly one recipe identity")
		check(data.quantity == 1 and data.unit == &"cup" and data.price == recipe.price, "Tea request copies one serving and its existing price")
		check(data.brewed_liquid_id == &"black_tea" and data.output_item_id == recipe_id, "Finished recipe identity remains distinct from stock/liquid identity")
		check(data.minimum_serving_volume_ml == 225.0 and data.target_serving_volume_ml == 250.0 and data.max_batch_volume_ml == 1500.0,
			"Tea request retains the accepted minimum, target and batch amounts")
		check(data.kettle_portion_counts == recipe.kettle_portion_counts and data.cup_portion_counts == recipe.cup_portion_counts,
			"Desired batch/cup amounts come from the recipe")
		check(data.kettle_portion_units == recipe.kettle_portion_units and data.cup_portion_units == recipe.cup_portion_units,
			"Desired portion units remain stock units, separate from the requested cup")
		check(data.icon == (catalog.items[&"black_tea"] as ItemDef).icon, "Tea presentation shares its Catalog icon")
	for item_id: StringName in READY:
		var option := request(StringName("ready_" + String(item_id)))
		var item: ItemDef = catalog.items[item_id]
		var data: Dictionary = option.snapshot(catalog)
		check(option.validate(catalog).is_empty() and data.kind == &"ready_item", "Existing hanging item has a valid ready request")
		check(data.item_id == item.id and String(data.recipe_id).is_empty() and data.quantity == 1 and data.unit == &"piece",
			"Ready request preserves the existing one-piece portion identity")
		check(data.price == item.sell_price and data.icon == item.icon, "Ready request uses the existing sell price and shared pantry artwork")
		check(not data.has("minimum_serving_volume_ml") and not data.has("unlocked"), "Ready pieces acquire no tea volume or invented unlock requirement")
	check(catalog.get_customer(&"missing") == null and request(&"missing") == null, "Unknown data lookups do not create placeholder identities")


func check_request_validation() -> void:
	var tea := request(&"tea_cha").duplicate(true) as OrderRequestDef
	for mutation: Dictionary in [
		{"field": "id", "value": &""}, {"field": "id", "value": &" spaced "},
		{"field": "kind", "value": "bundle"}, {"field": "quantity", "value": 0}, {"field": "quantity", "value": 2},
		{"field": "recipe_id", "value": &""}, {"field": "recipe_id", "value": &"missing"},
		{"field": "recipe_id", "value": &"ginger_tea"}, {"field": "recipe_id", "value": &"lemon_tea"},
		{"field": "item_id", "value": &"banana"},
	]:
		var candidate := tea.duplicate(true) as OrderRequestDef
		candidate.set(mutation.field, mutation.value)
		check(not candidate.validate(catalog).is_empty() and candidate.snapshot(catalog).is_empty(),
			"Invalid tea configuration is diagnosed and cannot become a snapshot: %s=%s" % [mutation.field, mutation.value])
	check(not tea.validate(null).is_empty(), "Missing Catalog cannot validate a request")
	var ready := request(&"ready_banana").duplicate(true) as OrderRequestDef
	for item_id: StringName in [&"missing", &"black_tea", &"sugar", &"water"]:
		ready.item_id = item_id
		check(not ready.validate(catalog).is_empty(), "A ready request cannot pretend an ingredient/water is a ready piece")
	ready.item_id = &"banana"
	ready.recipe_id = &"cha"
	check(not ready.validate(catalog).is_empty(), "A ready item cannot also request tea")
	ready.recipe_id = &""
	var original_item: ItemDef = catalog.items[&"banana"]
	for mutation: Dictionary in [
		{"field": "id", "value": &"different"}, {"field": "category", "value": &"ingredient"},
		{"field": "unit", "value": &"spoonful"}, {"field": "sell_price", "value": 0}, {"field": "sell_price", "value": -1},
	]:
		var item := original_item.duplicate(true) as ItemDef
		item.set(mutation.field, mutation.value)
		catalog.items[&"banana"] = item
		check(not ready.validate(catalog).is_empty(), "Invalid ready-item catalog metadata is rejected: " + String(mutation.field))
	catalog.items[&"banana"] = original_item
	check(ready.validate(catalog).is_empty(), "Restoring ready-item metadata restores eligibility")


func reject_recipe_change(label: String, mutate: Callable) -> void:
	var original: Resource = catalog.recipes[&"cha"]
	var changed: Resource = original.duplicate(true)
	mutate.call(changed)
	catalog.recipes[&"cha"] = changed
	check(not request(&"tea_cha").validate(catalog).is_empty(), "Invalid recipe is diagnosed: " + label)
	check(make_order(&"invalid_recipe") == null, "Invalid referenced recipe cannot generate an order: " + label)
	catalog.recipes[&"cha"] = original


func check_recipe_validation() -> void:
	for mutation: Dictionary in [
		{"field": "id", "value": &"wrong_id"}, {"field": "production_supported", "value": false},
		{"field": "price", "value": 0}, {"field": "price", "value": -1},
		{"field": "output_item_id", "value": &""}, {"field": "brewed_liquid_id", "value": &"missing"},
		{"field": "brewed_liquid_id", "value": &"sugar"},
		{"field": "minimum_serving_volume_ml", "value": 0.0}, {"field": "minimum_serving_volume_ml", "value": -1.0},
		{"field": "minimum_serving_volume_ml", "value": 251.0}, {"field": "minimum_serving_volume_ml", "value": NAN},
		{"field": "target_serving_volume_ml", "value": 1501.0}, {"field": "target_serving_volume_ml", "value": INF},
		{"field": "max_batch_volume_ml", "value": 249.0}, {"field": "max_batch_volume_ml", "value": INF},
	]:
		reject_recipe_change(String(mutation.field), func(recipe: Resource) -> void: recipe.set(mutation.field, mutation.value))
	reject_recipe_change("missing portion unit", func(recipe: Resource) -> void: recipe.kettle_portion_units.clear())
	reject_recipe_change("wrong portion unit", func(recipe: Resource) -> void: recipe.cup_portion_units[&"sugar"] = &"piece")
	reject_recipe_change("zero desired amount", func(recipe: Resource) -> void: recipe.cup_portion_counts[&"sugar"] = 0)
	reject_recipe_change("negative desired amount", func(recipe: Resource) -> void: recipe.kettle_portion_counts[&"black_tea"] = -1)
	reject_recipe_change("extra unit without amount", func(recipe: Resource) -> void: recipe.cup_portion_units[&"condensed_milk"] = &"spoonful")
	reject_recipe_change("unknown ingredient", func(recipe: Resource) -> void: recipe.cup_portion_counts[&"missing"] = 1)
	reject_recipe_change("no batch ingredient", func(recipe: Resource) -> void: recipe.kettle_portion_counts.clear())
	reject_recipe_change("unresolved base", func(recipe: Resource) -> void: recipe.base_item_ids.append(&"missing"))
	reject_recipe_change("duplicate base", func(recipe: Resource) -> void: recipe.base_item_ids.append(&"black_tea"))
	reject_recipe_change("relish without desired count", func(recipe: Resource) -> void: recipe.relish_item_ids.append(&"condensed_milk"))
	reject_recipe_change("boiling batch without water", func(recipe: Resource) -> void: recipe.base_item_ids.erase(&"water"))
	var original: Resource = catalog.recipes[&"cha"]
	catalog.recipes[&"cha"] = Resource.new()
	check(not request(&"tea_cha").validate(catalog).is_empty() and make_order(&"wrong_resource") == null,
		"A wrong resource type is diagnosed safely rather than read as a recipe")
	catalog.recipes[&"cha"] = original
	var original_water: ItemDef = catalog.items[&"water"]
	var bad_water := original_water.duplicate(true) as ItemDef
	bad_water.unit = &"piece"
	catalog.items[&"water"] = bad_water
	check(not request(&"tea_cha").validate(catalog).is_empty(), "Measured water cannot be reinterpreted as a counted piece")
	catalog.items[&"water"] = original_water
	var locked: Resource = original.duplicate(true)
	locked.unlocked_by_default = false
	catalog.recipes[&"cha"] = locked
	check(not request(&"tea_cha").validate(catalog).is_empty() and make_order(&"locked") == null, "Locked tea cannot be generated for the current level")
	check(request(&"tea_cha").validate(catalog, false).is_empty(), "Explicit design inspection can validate a locked recipe independently of level eligibility")
	locked.production_supported = false
	check(not request(&"tea_cha").validate(catalog, false).is_empty(), "Ignoring unlock eligibility never enables unsupported production recipes")
	catalog.recipes[&"cha"] = original
	check(catalog.validate_customer_orders().is_empty(), "Negative recipe fixtures restore all shipped data")


func check_profile_validation() -> void:
	var original: CustomerDef = catalog.get_customer(&"customer_a")
	for field: StringName in [&"id", &"display_name_key"]:
		var invalid_identity := original.duplicate(true) as CustomerDef
		invalid_identity.set(field, "")
		check(not invalid_identity.validate(catalog).is_empty(), "Customer identity/display data cannot be blank")
	for duration: float in [0.0, -1.0, INF, NAN]:
		var changed := original.duplicate(true) as CustomerDef
		changed.patience_seconds = duration
		check(not changed.validate(catalog).is_empty(), "Patience must be finite and positive")
	var optional := original.duplicate(true) as CustomerDef
	optional.sprite_texture = null
	optional.dialogue_profile = &""
	optional.patience_seconds = 123.0
	check(optional.validate(catalog).is_empty(), "Editable patience and optional art/dialogue need no customer scene")
	var empty := original.duplicate(true) as CustomerDef
	empty.order_requests.clear()
	check(not empty.validate(catalog).is_empty(), "Empty customer order pools fail validation")
	empty.order_requests.append(null)
	check(not empty.validate(catalog).is_empty(), "Missing pool entries fail validation")
	var duplicate := original.duplicate(true) as CustomerDef
	duplicate.order_requests.append(duplicate.order_requests[0])
	check(not duplicate.validate(catalog).is_empty(), "Duplicate request identities do not become ambiguous pool entries")
	var divergent := original.duplicate(true) as CustomerDef
	divergent.order_requests[0] = request(&"tea_cha_no_sugar").duplicate(true) as OrderRequestDef
	check(not divergent.validate(catalog).is_empty(), "A copied request cannot silently diverge under an existing shared Catalog identity")
	var invalid := original.duplicate(true) as CustomerDef
	var bad_request := request(&"tea_cha").duplicate(true) as OrderRequestDef
	bad_request.id = &"bad_reference"
	bad_request.recipe_id = &"missing"
	invalid.order_requests.append(bad_request)
	catalog.customers[original.id] = invalid
	check(catalog.get_available_customers().size() == 1, "An invalid profile is excluded as a whole, without silently dropping its bad option")
	check(make_order(&"invalid_pool", &"tea_cha_no_sugar") == null, "Even a valid member cannot bypass its profile's invalid pool")
	check(not catalog.validate_customer_orders().is_empty(), "Catalog exposes invalid profile diagnostics")
	var restricted := original.duplicate(true) as CustomerDef
	restricted.order_requests.clear()
	restricted.order_requests.append(request(&"ready_banana"))
	catalog.customers[original.id] = restricted
	check(make_order(&"outside_pool", &"tea_cha") == null and make_order(&"inside_pool", &"ready_banana") != null,
		"Order creation respects the selected customer's pool instead of the global request list")
	catalog.customers[original.id] = original
	check(catalog.get_available_customers().size() == 2, "Restoring the profile restores both available customers")


func check_order_snapshots() -> void:
	var tea := make_order(&"snapshot_order")
	check(tea != null and tea.order_id == &"snapshot_order" and tea.customer_id == &"customer_a"
		and tea.request_id == &"tea_cha" and tea.request_kind == &"tea" and tea.recipe_id == &"cha" and tea.item_id.is_empty(),
		"Tea order holds stable exclusive identity independently of scene nodes")
	check(tea.created_time == 12.5 and not tea.fulfilled and tea.get_results().is_empty(), "A new order has creation time but no invented outcome")
	var expected: Dictionary = tea.get_request()
	var copy: Dictionary = tea.get_snapshot()
	copy.order_id = &"changed"
	copy.request.cup_portion_counts[&"sugar"] = 999
	copy.request.base_item_ids.clear()
	check(tea.order_id == &"snapshot_order" and tea.get_request() == expected, "Aggregate snapshot mutation cannot rewrite nested order data")
	copy = tea.get_request()
	copy.kettle_portion_units.clear()
	check(tea.get_request() == expected, "The dedicated request accessor also detaches nested containers")
	var original: Resource = catalog.recipes[&"cha"]
	var edited: Resource = original.duplicate(true)
	edited.price = 99
	edited.cup_portion_counts[&"sugar"] = 5
	catalog.recipes[&"cha"] = edited
	check(tea.get_request() == expected, "Later recipe edits do not rewrite an existing order")
	var later := make_order(&"later_order")
	check(later.get_request().price == 99 and later.get_request().cup_portion_counts[&"sugar"] == 5,
		"New orders use current designer data while previous orders retain their snapshot")
	catalog.recipes[&"cha"] = original
	tea.order_id = &"reassigned"
	tea.fulfilled = true
	check(tea.order_id == &"snapshot_order" and not tea.fulfilled, "Public identity and fulfillment properties cannot bypass authoritative recording")
	var piece := make_order(&"piece_snapshot", &"ready_banana")
	check(piece.recipe_id.is_empty() and piece.item_id == &"banana" and piece.get_request().unit == &"piece", "Ready orders retain piece identity without a recipe alias")
	check(make_order(&"") == null and catalog.create_order(&"missing_customer", &"missing", &"tea_cha", 0.0) == null,
		"Missing order/customer identities cannot create authoritative orders")
	for time: float in [-1.0, NAN, INF]:
		check(catalog.create_order(&"bad_time", &"customer_a", &"tea_cha", time) == null, "Creation time must be finite and nonnegative")
	check(catalog.create_order(&"time_zero", &"customer_a", &"tea_cha", 0.0) != null, "A valid day-start creation time remains allowed")
	for mutation: Dictionary in [
		{"field": "id", "value": &""}, {"field": "kind", "value": &"bundle"}, {"field": "quantity", "value": 2},
		{"field": "quantity", "value": 1.0},
		{"field": "quantity", "value": true},
		{"field": "unit", "value": &"piece"}, {"field": "price", "value": 0}, {"field": "price", "value": 1.5},
		{"field": "item_id", "value": &"banana"},
		{"field": "minimum_serving_volume_ml", "value": NAN},
		{"field": "cup_portion_counts", "value": {&"sugar": 1.5}},
		{"field": "cup_portion_units", "value": {&"sugar": 1}},
		{"field": "base_item_ids", "value": "water,black_tea"},
		{"field": "batch_requires_boiling_water", "value": 1},
	]:
		var invalid: Dictionary = expected.duplicate(true)
		invalid[mutation.field] = mutation.value
		check(OrderState.create(&"bad_snapshot", &"customer_a", invalid, 0.0) == null, "Malformed direct order snapshot is rejected: " + String(mutation.field))
	for field: StringName in [&"minimum_serving_volume_ml", &"cup_portion_counts", &"output_item_id"]:
		var missing: Dictionary = expected.duplicate(true)
		missing.erase(field)
		check(OrderState.create(&"missing_metadata", &"customer_a", missing, 0.0) == null,
			"Direct tea snapshots require their declared metadata: " + String(field))
	check(tea.get_request().icon == (catalog.items[&"black_tea"] as ItemDef).icon, "Copy-safe order data intentionally keeps shared artwork identity")


func check_outcomes() -> void:
	for cold: bool in [false, true]:
		var order := make_order(&"cold_order" if cold else &"warm_order")
		var result := make_result(order, &"first_handoff", true, cold)
		var data: Dictionary = result.get_snapshot()
		check(data.accepted and data.fulfilled and data.cold_at_handoff == cold, "Warm and cold accepted tea both fulfill the data contract")
		check(data.unhappy == cold and data.bad_review == cold and data.reason == (&"cold_tea" if cold else &"tea_served"),
			"Cold tea alone adds the approved unhappy/bad-review outcome")
		check(order.record_result(result) and order.fulfilled, "The first accepted handoff records fulfillment")
		var accepted: Dictionary = order.get_accepted_result()
		data.bad_review = not cold
		data.handoff_id = &"changed"
		check(result.get_snapshot().bad_review == cold and result.get_snapshot().handoff_id == &"first_handoff", "Result snapshots are detached from their authoritative value")
		check(not order.record_result(result), "Replaying the same result object does not fulfill twice")
		check(not order.record_result(make_result(order, &"first_handoff", true, not cold)), "Conflicting replay of a handoff identity cannot replace history")
		check(not order.record_result(make_result(order, &"later_accept", true, not cold)), "A new accepted handoff cannot fulfill an already fulfilled order again")
		check(not order.record_result(make_result(order, &"later_reject", false, false, &"wrong_request")), "A later rejected attempt cannot rewrite fulfilled history")
		check(order.get_results().size() == 1 and order.get_accepted_result() == accepted, "All repeated callbacks leave one unchanged accepted outcome")
		var results: Array[Dictionary] = order.get_results()
		results[0].reason = &"mutated"
		results.clear()
		var historical: Dictionary = order.get_result(&"first_handoff")
		historical.accepted = false
		var aggregate: Dictionary = order.get_snapshot()
		aggregate.accepted_result.bad_review = not cold
		aggregate.results[0].fulfilled = false
		check(order.get_results().size() == 1 and order.get_accepted_result() == accepted, "All history accessors return independent mutable containers")
		check(not accepted.has("payment") and not accepted.has("reputation") and not accepted.has("discount"), "Outcome data introduces no finance or broad reputation policy")
	var retry := make_order(&"retry_order")
	var rejected := make_result(retry, &"wrong_handoff", false, true, &"wrong_request")
	check(retry.record_result(rejected) and not retry.fulfilled, "Rejected wrong tea remains unfulfilled")
	check(rejected.get_snapshot().cold_at_handoff and not rejected.get_snapshot().unhappy and not rejected.get_snapshot().bad_review,
		"A rejected cold attempt preserves its condition without an accepted-service review")
	check(not retry.record_result(make_result(retry, &"wrong_handoff", true)), "A rejected attempt's identity cannot be reused as an accepted handoff")
	check(retry.record_result(make_result(retry, &"fresh_handoff", true)) and retry.fulfilled and retry.get_results().size() == 2,
		"A corrected fresh handoff can fulfill once after a rejected attempt")
	var ready := make_order(&"ready_order", &"ready_biscuits")
	var ready_result := make_result(ready, &"ready_handoff", true)
	check(ready.record_result(ready_result) and ready.fulfilled, "An accepted ready piece fulfills its own typed order")
	check(ready_result.get_snapshot().reason == &"ready_item_served" and not ready_result.get_snapshot().cold_at_handoff
		and not ready_result.get_snapshot().unhappy and not ready_result.get_snapshot().bad_review, "Ready-item service inherits no tea thermal consequence")
	check(make_result(ready, &"cold_piece", true, true) == null, "Ready-item data cannot invent a cold-snack condition")
	var identity := make_order(&"identity_order")
	for mismatch: ServiceResult in [
		ServiceResult.create(&"other_order", &"different", identity.customer_id, &"tea", true),
		ServiceResult.create(&"other_customer", identity.order_id, &"different", &"tea", true),
		ServiceResult.create(&"other_kind", identity.order_id, identity.customer_id, &"ready_item", true),
	]:
		check(not identity.record_result(mismatch) and not identity.fulfilled and identity.get_results().is_empty(), "Mismatched order/customer/request kind cannot enter history")
	check(not identity.record_result(null) and not identity.record_result(ServiceResult.new()), "Missing/unconfigured results cannot fulfill an order")
	check(not OrderState.new().record_result(make_result(identity, &"uninitialized", true)), "An uninitialized order cannot acquire fulfillment")
	check(ServiceResult.create(&"", &"order", &"customer", &"tea", true) == null, "A result needs stable handoff identity")
	check(ServiceResult.create(&"handoff", &"", &"customer", &"tea", true) == null, "A result needs stable order identity")
	check(ServiceResult.create(&"handoff", &"order", &"", &"tea", true) == null, "A result needs stable customer identity")
	check(ServiceResult.create(&"handoff", &"order", &"customer", &"bundle", true) == null, "Unsupported result kinds cannot imply bundle support")
	check(ServiceResult.create(&"handoff", &"order", &"customer", &"tea", false) == null, "Rejected results require a reason")
	check(ServiceResult.create(&"handoff", &"order", &"customer", &"tea", true, false, &"wrong_request") == null, "Accepted results cannot also claim a rejection reason")
	check(identity.get_result(&"missing").is_empty() and identity.get_accepted_result().is_empty(), "Missing history does not produce placeholder outcomes")


func run() -> void:
	catalog = root.get_node("Catalog")
	state = root.get_node("GameState")
	check(state.ensure_inventory(), "Isolation fixture initializes shared stock")
	state.ensure_water_day()
	var stock: Dictionary = state.inventory.quantities
	var water: float = state.water_supply.remaining_ml
	var cup := CUP.instantiate() as Cup
	root.add_child(cup)
	cup.set_process(false)
	cup.receive_liquid(&"black_tea", 225.0, 30.0, {&"sugar": 0.5})
	cup.assigned_order_id = &"unrelated_live_order"
	var cup_state: Array = [cup.state, cup.volume_ml, cup.temperature, cup.assigned_order_id, cup.get_ingredient_amounts()]
	check_catalog_data()
	check_request_validation()
	check_recipe_validation()
	check_profile_validation()
	check_order_snapshots()
	check_outcomes()
	check(state.inventory.quantities == stock and state.water_supply.remaining_ml == water, "Pure order/result operations neither consume nor replenish shared supplies")
	check([cup.state, cup.volume_ml, cup.temperature, cup.assigned_order_id, cup.get_ingredient_amounts()] == cup_state,
		"Pure order/result operations do not serve, discard, cool or otherwise mutate an unrelated live cup")
	check(catalog.validate_customer_orders().is_empty() and catalog.get_available_customers().size() == 2, "All negative fixtures leave the shipped data restored")
	cup.queue_free()
	await process_frame
	print("CUSTOMER_ORDER_DATA: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
