extends SceneTree
## Production command matrix and physical/Khata integration; no customer-order implementation.

class BeforeApplyInventory extends InventoryState:
	var before_apply: Callable
	func commit(token: int, apply: Callable) -> bool:
		var guarded := func() -> bool:
			if before_apply.is_valid(): before_apply.call()
			return bool(apply.call())
		return super.commit(token, guarded)

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: KhataModal
var stock: InventoryState
var cup: Cup
var kettle: Kettle
var source_owner := Node2D.new()
var world: Node2D
var tray: TrayStation


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while (modal.book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not modal.book.busy and not modal.is_traveling(), "Notebook motion settles")
	await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func portion(item_id: StringName, quantity := 1, provider: InventoryState = null) -> IngredientPortion:
	if provider == null: provider = stock
	var result := IngredientPortion.new(item_id, provider.get_unit(item_id), source_owner, provider)
	result.quantity = quantity
	result.token = provider.reserve(item_id, result.unit, quantity, result.source_id)
	return result


func snapshot(target: Node2D) -> Dictionary:
	if target is Cup:
		var vessel := target as Cup
		return {"state": vessel.state, "volume": vessel.volume_ml, "temperature": vessel.temperature,
			"liquid": vessel.liquid_type, "base": vessel.contents_base_id, "ingredients": vessel.relish_item_ids.duplicate()}
	var vessel := target as Kettle
	return {"state": vessel.state, "volume": vessel.volume_ml, "temperature": vessel.temperature,
		"tea": vessel.contains_tea, "steep": vessel.steep_progress}


func attempt(target: Node2D, item_id: StringName, expected: bool, label: String, quantity := 1) -> void:
	var before := stock.remaining(item_id)
	var contents := snapshot(target)
	var held := portion(item_id, quantity)
	var command := IngredientDropCommand.new(held, target)
	var validation := command.can_execute()
	check(validation.is_valid == expected, "%s reports the approved eligibility" % label)
	check(snapshot(target) == contents and stock.remaining(item_id) == before, "%s validation changes neither stock nor contents" % label)
	check(command.execute() == expected, "%s executes only when valid" % label)
	if expected:
		check(stock.remaining(item_id) == before - 1 and stock.available(item_id) == before - 1, "%s consumes exactly one agreed portion" % label)
		var after := snapshot(target)
		check(not command.execute() and snapshot(target) == after and stock.remaining(item_id) == before - 1, "%s command cannot replay its effect or debit" % label)
	else:
		check(not validation.reason_key.is_empty(), "%s explains rejection" % label)
		check(snapshot(target) == contents and stock.remaining(item_id) == before, "%s rejection changes neither stock nor contents" % label)
	held.cancel()
	check(stock.available(item_id) == stock.remaining(item_id), "%s leaves no unused reservation after cleanup" % label)


func prepare_cup(kind: StringName = &"", amount := 0.0, served := false, dirty := false) -> void:
	cup.reset_clean()
	if amount > 0: cup.receive_liquid(kind, amount, 65)
	if served or dirty: cup.mark_served()
	if dirty: cup.mark_dirty()


func prepare_kettle(amount: float, boiling := true) -> void:
	kettle.discard_contents()
	if amount > 0: kettle.add_water(amount)
	kettle.temperature = kettle.config.boiling_temperature if boiling else kettle.config.ambient_temperature


func check_command_matrix() -> void:
	for item_id: StringName in [&"sugar", &"condensed_milk"]:
		prepare_cup()
		attempt(cup, item_id, true, "%s into clean empty cup" % item_id)
		check(cup.state == Cup.CupState.IN_USE and cup.volume_ml == 0 and cup.get_relish_count(item_id) == 1, "A dry spoon starts use without adding liquid")
		attempt(cup, item_id, true, "%s into in-use empty cup" % item_id)
		for amount in [100.0, 250.0]:
			prepare_cup(&"black_tea", amount)
			var temperature := cup.temperature
			attempt(cup, item_id, true, "%s into %dml tea cup" % [item_id, amount])
			check(cup.volume_ml == amount and cup.temperature == temperature, "Abstract spoon changes neither volume nor temperature, including full cups")
		prepare_cup(&"water", 100)
		attempt(cup, item_id, false, "%s into incompatible water" % item_id)
		prepare_cup(&"black_tea", 150, true)
		attempt(cup, item_id, false, "%s into served cup" % item_id)
		prepare_cup(&"black_tea", 150, true, true)
		attempt(cup, item_id, false, "%s into dirty cup" % item_id)
		prepare_kettle(500)
		attempt(kettle, item_id, false, "%s into kettle" % item_id)
	prepare_cup()
	for _index in range(5): attempt(cup, &"sugar", true, "Repeated counted sugar spoon")
	check(cup.get_relish_count(&"sugar") == 5 and cup.relish_item_ids.size() == 5, "No legacy three-spoon limit truncates counts")
	attempt(cup, &"sugar", false, "Two-spoon payload is not one grab", 2)
	attempt(cup, &"black_tea", false, "Teabag into cup")
	attempt(cup, &"banana", false, "Ready item into cup")
	for amount in [0.0, 0.01, 250.0, 1500.0]:
		prepare_kettle(amount)
		attempt(kettle, &"black_tea", amount > 0, "%sml boiling kettle" % amount)
		if amount > 0: attempt(kettle, &"black_tea", false, "Second teabag in one batch")
	prepare_kettle(500, false)
	attempt(kettle, &"black_tea", false, "Unboiled batch")
	prepare_kettle(1500)
	kettle.volume_ml = 1501
	attempt(kettle, &"black_tea", false, "Batch above approved 1500ml maximum")
	prepare_kettle(500)
	kettle.is_pouring = true
	attempt(kettle, &"black_tea", false, "Batch while pouring")
	kettle.is_pouring = false
	attempt(kettle, &"black_tea", false, "Two-bag payload is not one grab", 2)
	attempt(kettle, &"biscuits", false, "Ready item into kettle")
	prepare_cup()
	var held := portion(&"sugar")
	held.unit = &"piece"
	check(not IngredientDropCommand.new(held, cup).execute(), "A mutated unit cannot reuse a different reservation")
	held.cancel()
	check(stock.available(&"sugar") == stock.remaining(&"sugar"), "Mismatched-unit cleanup releases the original token")
	var before := stock.remaining(&"sugar")
	stock.set_quantity(&"sugar", 0)
	held = portion(&"sugar")
	check(held.token == 0 and not IngredientDropCommand.new(held, cup).execute(), "Depleted stock cannot apply a command")
	held.cancel()
	stock.set_quantity(&"sugar", before)


func check_policy_resources() -> void:
	var policy := IngredientDropCommand.DEFAULT_POLICY.duplicate(true) as IngredientPolicy
	prepare_cup()
	var sugar_rule := policy.rule_for(&"sugar", cup)
	check(sugar_rule != null and sugar_rule.unit == &"spoonful" and sugar_rule.allow_empty and sugar_rule.allow_repeated,
		"Default resource records approved cup portion rules")
	sugar_rule.allow_empty = false
	var held := portion(&"sugar")
	check(not IngredientDropCommand.new(held, cup, policy).can_execute().is_valid,
		"Command reads empty-cup permission from its injected policy")
	check(IngredientDropCommand.new(held, cup).can_execute().is_valid,
		"Changing an isolated policy does not mutate shared default rules")
	held.cancel()
	prepare_cup(&"black_tea", 150)
	cup.add_relish(&"sugar")
	sugar_rule.allow_repeated = false
	held = portion(&"sugar")
	check(not IngredientDropCommand.new(held, cup, policy).execute(), "Injected repeated-portion rule changes eligibility without command rewrites")
	held.cancel()
	prepare_kettle(500)
	var tea_rule := policy.rule_for(&"black_tea", kettle)
	check(tea_rule != null and tea_rule.requires_boiling and tea_rule.max_batch_volume_ml == 1500, "Default resource records the teabag batch allowance")
	tea_rule.max_batch_volume_ml = 250
	held = portion(&"black_tea")
	check(not IngredientDropCommand.new(held, kettle, policy).execute(), "Injected batch allowance is revalidated before application")
	held.cancel()
	check(stock.available(&"sugar") == stock.remaining(&"sugar") and stock.available(&"black_tea") == stock.remaining(&"black_tea"),
		"Rejected custom-policy commands leave no consumed or reserved stock after cleanup")


func check_command_lifecycle() -> void:
	prepare_cup(&"black_tea", 150)
	var held := portion(&"sugar")
	var command := IngredientDropCommand.new(held, cup)
	check(command.can_execute().is_valid, "State-change fixture starts valid")
	cup.mark_served()
	check(not command.execute() and cup.relish_item_ids.is_empty(), "Execute revalidates a cup served since hover")
	held.cancel()
	prepare_cup()
	held = portion(&"sugar")
	command = IngredientDropCommand.new(held, cup)
	var original_parent := cup.get_parent()
	original_parent.remove_child(cup)
	check(not command.execute(), "Detached target is rejected before mutation")
	original_parent.add_child(cup)
	held.cancel()
	held = portion(&"sugar")
	command = IngredientDropCommand.new(held, cup)
	screen.remove_child(source_owner)
	check(not command.execute(), "Detached source invalidates its pending command")
	screen.add_child(source_owner)
	held.cancel()
	var doomed := load("res://scenes/gameplay/tools/Cup.tscn").instantiate() as Cup
	screen.add_child(doomed)
	held = portion(&"sugar")
	command = IngredientDropCommand.new(held, doomed)
	doomed.queue_free()
	check(not command.execute(), "Queued target cannot accept a command before destruction finishes")
	held.cancel()
	await frames()
	# Mutation may emit synchronously. Neither the same token nor another stock
	# mutation can reenter the transaction from a vessel observer.
	prepare_cup()
	held = portion(&"sugar")
	command = IngredientDropCommand.new(held, cup)
	var before := stock.remaining(&"sugar")
	var nested := [true, true]
	cup.contents_changed.connect(func(_base: StringName, _relish: Array[StringName], _order: StringName) -> void:
		nested[0] = command.execute()
		nested[1] = stock.consume(&"condensed_milk", 1), CONNECT_ONE_SHOT)
	check(command.execute() and not nested[0] and not nested[1], "Vessel observers cannot reenter the command or debit other stock mid-commit")
	check(cup.get_relish_count(&"sugar") == 1 and stock.remaining(&"sugar") == before - 1, "Synchronous observers still leave exactly one ingredient and debit")
	# The provider deliberately changes receiver eligibility after claiming the
	# token but before the command's callback. That callback must validate again.
	prepare_cup()
	var interleaved := BeforeApplyInventory.new()
	interleaved.reset({&"sugar": 2}, {&"sugar": &"spoonful"})
	held = portion(&"sugar", 1, interleaved)
	interleaved.before_apply = func() -> void: cup.state = Cup.CupState.DIRTY
	check(not IngredientDropCommand.new(held, cup).execute(), "Commit callback revalidates target state after reservation claim")
	check(interleaved.remaining(&"sugar") == 2 and interleaved.available(&"sugar") == 2 and cup.relish_item_ids.is_empty(), "Rejected commit callback rolls back stock without a partial ingredient")
	held.cancel()
	prepare_cup()
	interleaved.before_apply = func() -> void: screen.remove_child(source_owner)
	held = portion(&"sugar", 1, interleaved)
	check(not IngredientDropCommand.new(held, cup).execute(), "Commit callback revalidates source liveness after reservation claim")
	check(interleaved.available(&"sugar") == 2 and cup.relish_item_ids.is_empty(), "Source removal inside commit loses no stock or contents")
	screen.add_child(source_owner)
	held.cancel()


func check_scene_ownership() -> void:
	# The same SceneTree is not enough ownership: another scene root must not
	# inherit permission from the original stall's target registration.
	prepare_cup()
	controller.set_mode(InteractionController.MODE_USE)
	var zone := cup.get_node("IngredientTarget") as IngredientPortionTarget
	var cup_pose := cup.transform
	var cup_parent := cup.get_parent()
	var payload := take_route("physical", &"sugar")
	var held := payload.metadata.get("portion") as IngredientPortion
	var command := IngredientDropCommand.new(held, cup, IngredientDropCommand.DEFAULT_POLICY, screen)
	check(zone.accepts(payload).is_valid and command.can_execute().is_valid,
		"Original stall owns its eligible source and cup before transfer")
	var before := stock.remaining(&"sugar")
	cup.reparent(root)
	check(cup.is_inside_tree() and not screen.is_ancestor_of(cup), "Ownership regression keeps the displaced cup live in the same tree")
	check(not zone.accepts(payload).is_valid and not zone.try_apply_drop(payload) and not command.execute(),
		"Cup reparented outside its stall loses both adapter and captured-command permission")
	check(stock.remaining(&"sugar") == before and cup.get_relish_counts().is_empty(),
		"Cross-scene receiver rejection consumes no stock and adds no ingredient")
	controller.cancel_drag()
	cup.reparent(cup_parent)
	cup.transform = cup_pose
	check(stock.available(&"sugar") == before, "Cross-scene rejection releases its pending reservation")
	var interleaved := BeforeApplyInventory.new()
	interleaved.reset({&"sugar": 2}, {&"sugar": &"spoonful"})
	interleaved.before_apply = func() -> void: cup.reparent(root)
	held = portion(&"sugar", 1, interleaved)
	command = IngredientDropCommand.new(held, cup, IngredientDropCommand.DEFAULT_POLICY, screen)
	check(command.can_execute().is_valid, "Callback-transfer regression starts inside the original stall")
	check(not command.execute() and cup.is_inside_tree() and not screen.is_ancestor_of(cup),
		"Commit callback revalidates receiver ownership after the provider claims the token")
	check(interleaved.remaining(&"sugar") == 2 and interleaved.available(&"sugar") == 2
		and cup.get_relish_counts().is_empty(), "Reparent during commit rolls stock back without a partial ingredient")
	held.cancel()
	cup.reparent(cup_parent)
	cup.transform = cup_pose


func physical_source(item_id: StringName) -> IngredientPortionSource:
	for source in screen.portion_sources:
		if source.item_id == item_id: return source
	return null


func take_route(route: String, item_id: StringName) -> HeldItemPayload:
	var before := stock.remaining(item_id)
	var began: bool
	if route == "physical":
		var source := physical_source(item_id)
		began = source.begin_portion(point(source.source_owner))
	else:
		began = modal.begin_inventory_export(item_id, modal.inventory_item_screen_rect(item_id).get_center())
	check(began and controller.is_dragging(), "%s route begins %s from the normal scene" % [route, item_id])
	check(stock.remaining(item_id) == before and stock.available(item_id) == before - 1, "Route pickup reserves one unit without a debit")
	return controller.current_payload


func use_route(route: String, item_id: StringName, target: Node2D, expected: bool) -> void:
	var before := stock.remaining(item_id)
	var contents := snapshot(target)
	var payload := take_route(route, item_id)
	var zone := target.get_node("IngredientTarget") as DropZone
	controller.update_drag(point(zone))
	check(zone.accepts(payload).is_valid == expected, "%s has the same approved %s eligibility" % [route, item_id])
	controller.release_drop(point(zone))
	check(not controller.is_dragging() and stock.remaining(item_id) == before - (1 if expected else 0)
		and stock.available(item_id) == stock.remaining(item_id), "%s resolves once with the correct stock effect" % route)
	if not expected: check(snapshot(target) == contents, "Invalid routed release preserves target contents")
	check(not zone.try_apply_drop(payload), "Replayed routed payload cannot apply again")
	if route != "physical":
		check(modal.is_peeking() == (route == "peek") and modal.is_open() == (route == "full")
			and modal.page_index == 0, "Production drop returns to its originating notebook view")


func check_normal_scene_routes() -> void:
	for source in screen.portion_sources:
		check(source.provider == stock, "Normal physical sources bind the same production stock as Khata")
	check(modal.inventory == stock, "Normal pantry binds that same authority without preview injection")
	for route in ["physical", "peek", "full"]:
		controller.set_mode(InteractionController.MODE_USE if route == "physical" else InteractionController.MODE_NEUTRAL)
		if route != "physical":
			check(modal.open_peek() if route == "peek" else modal.open(), "Normal scene opens a production export view")
			await settle()
		prepare_cup()
		use_route(route, &"sugar", cup, true)
		use_route(route, &"condensed_milk", cup, true)
		check(cup.get_relish_count(&"sugar") == 1 and cup.get_relish_count(&"condensed_milk") == 1 and cup.volume_ml == 0,
			"Both routes preserve counted dry ingredients before the base")
		cup.receive_liquid(&"black_tea", cup.capacity_ml, 65)
		use_route(route, &"sugar", cup, true)
		check(cup.get_relish_count(&"sugar") == 2 and cup.get_relish_count(&"condensed_milk") == 1 and cup.volume_ml == cup.capacity_ml,
			"Pouring preserves earlier ingredients and a full cup accepts another counted spoon")
		prepare_cup(&"water", 100)
		use_route(route, &"sugar", cup, false)
		prepare_kettle(500, false)
		use_route(route, &"black_tea", kettle, false)
		kettle.temperature = kettle.config.boiling_temperature
		use_route(route, &"black_tea", kettle, true)
		use_route(route, &"black_tea", kettle, false)
		use_route(route, &"sugar", kettle, false)
		use_route(route, &"black_tea", cup, false)
		var before := stock.remaining(&"sugar")
		take_route(route, &"sugar")
		controller.cancel_drag()
		check(stock.available(&"sugar") == before and not controller.is_dragging(), "Cancelled production route returns its unconsumed unit")
		if route != "physical":
			modal.close()
			await settle()


func base_center(item: Node2D) -> Vector2:
	var handle := item.get_node("PlacementHandle") as TablePlaceable
	var polygons := handle.surface.get_candidate_polygons(item)
	var bounds := Rect2(polygons[0][0], Vector2.ZERO)
	for polygon in polygons:
		for vertex in polygon: bounds = bounds.expand(vertex)
	return world.to_local(handle.surface.to_global(bounds.get_center()))


func move_item(item: Node2D, destination: Vector2, expected: PlacementSurface) -> void:
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	var handle := item.get_node("PlacementHandle") as TablePlaceable
	var origin := world.to_local(item.global_position)
	var pointer := world.get_global_transform_with_canvas() * (origin + destination - base_center(item))
	check(handle.begin_drag(point(item)), "Ingredient-bearing object begins a real placement gesture")
	controller.release_drop(pointer)
	check(not controller.is_dragging() and handle.surface == expected and base_center(item).distance_to(destination) < 0.01,
		"Placement preserves the actual target owner through free table/tray movement")


func check_movement_and_disposal() -> void:
	prepare_cup()
	controller.set_mode(InteractionController.MODE_USE)
	use_route("physical", &"sugar", cup, true)
	var zone := cup.get_node("IngredientTarget") as DropZone
	var original := base_center(cup)
	move_item(cup, Vector2(920.375, 940.625), screen.table_surface)
	check(cup.get_node("IngredientTarget") == zone and cup.get_relish_count(&"sugar") == 1, "Table transfer retains target identity and dry ingredients")
	controller.set_mode(InteractionController.MODE_USE)
	use_route("physical", &"condensed_milk", cup, true)
	move_item(cup, original, tray.interior_surface)
	var tray_origin := base_center(tray)
	move_item(tray, tray_origin + Vector2(-8.125, 29.375), screen.table_surface)
	check(cup.get_node("IngredientTarget") == zone and cup.get_relish_counts() == {&"sugar": 1, &"condensed_milk": 1}, "Populated tray movement carries the same ingredient target and counts")
	check(modal.open_peek(), "Moved tray cup remains available to the pantry")
	await settle()
	use_route("peek", &"sugar", cup, true)
	modal.close()
	await settle()
	move_item(tray, tray_origin, screen.table_surface)
	controller.set_mode(InteractionController.MODE_USE)
	var quantities := stock.quantities
	check(cup.has_contents() and cup.volume_ml == 0 and cup.begin_interaction_drag(point(cup)), "Cup with only dry spoons can begin disposal")
	var discard := screen.get_node("WorldRoot/DropZoneRoot/DiscardArea") as DropZone
	controller.release_drop(point(discard))
	check(not controller.is_dragging() and not cup.has_contents() and stock.quantities == quantities, "Dragging a dry-ingredient cup to discard clears contents without refund")
	# Follow a real measured-water refill, production teabag, brewing and pouring
	# through the same cup. Ingredient commands never charge water a second time.
	prepare_kettle(0)
	var supply: DailyWaterSupply = root.get_node("GameState").water_supply
	var water_before := supply.remaining_ml
	var drum := screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	check(drum.begin_drag(point(drum)), "Measured drum can start the next batch")
	controller.release_drop(point(kettle.get_node("WaterFillTarget")))
	check(kettle.volume_ml > 0 and is_equal_approx(supply.remaining_ml + kettle.volume_ml, water_before), "Refill debits exactly the measured water transferred")
	var after_fill := supply.remaining_ml
	kettle.temperature = kettle.config.boiling_temperature
	use_route("physical", &"black_tea", kettle, true)
	use_route("physical", &"sugar", cup, true)
	kettle.advance_brewing(kettle.config.steep_seconds)
	check(kettle.start_pour(cup), "Production batch pours into a cup already holding a spoon")
	kettle.update_pour(0.5)
	kettle.stop_pour()
	check(cup.volume_ml > 0 and cup.get_relish_count(&"sugar") == 1 and supply.remaining_ml == after_fill, "Pour retains cup ingredients without another water debit")
	quantities = stock.quantities
	check(cup.begin_interaction_drag(point(cup)), "Filled ingredient cup begins deliberate disposal")
	controller.release_drop(point(discard))
	check(not cup.has_contents() and stock.quantities == quantities and supply.remaining_ml == after_fill, "Filled-cup disposal refunds neither ingredients nor water")
	kettle.discard_contents()
	check(stock.quantities == quantities and supply.remaining_ml == after_fill, "Discarding the remainder of a used batch refunds nothing")


func run() -> void:
	root.size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(root.get_node("GameState").reset_demo_state(), "Production test starts with authoritative supplies")
	stock = root.get_node("GameState").inventory
	for item_id: StringName in [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]: stock.set_quantity(item_id, 200)
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames()
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	modal.book.sound_enabled = false
	world = screen.get_node("WorldRoot")
	tray = world.get_node("ToolLayer/TrayStation")
	cup = screen.get_cups()[0]
	kettle = world.get_node("ToolLayer/KettleStation")
	kettle.set_process(false)
	for vessel: Cup in screen.get_cups(): vessel.set_process(false)
	for burner in world.get_node("ToolLayer/StoveStation").burners: burner.set_process(false)
	screen.add_child(source_owner)
	check_command_matrix()
	check_policy_resources()
	await check_command_lifecycle()
	check_scene_ownership()
	await check_normal_scene_routes()
	await check_movement_and_disposal()
	screen.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and stock.available(&"sugar") == stock.remaining(&"sugar"), "Production scene teardown leaves no held stock or cursor")
	print("INGREDIENT_COMMANDS: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
