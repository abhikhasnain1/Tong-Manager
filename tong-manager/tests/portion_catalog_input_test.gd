extends "res://tests/khata_inventory_input_test.gd"
## Rendered authoring proof: temporary sixth item uses only existing data effects.

const EXTRA_ITEM := &"cardamom_test"
var receiver: Cup


func click_group(direction: int, expected_index: int) -> void:
	var rect: Rect2 = modal.inventory_navigation_screen_rect(direction)
	check(rect.has_area() and root.get_visible_rect().encloses(rect), "Additional-item navigation is reachable inside the rendered notebook")
	await click(rect.get_center())
	check(modal.inventory_page.item_page_index == expected_index and book.spread == 0 and not book.busy,
		"Actual in-page arrow changes only the pantry group, not the shared book spread")


func use_extra(peeking: bool, expected_amount: float) -> void:
	var before := stock.remaining(EXTRA_ITEM)
	await mouse(item_point(EXTRA_ITEM), true)
	check(controller.is_dragging() and modal.exporting and controller.current_payload.item_id == EXTRA_ITEM
		and controller.current_payload.metadata.unit == &"piece", "Actual sixth-cell press carries its configured item and unit")
	if not controller.is_dragging():
		await mouse(Vector2(5, 5), false)
		return
	check(stock.remaining(EXTRA_ITEM) == before and stock.available(EXTRA_ITEM) == before - 1,
		"New catalog item reserves without immediate consumption")
	var zone := receiver.get_node("IngredientTarget") as DropZone
	await move_pointer(point(zone), true)
	check(controller.hovered_drop_zone == zone and zone.accepts(controller.current_payload).is_valid,
		"Copied data rule authorizes the new item at the real cup")
	await mouse(point(zone), false)
	check(stock.remaining(EXTRA_ITEM) == before - 1 and stock.available(EXTRA_ITEM) == before - 1
		and is_equal_approx(receiver.get_ingredient_amounts().get(EXTRA_ITEM, 0.0), expected_amount),
		"Actual drop applies the new configured effect and debits shared stock once")
	check(modal.inventory_page.item_page_index == 1 and modal.inventory_page.item_display(EXTRA_ITEM).remaining == before - 1,
		"Successful drop refreshes stock while retaining the extra-item group")
	return_to_view(peeking, "Configured new-item drop")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("portion_catalog_input_test.gd requires a rendered window; use portion_catalog_test.gd headlessly.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	var catalog := root.get_node("Catalog")
	var item := ItemDef.new()
	item.id = EXTRA_ITEM
	item.unit = &"piece"
	item.portion_label = "Cardamom"
	item.pantry_enabled = true
	item.pantry_order = 50
	item.portion_color = Color("73a77c")
	item.icon = (catalog.get_item(&"sugar") as ItemDef).icon
	catalog.items[EXTRA_ITEM] = item
	var config := load("res://data/balance/demo_day_1.tres").duplicate(true) as Resource
	config.starting_inventory[EXTRA_ITEM] = 6
	check(root.get_node("GameState").reset_demo_state(config), "Temporary catalog item initializes through actual DayConfig stock")
	stock = root.get_node("GameState").inventory
	var layout := (load("res://data/balance/portion_sources_level_1.tres") as PortionSourceLayout).duplicate(true) as PortionSourceLayout
	layout.physical_sources[1].item_id = EXTRA_ITEM
	var policy := (load("res://data/balance/ingredient_policy.tres") as IngredientPolicy).duplicate(true) as IngredientPolicy
	var new_rule: IngredientRule
	for rule in policy.rules:
		if rule.item_id == &"sugar" and rule.vessel_kind == "cup":
			new_rule = rule.duplicate(true) as IngredientRule
	check(new_rule != null, "Existing cup-mix rule is available for a data-only new ingredient")
	if new_rule == null:
		quit(1)
		return
	new_rule.item_id = EXTRA_ITEM
	new_rule.unit = &"piece"
	policy.rules.append(new_rule)
	check(policy.configuration_errors().is_empty(), "Copied data rule remains valid without a new coded effect")
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	screen.source_layout = layout
	screen.ingredient_policy = policy
	root.add_child(screen)
	await frames(4)
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	receiver = screen.get_cups()[0]
	receiver.set_process(false)
	check(receiver.receive_liquid(&"black_tea", receiver.capacity_ml, 65) == receiver.capacity_ml,
		"Fixture fills a real cup to test an additional configured piece mix")
	await tap(KEY_U)
	var source: IngredientPortionSource
	for candidate: IngredientPortionSource in screen.portion_sources:
		if candidate.item_id == EXTRA_ITEM: source = candidate
	check(source != null, "Authored physical binding discovers the extra item")
	if source != null:
		await move_pointer(Vector2(5, 5))
		await move_pointer(point(source.source_owner))
		check(controller.current_hint.contains("cardamom") and not controller.current_hint.contains("sugar"),
			"Real physical hover names the configured item instead of its reused artwork")
		await mouse(point(source.source_owner), true)
		check(controller.is_dragging() and controller.current_payload.item_id == EXTRA_ITEM
			and controller.current_payload.source == &"physical_source" and controller.current_payload.metadata.unit == &"piece",
			"Real physical click carries the configured identity, origin and unit")
		# Drag hints describe the current target or empty space; the source label
		# belongs to hover and must not be asserted after target feedback begins.
		var visual := controller.current_drag_node as IngredientPortionVisual
		check(visual != null and visual.item_id == EXTRA_ITEM and visual.definition.get_portion_label() == "Cardamom",
			"Held piece keeps the configured visual label after drag-target feedback replaces the hover hint")
		await tap(KEY_ESCAPE)
		await mouse(point(source.source_owner), false)
		check(stock.remaining(EXTRA_ITEM) == 6 and stock.available(EXTRA_ITEM) == 6,
			"Cancelled new physical portion is returned without a debit")
	await tap(KEY_U)
	await tap(KEY_K)
	await settle()
	check(modal.is_peeking() and not modal.inventory_item_screen_rect(EXTRA_ITEM).has_area(),
		"Accepted five-item layout remains the initial Peek group")
	await click_group(1, 1)
	await capture("sixth-item-peek")
	await use_extra(true, 1.0)
	await click((modal.peek.get_node("OpenButton") as Control).get_global_rect().get_center())
	await settle()
	check(modal.inventory_page.item_page_index == 1, "Unfolding preserves the same added-item group")
	await capture("sixth-item-full")
	await use_extra(false, 2.0)
	await click_group(1, 1)
	await click_group(-1, 0)
	check(modal.inventory_item_screen_rect(&"black_tea").has_area()
		and not modal.inventory_item_screen_rect(EXTRA_ITEM).has_area(), "Real Previous arrow restores the original grid without an invisible sixth-cell hit box")
	await click_group(1, 1)
	var before := stock.remaining(EXTRA_ITEM)
	await mouse(item_point(EXTRA_ITEM), true)
	await tap(KEY_ESCAPE)
	await mouse(point(receiver.get_node("IngredientTarget")), false)
	check(stock.available(EXTRA_ITEM) == before and receiver.get_ingredient_amounts().get(EXTRA_ITEM) == 2.0,
		"Cancel and late release preserve the new item's stock and mixture")
	return_to_view(false, "Configured new-item cancel")
	await tap(KEY_K)
	await settle()
	screen.queue_free()
	await frames()
	catalog.items.erase(EXTRA_ITEM)
	check(root.get_node("GameState").reset_demo_state(), "Temporary new-item fixture leaves no shipped stock changes")
	print("PORTION_CATALOG_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
