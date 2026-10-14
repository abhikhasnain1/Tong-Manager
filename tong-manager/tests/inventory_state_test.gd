extends SceneTree

# Contract adapters below deliberately stand in for a physical source and a
# future Khata export. They do not implement the Khata UI or final recipe rules.
const STARTING := {&"black_tea": 4, &"sugar": 6, &"condensed_milk": 3, &"banana": 2, &"biscuits": 2}
const UNITS := {&"black_tea": &"teabag", &"sugar": &"spoonful", &"condensed_milk": &"spoonful", &"banana": &"piece", &"biscuits": &"piece"}
const MAX_INT := 9223372036854775807

class ContractTarget extends Node2D:
	var accepted := 0
	var capacity := 2
	func apply() -> bool:
		if not is_inside_tree() or is_queued_for_deletion() or accepted >= capacity:
			return false
		accepted += 1
		return true

var checks := 0
var failures: Array[String] = []
var notifications := 0
var callback_inventory: InventoryState
var callback_token := 0
var callback_other_token := 0
var target_effects := 0
var callback_game_state: Node
var reset_observations: Array[Dictionary] = []
var reset_config: Resource

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _changed() -> void:
	notifications += 1

func _apply() -> bool:
	target_effects += 1
	return true

func _reject() -> bool:
	return false

func fresh() -> InventoryState:
	var inventory := InventoryState.new()
	check(inventory.reset(STARTING, UNITS), "Known nonnegative integer stock initializes")
	return inventory

func verify_mutations() -> void:
	var inventory := fresh()
	check(inventory is PortionStockProvider, "Production inventory implements the existing portion interface")
	check(inventory.get_quantity(&"sugar") == 6 and inventory.remaining(&"sugar") == 6, "Quantity and provider views share one balance")
	check(inventory.get_unit(&"black_tea") == &"teabag" and inventory.get_unit(&"condensed_milk") == &"spoonful", "Current source units require no gram or volume conversion")
	check(inventory.get_quantity(&"unknown") == 0 and inventory.available(&"unknown") == 0, "Unknown item reads are empty")
	check(inventory.get_unit(&"unknown") == &"", "Unknown item has no invented unit")
	var snapshot: Dictionary = inventory.quantities
	snapshot[&"sugar"] = -100
	snapshot[&"unknown"] = 100
	check(inventory.get_quantity(&"sugar") == 6 and inventory.get_quantity(&"unknown") == 0, "A returned quantity dictionary cannot mutate inventory")
	var starting: Dictionary = STARTING.duplicate()
	var units: Dictionary = UNITS.duplicate()
	check(inventory.reset(starting, units), "Mutable caller dictionaries can initialize stock")
	starting[&"sugar"] = 100
	units[&"sugar"] = &"ml"
	check(inventory.remaining(&"sugar") == 6 and inventory.get_unit(&"sugar") == &"spoonful", "Caller changes cannot alter stored counts or units")
	for item_id in [&"unknown", &"water"]:
		check(not inventory.can_consume(item_id, 1), "Unknown or measured-water items cannot consume integer stock")
		check(not inventory.consume(item_id, 1) and not inventory.add(item_id, 1) and not inventory.set_quantity(item_id, 1), "Mutations cannot create an unregistered item or duplicate water")
	for amount in [-1, 0]:
		check(not inventory.can_consume(&"sugar", amount) and not inventory.consume(&"sugar", amount), "Nonpositive consumption is rejected")
		check(not inventory.add(&"sugar", amount), "Nonpositive additions are rejected")
	check(not inventory.set_quantity(&"sugar", -1), "Setting a negative quantity is rejected")
	check(inventory.can_consume(&"sugar", 6) and not inventory.can_consume(&"sugar", 7), "Consumption checks the actual balance")
	check(inventory.consume(&"sugar", 2) and inventory.remaining(&"sugar") == 4, "Successful direct consumption subtracts exactly its amount")
	check(not inventory.consume(&"sugar", 5) and inventory.remaining(&"sugar") == 4, "Over-consumption does not change stock")
	check(inventory.add(&"sugar", 3) and inventory.remaining(&"sugar") == 7, "Positive addition changes only the requested balance")
	check(inventory.set_quantity(&"sugar", 0) and inventory.remaining(&"sugar") == 0, "An empty quantity can be set explicitly")
	check(inventory.set_quantity(&"sugar", MAX_INT), "Maximum integer stock is representable")
	check(not inventory.add(&"sugar", 1) and inventory.remaining(&"sugar") == MAX_INT, "Overflow cannot wrap a balance below zero")
	check(inventory.consume(&"sugar", 1) and inventory.add(&"sugar", 1), "Near-limit arithmetic preserves an exact integer balance")
	check(inventory.reset(STARTING, UNITS), "An explicit valid reset restores authored values")
	inventory.changed.connect(_changed)
	notifications = 0
	var before := inventory.quantities
	var invalid_seeds: Array[Dictionary] = [
		{&"sugar": -1}, {&"sugar": 1.0}, {&"sugar": true},
		{&"sugar": "1"}, {&"sugar": []}, {&"unknown": 1},
	]
	for seed in invalid_seeds:
		check(not inventory.can_reset(seed, UNITS) and not inventory.reset(seed, UNITS), "Invalid reset data is rejected before mutation")
		check(inventory.quantities == before, "Rejected reset preserves every existing balance")
	check(not inventory.reset({&"sugar": 1}, {}), "Missing unit metadata rejects initialization")
	check(not inventory.reset({&"sugar": 1}, {&"sugar": &""}), "Empty unit metadata rejects initialization")
	check(not inventory.reset({&"water": 100}, {&"water": &"ml"}), "Measured water cannot become integer portion stock")
	check(not inventory.reset({&"sugar": 1}, {&"sugar": &"ml"}), "Any measured ml stock is excluded from the portion authority")
	check(notifications == 0 and inventory.quantities == before, "Rejected resets emit no successful-change notification")
	check(inventory.reset(STARTING, UNITS, false) and notifications == 0, "Coordinated reset can defer stock notification")
	inventory.changed.disconnect(_changed)

func _reentrant_apply() -> bool:
	check(callback_inventory.is_committing(), "Target callback runs inside the stock commit guard")
	check(callback_inventory.remaining(&"sugar") == 5, "Target observers see the claimed debit")
	check(not callback_inventory.commit(callback_token, _apply), "The committing token cannot reenter its target")
	check(not callback_inventory.commit(callback_other_token, _apply), "Another token cannot commit during target application")
	check(not callback_inventory.consume(&"sugar", 1), "Direct consumption cannot race target application")
	check(not callback_inventory.add(&"sugar", 1), "Addition cannot race target application")
	check(not callback_inventory.set_quantity(&"sugar", 1), "Quantity replacement cannot race target application")
	check(callback_inventory.reserve(&"sugar", &"spoonful", 1, 33) == 0, "A callback cannot create another reservation during commit")
	check(not callback_inventory.reset(STARTING, UNITS), "A callback cannot reset stock during commit")
	var before_notifications := notifications
	callback_inventory.release(callback_other_token)
	check(notifications == before_notifications, "Cleanup during commit defers its stock notification")
	check(not callback_inventory.reservation_matches(callback_other_token, &"sugar", &"spoonful", 1, 22), "Cleanup can release an unrelated held reservation")
	target_effects += 1
	return true

func verify_reservations() -> void:
	var inventory := fresh()
	for args in [[&"unknown", &"piece", 1, 1], [&"sugar", &"ml", 1, 1], [&"sugar", &"spoonful", 0, 1], [&"sugar", &"spoonful", -1, 1], [&"sugar", &"spoonful", 1, 0], [&"sugar", &"spoonful", 1, -1]]:
		check(inventory.reserve(args[0], args[1], args[2], args[3]) == 0, "Invalid reservation cannot claim stock")
	var token := inventory.reserve(&"sugar", &"spoonful", 4, 11)
	check(token > 0 and inventory.remaining(&"sugar") == 6 and inventory.available(&"sugar") == 2, "Pickup reserves stock without consuming it")
	check(inventory.reservation_matches(token, &"sugar", &"spoonful", 4, 11), "Reservation binds item, unit, quantity and source identity")
	for args in [[&"sugar", &"spoonful", 4, 12], [&"banana", &"piece", 4, 11], [&"sugar", &"ml", 4, 11], [&"sugar", &"spoonful", 1, 11]]:
		check(not inventory.reservation_matches(token, args[0], args[1], args[2], args[3]), "A different identity cannot reuse a reservation")
	check(inventory.reserve(&"sugar", &"spoonful", 3, 22) == 0, "Another source cannot overbook the shared balance")
	check(not inventory.can_consume(&"sugar", 3) and not inventory.consume(&"sugar", 3), "Direct consumers cannot spend reserved stock")
	check(not inventory.set_quantity(&"sugar", 3), "Quantity replacement cannot strand a live reservation")
	check(inventory.consume(&"sugar", 2) and inventory.available(&"sugar") == 0, "Unreserved stock remains available to direct consumers")
	check(inventory.set_quantity(&"sugar", 4), "Setting exactly the reserved amount remains valid")
	inventory.release(token)
	inventory.release(token)
	check(inventory.remaining(&"sugar") == 4 and inventory.available(&"sugar") == 4, "Repeated cancellation restores availability exactly once")
	token = inventory.reserve(&"sugar", &"spoonful", 1, 11)
	target_effects = 0
	check(inventory.commit(token, _apply) and target_effects == 1 and inventory.remaining(&"sugar") == 3, "A successful command applies and deducts once")
	check(not inventory.commit(token, _apply) and target_effects == 1, "Repeated command delivery cannot duplicate its target effect")
	inventory.release(token)
	check(inventory.remaining(&"sugar") == 3, "Cleanup never refunds an already consumed portion")
	token = inventory.reserve(&"sugar", &"spoonful", 1, 11)
	check(not inventory.commit(token, _reject), "A rejecting target fails the transaction")
	check(inventory.remaining(&"sugar") == 3 and inventory.available(&"sugar") == 3, "Rejected target restores stock and releases its reservation")
	check(not inventory.commit(token, _apply), "A failed command token cannot be replayed against another target")
	token = inventory.reserve(&"sugar", &"spoonful", 1, 11)
	check(not inventory.commit(token, Callable()), "An invalid callback cannot debit stock")
	inventory.release(token)
	check(inventory.remaining(&"sugar") == 3 and inventory.available(&"sugar") == 3, "Invalid callback cleanup preserves stock")
	token = inventory.reserve(&"black_tea", &"teabag", 1, 11)
	check(inventory.reset(STARTING, UNITS), "Explicit reset replaces balances and clears reservations")
	var fresh_token := inventory.reserve(&"black_tea", &"teabag", 1, 11)
	check(fresh_token != token and not inventory.commit(token, _apply), "Reset cannot revive an old token through ID reuse")
	inventory.release(token)
	check(inventory.available(&"black_tea") == 3, "Releasing an old token cannot erase a fresh reservation")
	inventory.release(fresh_token)
	callback_inventory = inventory
	callback_token = inventory.reserve(&"sugar", &"spoonful", 1, 11)
	callback_other_token = inventory.reserve(&"sugar", &"spoonful", 1, 22)
	inventory.changed.connect(_changed)
	notifications = 0
	target_effects = 0
	check(inventory.commit(callback_token, _reentrant_apply), "Guarded target application succeeds")
	check(target_effects == 1 and inventory.remaining(&"sugar") == 5 and inventory.available(&"sugar") == 5, "Reentry cannot duplicate target effects or leak reservations")
	check(not inventory.is_committing() and notifications == 1, "Observers receive one settled stock update after commit and cleanup")
	inventory.changed.disconnect(_changed)
	callback_inventory = null
	for index in range(2):
		token = inventory.reserve(&"banana", &"piece", 1, 11 + index)
		check(token > 0 and inventory.commit(token, _apply), "Shared ready-item piece consumes finite stock")
	check(inventory.available(&"banana") == 0 and inventory.reserve(&"banana", &"piece", 1, 11) == 0, "Exhausted shared stock cannot create a payload")

func portion_from(inventory: InventoryState, source: Node2D, item_id: StringName = &"sugar") -> IngredientPortion:
	var portion := IngredientPortion.new(item_id, inventory.get_unit(item_id), source, inventory)
	portion.token = inventory.reserve(item_id, portion.unit, portion.quantity, portion.source_id)
	return portion

func verify_contract_adapters() -> void:
	var inventory := fresh()
	var physical_source := Node2D.new()
	var khata_adapter := Node2D.new()
	var target := ContractTarget.new()
	root.add_child(physical_source)
	root.add_child(khata_adapter)
	root.add_child(target)
	var physical := portion_from(inventory, physical_source)
	var khata := portion_from(inventory, khata_adapter)
	check(physical.is_available() and khata.is_available() and inventory.available(&"sugar") == 4, "Physical and Khata contract adapters reserve the same authority")
	check(physical.commit(target.apply) and inventory.remaining(&"sugar") == 5, "Physical contract commits one effect and one debit")
	check(khata.commit(target.apply) and inventory.remaining(&"sugar") == 4 and target.accepted == 2, "Khata contract observes and consumes the same balance")
	check(not physical.commit(target.apply) and not khata.commit(target.apply), "Repeated adapter commands cannot repeat target mutations")
	physical.cancel()
	khata.cancel()
	check(inventory.remaining(&"sugar") == 4 and inventory.available(&"sugar") == 4, "Committed adapter cleanup cannot refund stock")
	var full := portion_from(inventory, khata_adapter)
	check(not full.commit(target.apply) and target.accepted == 2, "A full target rejects the contract command")
	full.cancel()
	check(inventory.remaining(&"sugar") == 4 and inventory.available(&"sugar") == 4, "Full-target rejection preserves stock")
	var canceled := portion_from(inventory, physical_source)
	canceled.cancel()
	canceled.cancel()
	check(not canceled.commit(target.apply) and inventory.available(&"sugar") == 4, "Canceled export stays invalid and releases once")
	var removed := portion_from(inventory, physical_source)
	physical_source.queue_free()
	check(not removed.is_available() and not removed.commit(target.apply), "Queued source removal invalidates its portion immediately")
	removed.cancel()
	await process_frame
	check(inventory.available(&"sugar") == 4, "Source-removal cleanup returns only the unused reservation")
	var detached := portion_from(inventory, khata_adapter)
	root.remove_child(khata_adapter)
	check(not detached.is_available() and not detached.commit(target.apply), "A detached source cannot deliver its live old token")
	detached.cancel()
	root.add_child(khata_adapter)
	var deleted_target := portion_from(inventory, khata_adapter)
	target.queue_free()
	check(not deleted_target.commit(target.apply), "Queued target deletion is rejected by the target adapter")
	deleted_target.cancel()
	await process_frame
	check(inventory.remaining(&"sugar") == 4 and inventory.available(&"sugar") == 4, "Deleted and detached targets cannot lose stock")
	var reset_portion := portion_from(inventory, khata_adapter)
	check(inventory.reset(STARTING, UNITS) and not reset_portion.is_available(), "Reset invalidates a held contract portion")
	reset_portion.cancel()
	check(inventory.available(&"sugar") == 6, "Old cleanup cannot refund into the reset allocation")
	khata_adapter.queue_free()
	await process_frame

func _record_reset(_amount: float = 0.0) -> void:
	reset_observations.append({
		"sugar": callback_game_state.inventory.remaining(&"sugar"),
		"water": callback_game_state.water_supply.remaining_ml,
		"reentrant": callback_game_state.reset_demo_state(reset_config),
	})

func _try_game_reset() -> bool:
	var before_stock: Dictionary = callback_game_state.inventory.quantities
	var before_water: float = callback_game_state.water_supply.remaining_ml
	var before_day: int = callback_game_state.water_supply.day_id
	check(not callback_game_state.reset_demo_state(reset_config), "GameState reset is refused during an inventory commit")
	check(callback_game_state.inventory.quantities == before_stock and callback_game_state.water_supply.remaining_ml == before_water and callback_game_state.water_supply.day_id == before_day, "Rejected in-flight reset changes neither authority")
	return true

func _try_reset_during_water() -> void:
	var before_stock: Dictionary = callback_game_state.inventory.quantities
	var before_water: float = callback_game_state.water_supply.remaining_ml
	check(not callback_game_state.reset_demo_state(reset_config), "GameState reset is refused during a measured-water transfer")
	check(callback_game_state.inventory.quantities == before_stock and callback_game_state.water_supply.remaining_ml == before_water, "Water callback cannot partially reset inventory")

func verify_game_state() -> void:
	var game_state := root.get_node("GameState")
	var config: Resource = load("res://data/balance/demo_day_1.tres").duplicate()
	config.starting_inventory = {&"black_tea": 3, &"sugar": 2, &"banana": 1}
	config.daily_water_ml = 900.0
	check(game_state.ensure_inventory(config), "First inventory initialization accepts the actual DayConfig")
	var inventory: InventoryState = game_state.inventory
	check(inventory.remaining(&"sugar") == 2 and inventory.remaining(&"banana") == 1, "Custom starting quantities win over demo and fixture defaults")
	check(inventory.get_unit(&"black_tea") == &"teabag" and inventory.get_unit(&"sugar") == &"spoonful", "Catalog units match the accepted physical portion forms")
	check(inventory.remaining(&"water") == 0 and inventory.reserve(&"water", &"ml", 1, 1) == 0, "Daily measured water has no duplicate ingredient balance")
	game_state.ensure_water_day(config)
	check(game_state.water_supply.remaining_ml == 900.0, "Custom initial water remains under its existing authority")
	check(inventory.consume(&"sugar", 1), "Custom inventory can be consumed")
	var other: Resource = config.duplicate()
	other.starting_inventory = {&"sugar": 999}
	other.daily_water_ml = 5000.0
	check(game_state.ensure_inventory(other) and game_state.inventory == inventory and inventory.remaining(&"sugar") == 1, "Repeated ensure with a different config never replenishes or replaces inventory")
	game_state.ensure_water_day(other)
	check(game_state.water_supply.remaining_ml == 900.0, "Repeated ensure does not replenish measured water")
	var water_source := Node2D.new()
	var kettle := load("res://scenes/gameplay/tools/Kettle.tscn").instantiate() as Kettle
	root.add_child(water_source)
	root.add_child(kettle)
	kettle.set_process(false)
	callback_game_state = game_state
	reset_config = config
	kettle.contents_changed.connect(_try_reset_during_water)
	var water_token: int = game_state.water_supply.reserve_transfer(water_source)
	check(game_state.water_supply.fill_kettle(water_token, kettle) == 900.0, "Measured fill consumes its sole finite water allocation")
	kettle.contents_changed.disconnect(_try_reset_during_water)
	check(game_state.water_supply.remaining_ml == 0.0 and inventory.remaining(&"sugar") == 1, "Water transfer changes no ingredient balance")
	check(kettle.discard_contents() == 900.0 and game_state.water_supply.remaining_ml == 0.0, "Discarding water cannot refund its source")
	var token := inventory.reserve(&"sugar", &"spoonful", 1, water_source.get_instance_id())
	check(inventory.commit(token, _try_game_reset), "Inventory can complete after a rejected reentrant reset")
	check(inventory.remaining(&"sugar") == 0 and game_state.water_supply.remaining_ml == 0.0, "Rejected reset leaves both depleted balances intact")
	var pending := inventory.reserve(&"black_tea", &"teabag", 1, water_source.get_instance_id())
	reset_observations.clear()
	inventory.changed.connect(_record_reset)
	game_state.water_supply.remaining_changed.connect(_record_reset)
	var old_day: int = game_state.water_supply.day_id
	check(game_state.reset_demo_state(config), "Explicit new demo state resets both resource-driven authorities")
	check(game_state.inventory == inventory and game_state.water_supply.day_id == old_day + 1, "Reset preserves bound inventory identity and deliberately advances the water day")
	check(reset_observations.size() == 2, "Coordinated reset notifies stock and water observers once each")
	for observation in reset_observations:
		check(observation.sugar == 2 and observation.water == 900.0 and not observation.reentrant, "Every reset observer sees both completed balances and cannot reenter reset")
	inventory.changed.disconnect(_record_reset)
	game_state.water_supply.remaining_changed.disconnect(_record_reset)
	check(not inventory.commit(pending, _apply), "Explicit reset invalidates pre-reset reservations")
	var before: Dictionary = inventory.quantities
	old_day = game_state.water_supply.day_id
	var invalid: Resource = config.duplicate()
	invalid.starting_inventory = {&"sugar": -1}
	check(not game_state.reset_demo_state(invalid), "Invalid stock config rejects the entire demo reset")
	check(inventory.quantities == before and game_state.water_supply.day_id == old_day and game_state.water_supply.remaining_ml == 900.0, "Invalid stock cannot advance or refill the water day")
	invalid = config.duplicate()
	invalid.daily_water_ml = -1.0
	check(not game_state.reset_demo_state(invalid), "Invalid water allocation rejects the entire demo reset")
	check(inventory.quantities == before and game_state.water_supply.day_id == old_day, "Invalid water cannot reset stock or advance day")
	callback_game_state = null
	kettle.queue_free()
	water_source.queue_free()
	await process_frame

func _source(screen: Node, owner_name: String) -> IngredientPortionSource:
	for source: IngredientPortionSource in screen.portion_sources:
		if source.source_owner.name == owner_name:
			return source
	return null

func verify_physical_injection() -> void:
	var game_state := root.get_node("GameState")
	var inventory: InventoryState = game_state.inventory
	var scene := load("res://scenes/gameplay/tong/TongDayScreen.tscn") as PackedScene
	var screen := scene.instantiate()
	root.add_child(screen)
	await process_frame
	await physics_frame
	screen.set_portion_provider(inventory)
	var controller := screen.get_node("InteractionController") as InteractionController
	controller.set_mode(InteractionController.MODE_INTERACT)
	var sugar := _source(screen, "SugarCan")
	var other_sugar := _source(screen, "SugarCanEnglish")
	var cup: Cup = screen.get_cups()[0]
	cup.set_process(false)
	cup.receive_liquid(&"black_tea", 150.0, 65.0)
	check(sugar.provider == inventory and other_sugar.provider == inventory, "Both placed sugar sources view the same production authority")
	var original_counts := inventory.quantities
	var original_units: Dictionary = {}
	for item_id: StringName in original_counts:
		original_units[item_id] = inventory.get_unit(item_id)
	inventory.changed.connect(func() -> void: inventory.reset(original_counts, original_units), CONNECT_ONE_SHOT)
	check(not sugar.begin_portion(sugar.source_owner.get_global_transform_with_canvas().origin), "Synchronous production reset during reserve cannot create a stale held portion")
	check(not controller.is_dragging() and inventory.available(&"sugar") == 2, "Interrupted pickup leaves production stock and controller coherent")
	check(sugar.begin_portion(sugar.source_owner.get_global_transform_with_canvas().origin), "Existing physical source can reserve production stock")
	var payload := controller.current_payload
	controller.release_drop(cup.get_node("IngredientTarget").get_global_transform_with_canvas().origin)
	check(inventory.remaining(&"sugar") == 1 and other_sugar.provider.available(&"sugar") == 1 and cup.relish_item_ids == [&"sugar"], "Production command applies once and both physical views see one shared debit")
	check(not cup.get_node("IngredientTarget").try_apply_drop(payload) and inventory.remaining(&"sugar") == 1, "Repeated target delivery cannot debit production stock again")
	check(cup.discard_contents() == 150.0 and inventory.remaining(&"sugar") == 1, "Discarding a garnished cup never refunds consumed ingredient stock")
	cup.receive_liquid(&"water", 100, 60)
	check(other_sugar.begin_portion(other_sugar.source_owner.get_global_transform_with_canvas().origin), "Second physical shortcut reserves the same final available spoonful")
	controller.release_drop(cup.get_node("IngredientTarget").get_global_transform_with_canvas().origin)
	check(inventory.remaining(&"sugar") == 1 and inventory.available(&"sugar") == 1 and cup.relish_item_ids.is_empty(), "Rejected incompatible-water target returns production reservation unchanged")
	check(other_sugar.begin_portion(other_sugar.source_owner.get_global_transform_with_canvas().origin), "A production portion can be held across an explicit reset request")
	var stale_payload := controller.current_payload
	var reset_to_remaining: Resource = screen.day_config.duplicate()
	reset_to_remaining.starting_inventory = inventory.quantities
	reset_to_remaining.daily_water_ml = 900.0
	check(game_state.reset_demo_state(reset_to_remaining), "Explicit coordinated reset accepts a held portion and invalidates its token")
	# process_frame resumes before Node._process; allow one complete idle pass.
	await process_frame
	await process_frame
	check(not controller.is_dragging() and inventory.available(&"sugar") == 1, "Reset clears a stationary held production portion without refunding into the new allocation")
	check(not cup.get_node("IngredientTarget").try_apply_drop(stale_payload), "A pre-reset physical payload cannot later mutate its target")
	check(sugar.begin_portion(sugar.source_owner.get_global_transform_with_canvas().origin), "Production source supports lifecycle cancellation")
	sugar.source_owner.queue_free()
	await process_frame
	check(not controller.is_dragging() and inventory.available(&"sugar") == 1, "Deleting a real physical source releases its production reservation")
	check(other_sugar.begin_portion(other_sugar.source_owner.get_global_transform_with_canvas().origin), "Another shortcut remains usable after source deletion")
	screen.queue_free()
	await process_frame
	check(inventory.available(&"sugar") == 1, "Whole scene exit releases production reservations without replenishing stock")
	screen = scene.instantiate()
	root.add_child(screen)
	await process_frame
	screen.set_portion_provider(inventory)
	check(game_state.ensure_inventory(screen.day_config) and game_state.inventory == inventory and inventory.remaining(&"sugar") == 1, "Screen recreation keeps the same depleted production stock")
	check(game_state.water_supply.remaining_ml == 900.0, "Screen recreation preserves the current finite water balance")
	screen.queue_free()
	await process_frame
	var fixture := DevelopmentPortionStock.new()
	check(fixture.reset_fixture() and inventory.remaining(&"sugar") == 1, "Development fixture reset never changes production inventory")

func run() -> void:
	verify_mutations()
	verify_reservations()
	await verify_contract_adapters()
	await verify_game_state()
	await verify_physical_injection()
	print("Inventory state checks: %d; failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
