extends "res://tests/ingredient_commands_input_test.gd"
## Real sandbox selection and gestures; temperature/time alone use fixtures.

var preview: Node
var picker: OptionButton
var initial_stock: Dictionary[StringName, int]


func select_example(index: int) -> bool:
	check(not picker.disabled, "Idle rule selector is enabled")
	await click(picker.get_global_rect().get_center())
	var popup := picker.get_popup()
	check(popup.visible, "Actual selector click opens its menu")
	if not popup.visible: return false
	# Route actual key events to the opened menu, without selecting a resource
	# or emitting its signal from the test. Read its actual focus after each key.
	for _step in picker.item_count + 1:
		if popup.get_focused_item() == index: break
		await menu_key(popup, KEY_DOWN)
	check(popup.get_focused_item() == index, "Menu keyboard navigation reaches the requested row")
	await menu_key(popup, KEY_ENTER)
	await frames()
	check(not popup.visible and picker.selected == index, "Menu input selects the requested example")
	if popup.visible or picker.selected != index: return false
	check(screen.ingredient_policy == preview.POLICIES[index], "Selected example reaches the real target policy")
	check(kettle.volume_ml == 0 and kettle.get_ingredient_amounts().is_empty()
		and cup.volume_ml == 0 and cup.get_ingredient_amounts().is_empty(), "Changing examples empties both vessel fixtures")
	check(stock.quantities == initial_stock and stock == preview.portion_stock,
		"Example reset restores supplies through the same inventory authority")
	check(controller.current_mode == InteractionController.MODE_NEUTRAL, "Example reset returns to Neutral")
	return true


func menu_key(popup: PopupMenu, key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.window_id = maxi(0, popup.get_window_id())
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func prepare_water(degrees: float) -> void:
	check(kettle.add_water(500) == 500, "Fixture adds one measured batch")
	kettle.temperature = degrees
	await tap(KEY_U)
	check(controller.current_mode == InteractionController.MODE_USE, "Actual mode key enables physical sources")


func check_source_access() -> void:
	var panel := preview.get_node("PreviewUI/Root/Panel") as Control
	check(root.get_visible_rect().encloses(panel.get_global_rect()), "Sandbox controls fit this viewport")
	for id: StringName in [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]:
		var source := source_for(id)
		check(source != null and not panel.get_global_rect().has_point(point(source.source_owner)),
			"Sandbox panel leaves %s source reachable" % id)
	for target: Node2D in [kettle.grip_anchor, screen.get_node("WorldRoot/ToolLayer/WaterDrum")]:
		check(not panel.get_global_rect().has_point(point(target)), "Sandbox panel leaves brewing utilities reachable")
	for dial_name in ["DialA", "DialB"]:
		var dial := preview.stove.get_node(dial_name) as Node2D
		if dial.is_visible_in_tree():
			check(not panel.get_global_rect().has_point(point(dial)), "Sandbox panel leaves active stove dials reachable")


func check_five_and_zero() -> void:
	if not await select_example(1): return
	await prepare_water(kettle.config.boiling_temperature)
	var before := stock.remaining(&"black_tea")
	for index in 5:
		await drop(&"black_tea", kettle, true)
		check(kettle.get_infused_counts().get(&"black_tea", 0) == index + 1,
			"Each physical bag increments the selected five-bag batch")
	await drop(&"black_tea", kettle, false)
	check(kettle.get_infused_counts().get(&"black_tea", 0) == 5 and stock.remaining(&"black_tea") == before - 5,
		"Sixth physical bag is rejected without losing stock or changing the five counted bags")
	await capture("five-teabags-active")
	if await pickup(&"sugar"):
		check(picker.disabled, "Holding a portion disables example switching")
		await move_pointer(picker.get_global_rect().get_center(), true)
		await mouse(picker.get_global_rect().get_center(), false)
		check(not picker.get_popup().visible and picker.selected == 1 and kettle.get_infused_counts().get(&"black_tea", 0) == 5,
			"Dropping onto the disabled selector cannot switch or reset the batch")
		check(stock.available(&"sugar") == stock.remaining(&"sugar"), "Cancelled selector drop releases its reservation")
	if not await select_example(2): return
	await prepare_water(kettle.config.boiling_temperature)
	await drop(&"black_tea", kettle, false)
	check(not kettle.contains_tea and kettle.get_ingredient_amounts().is_empty()
		and kettle.brewed_liquid_id.is_empty(), "Zero-bag example leaves plain water unbrewed")


func check_mixing_example() -> void:
	if not await select_example(3): return
	await prepare_water(20.0)
	await drop(&"sugar", kettle, false)
	await drop(&"black_tea", kettle, true)
	check(kettle.state == Kettle.BrewState.STEEPING and kettle.temperature == 20,
		"Selected data permits a cool infusion through the physical source")
	await drop(&"sugar", kettle, true)
	await drop(&"condensed_milk", kettle, false)
	check(kettle.get_mixed_amounts() == {&"sugar": 1.0}, "Steeping allows sugar while rejecting milk")
	kettle.advance_brewing(kettle.config.steep_seconds)
	await drop(&"condensed_milk", kettle, true)
	check(kettle.get_mixed_amounts() == {&"sugar": 1.0, &"condensed_milk": 1.0}
		and kettle.volume_ml == 500 and kettle.temperature == 20, "Ready-stage milk is counted without changing liquid volume or heat")
	await tap(KEY_U)
	await tap(KEY_K)
	await settle()
	returned_to(true)
	await drop(&"sugar", kettle, true, true)
	check(kettle.get_mixed_amounts().get(&"sugar", 0.0) == 2.0
		and modal.inventory_page.item_display(&"sugar").remaining == stock.remaining(&"sugar"),
		"Pantry uses the selected kettle rule and displays the same consumed stock")
	returned_to(true)
	await tap(KEY_K)
	await settle()
	check_source_access()
	await capture("mixing-example-active")
	if not await select_example(0): return
	check(screen.ingredient_policy.resource_path == "res://data/balance/ingredient_policy.tres"
		and screen.ingredient_policy.rule_for(&"black_tea", kettle).max_portions == 1,
		"Returning to current defaults preserves the shipped one-bag rule")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Designer rule input checks need a rendered window.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	check(root.get_node("GameState").reset_demo_state(), "Sandbox review initializes the actual inventory")
	stock = root.get_node("GameState").inventory
	initial_stock = stock.quantities
	preview = load("res://scenes/development/IngredientRulesPreview.tscn").instantiate()
	root.add_child(preview)
	await frames(4)
	screen = preview.screen
	controller = preview.controller
	modal = screen.khata_modal
	modal.book.sound_enabled = false
	picker = preview.policy_picker
	cup = screen.get_cups()[0]
	kettle = preview.kettle
	# Deterministic stages do not replace any picker, source or target gesture.
	kettle.set_process(false)
	for vessel: Cup in screen.get_cups(): vessel.set_process(false)
	for burner in preview.stove.burners: burner.set_process(false)
	check_source_access()
	await capture("sandbox-initial")
	await check_five_and_zero()
	await check_mixing_example()
	preview.queue_free()
	await frames()
	for id: StringName in [&"black_tea", &"sugar", &"condensed_milk"]:
		check(stock.available(id) == stock.remaining(id), "Sandbox teardown leaves no reservations")
	print("DESIGNER_INGREDIENT_RULES_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
