extends SceneTree
## Temporary data proves new supported-unit items need no source or pantry ID list.

const DEFAULT_IDS: Array[StringName] = [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]
const EXTRA_ID := &"cardamom_test"
const PIECE_ID := &"pastry_test"
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var catalog: Node
var state: Node
var modal: KhataModal
var controller: InteractionController


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
	check(not modal.book.busy and not modal.is_traveling(), "Notebook movement settles")
	await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func item_ids(entries: Array[ItemDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in entries: ids.append(entry.id)
	return ids


func make_item(id: StringName, unit: StringName, order: int) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.unit = unit
	item.pantry_enabled = true
	item.pantry_order = order
	return item


func check_default_data() -> void:
	check(item_ids(catalog.get_pantry_items()) == DEFAULT_IDS, "Only the accepted five items are enabled by default, in their accepted order")
	var labels := ["Tea", "Sugar", "Milk", "Banana", "Biscuit"]
	var units := [&"teabag", &"spoonful", &"spoonful", &"piece", &"piece"]
	for index in DEFAULT_IDS.size():
		var item := catalog.get_portion_item(DEFAULT_IDS[index]) as ItemDef
		check(item != null and item.get_portion_label() == labels[index] and item.unit == units[index] and item.icon != null,
			"Accepted item label, unit and art come from its resource")
	check(not (catalog.get_item(&"ginger") as ItemDef).pantry_enabled
		and not (catalog.get_item(&"lemon") as ItemDef).pantry_enabled
		and not (catalog.get_item(&"honey") as ItemDef).pantry_enabled,
		"Existing unsupported pantry entries are not silently enabled")
	var empty := ItemDef.new()
	check(not empty.supports_portions() and not empty.pantry_enabled, "Inspector-created ItemDef defaults introduce no new item")
	var water := catalog.get_portion_item(&"water") as ItemDef
	check(water == null, "Measured water remains outside integer portion presentation")
	var layout := load("res://data/balance/portion_sources_level_1.tres") as PortionSourceLayout
	check(layout.physical_sources.size() == 4 and layout.hanging_sources.size() == 3, "Authored source layout retains four containers and three hanging regions")
	check(layout.physical_sources[1].item_id == &"sugar" and layout.physical_sources[2].item_id == &"sugar",
		"Both sugar pictures retain a shared item identity")
	check(layout.hanging_sources[0].item_id == &"banana" and layout.hanging_sources[1].item_id == &"banana"
		and layout.hanging_sources[0].region == Rect2(0, 0, 192, 367)
		and layout.hanging_sources[1].region == Rect2(192, 0, 120, 367)
		and layout.hanging_sources[2].region == Rect2(0, 0, 398, 686),
		"Hanging resource preserves both shared banana regions and biscuit artwork")
	check(layout.hanging_sources[0].pivot == Vector2(76, 0)
		and layout.hanging_sources[1].pivot == Vector2(249, 51)
		and layout.hanging_sources[2].pivot == Vector2(245, 12), "Authored hanging pivots are unchanged")


func check_pagination_page() -> void:
	var page := KhataInventoryPage.new()
	page.configure(1, null)
	page.bind_inventory(state.inventory)
	root.add_child(page)
	await frames()
	check(page.page_count == 2 and page.item_page_index == 0, "Additional catalog items create a second bounded pantry group")
	for id in DEFAULT_IDS:
		check(page.item_at(page.item_rect(id).get_center()) == id, "Original first-page item is still hit-testable")
	check(page.item_rect(&"black_tea").position.is_equal_approx(Vector2(44, 170))
		and page.item_rect(&"banana").position.is_equal_approx(Vector2(44, 342)),
		"Default three-plus-two grid retains its original authored positions")
	check(not page.item_rect(EXTRA_ID).has_area() and not page.change_item_page(-1), "Off-page item has no invisible input rectangle and first page cannot go backward")
	var next_rect := page.navigation_rect(1)
	check(next_rect.has_area() and Rect2(0, 0, 480, 660).encloses(next_rect)
		and page.navigation_at(next_rect.get_center()) == 1, "Extra-group navigation remains inside the notebook paper")
	check(page.change_item_page(1) and page.item_page_index == 1 and not page.change_item_page(1), "Next group advances once and cannot overflow")
	for id in [EXTRA_ID, PIECE_ID]:
		check(page.item_rect(id).has_area() and KhataInventoryPage.GRID_RECT.encloses(page.item_rect(id))
			and page.item_at(page.item_rect(id).get_center()) == id, "Additional configured item fits the existing grid and responds at its displayed location")
		var display := page.item_display(id)
		check(display.remaining == 3 and display.available == 3 and display.unit == state.inventory.get_unit(id),
			"New item displays authoritative stock and its configured unit")
	check(not page.item_rect(&"black_tea").has_area(), "Previously visible first-group cell cannot be clicked through the second group")
	page.set_interaction_enabled(false)
	check(not page.change_item_page(-1) and page.navigation_at(next_rect.get_center()) == 0
		and page.item_at(page.item_rect(EXTRA_ID).get_center()).is_empty(), "Gesture ownership disables both new navigation and item hit tests")
	page.set_interaction_enabled(true)
	check(page.change_item_page(-1), "Returning to the accepted first group works")
	page.queue_free()
	await frames()


func check_source_binding() -> void:
	var layout := (load("res://data/balance/portion_sources_level_1.tres") as PortionSourceLayout).duplicate(true) as PortionSourceLayout
	layout.physical_sources[1].item_id = EXTRA_ID
	layout.hanging_sources[2].item_id = PIECE_ID
	var policy := (load("res://data/balance/ingredient_policy.tres") as IngredientPolicy).duplicate(true) as IngredientPolicy
	for rule in policy.rules.duplicate():
		if rule.item_id == &"sugar" and rule.vessel_kind == "cup":
			var piece_rule := rule.duplicate(true) as IngredientRule
			piece_rule.item_id = PIECE_ID
			piece_rule.unit = &"piece"
			policy.rules.append(piece_rule)
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	screen.source_layout = layout
	screen.ingredient_policy = policy
	root.add_child(screen)
	await frames()
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	modal.book.sound_enabled = false
	var source: IngredientPortionSource
	for candidate: IngredientPortionSource in screen.portion_sources:
		if candidate.item_id == EXTRA_ID: source = candidate
	check(source != null and source.source_owner.name == "SugarCan" and source.unit == &"spoonful"
		and source.provider == state.inventory, "A data-only binding assigns the existing physical artwork to a new catalog item and unit")
	controller.set_mode(InteractionController.MODE_USE)
	if source != null:
		var before: int = state.inventory.remaining(EXTRA_ID)
		check(source.begin_portion(point(source.source_owner)), "Configured physical source can reserve its new item")
		check(controller.current_payload != null and controller.current_payload.item_id == EXTRA_ID
			and controller.current_payload.metadata.unit == &"spoonful", "Physical payload uses data-defined identity and unit")
		check(controller.current_hint.contains("cardamom") and not controller.current_hint.contains("sugar"), "Physical hint names the configured ingredient instead of its reused artwork")
		var visual := controller.current_drag_node as IngredientPortionVisual
		check(visual != null and visual.presentation_style() == "spoon"
			and visual.definition.portion_color == Color("73a77c"), "Transient spoon uses the configured presentation color")
		controller.cancel_drag()
		check(state.inventory.remaining(EXTRA_ID) == before and state.inventory.available(EXTRA_ID) == before,
			"New-item physical cancellation has the same stock conservation")
	var piece := IngredientPortionVisual.new(PIECE_ID, &"piece")
	root.add_child(piece)
	check(piece.presentation_style() == "icon" and piece.definition.icon != null,
		"Unknown ready-item identity uses its configured icon instead of becoming a biscuit")
	piece.queue_free()
	var piece_source: IngredientPortionSource
	for candidate: IngredientPortionSource in screen.portion_sources:
		if candidate.item_id == PIECE_ID: piece_source = candidate
	var receiver: Cup = screen.get_cups()[0]
	var zone := receiver.get_node("IngredientTarget") as IngredientPortionTarget
	check(piece_source != null and piece_source.begin_portion(point(piece_source.source_owner)),
		"Data-defined piece ingredient can be extracted from a hanging source")
	check(controller.current_payload.metadata.category == &"ready_item" and zone.accepts(controller.current_payload).is_valid,
		"Canonical piece payload reaches its configured vessel rule despite ready-item presentation category")
	controller.release_drop(point(zone))
	check(receiver.get_ingredient_amounts().get(PIECE_ID) == 1.0 and state.inventory.remaining(PIECE_ID) == 2,
		"Physical piece mix applies once and debits the shared unit exactly once")
	controller.set_mode(InteractionController.MODE_NEUTRAL)


func navigate(direction: int) -> void:
	var rect := modal.inventory_navigation_screen_rect(direction)
	check(rect.has_area() and root.get_visible_rect().encloses(rect), "Mapped pantry group navigation is inside the current viewport")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = rect.get_center()
	check(modal._handle_inventory_input(event), "Notebook forwards group navigation to its actual rendered inventory page")
	await frames()


func check_modal_new_item() -> void:
	check(modal.open_peek(), "Normal notebook opens with the expanded data catalog")
	await settle()
	check(not modal.begin_inventory_export(EXTRA_ID, Vector2.ZERO), "Programmatic pickup cannot grab an item hidden on another pantry group")
	await navigate(1)
	check(modal.book.spread == 0 and modal.book.get_visible_page_index() == 1 and modal.is_peeking(), "In-page pagination changes neither book spread nor Peek ownership")
	var before: int = state.inventory.remaining(EXTRA_ID)
	var rect := modal.inventory_item_screen_rect(EXTRA_ID)
	check(rect.has_area() and root.get_visible_rect().encloses(rect), "Sixth configured item is visibly reachable in Peek")
	check(modal.begin_inventory_export(EXTRA_ID, rect.get_center()), "Sixth item exports from data without a central item list")
	check(controller.current_payload.item_id == EXTRA_ID and controller.current_payload.metadata.unit == &"spoonful"
		and state.inventory.remaining(EXTRA_ID) == before and state.inventory.available(EXTRA_ID) == before - 1,
		"New pantry item reserves the authoritative configured unit without consuming it")
	controller.cancel_drag()
	check(modal.is_peeking() and modal.inventory_page.item_page_index == 1
		and state.inventory.available(EXTRA_ID) == before, "Cancelling the new item restores its exact group and original view")
	var receiver: Cup = screen.get_cups()[0]
	var zone := receiver.get_node("IngredientTarget") as IngredientPortionTarget
	check(modal.begin_inventory_export(PIECE_ID, modal.inventory_item_screen_rect(PIECE_ID).get_center()),
		"Configured piece ingredient also exports from the extra pantry group")
	check(zone.accepts(controller.current_payload).is_valid, "Pantry piece payload reaches the same vessel rule")
	controller.release_drop(point(zone))
	check(receiver.get_ingredient_amounts().get(PIECE_ID) == 2.0 and state.inventory.remaining(PIECE_ID) == 1
		and state.inventory.available(PIECE_ID) == 1, "Pantry piece mix shares the physical count and exact-once debit")
	check(modal.open(), "Expanded catalog can unfold into Full")
	await settle()
	check(modal.inventory_page.item_page_index == 1 and modal.inventory_item_screen_rect(EXTRA_ID).has_area(),
		"Peek and Full share the same extra group selection and page identity")
	await navigate(-1)
	check(modal.inventory_page.item_page_index == 0 and modal.inventory_item_screen_rect(&"black_tea").has_area(),
		"Full returns to the original five-item layout through the same navigation")
	modal.close()
	await settle()


func run() -> void:
	root.size = Vector2i(1280, 800)
	catalog = root.get_node("Catalog")
	state = root.get_node("GameState")
	check_default_data()
	var extra := make_item(EXTRA_ID, &"spoonful", 50)
	extra.portion_label = "Cardamom"
	extra.portion_color = Color("73a77c")
	extra.icon = (catalog.get_item(&"sugar") as ItemDef).icon
	var piece := make_item(PIECE_ID, &"piece", 60)
	piece.portion_label = "Pastry"
	piece.icon = (catalog.get_item(&"biscuits") as ItemDef).icon
	catalog.items[EXTRA_ID] = extra
	catalog.items[PIECE_ID] = piece
	check(catalog.get_portion_item(EXTRA_ID) == extra and catalog.get_pantry_items().size() == 7, "Catalog discovers additional supported-unit resources")
	var invalid := make_item(&"unsupported_test", &"ml", 70)
	catalog.items[invalid.id] = invalid
	check(catalog.get_portion_item(invalid.id) == null and catalog.get_pantry_items().size() == 7,
		"Unsupported units cannot silently enter integer portion UI")
	catalog.items.erase(invalid.id)
	var config := load("res://data/balance/demo_day_1.tres").duplicate(true) as Resource
	config.starting_inventory[EXTRA_ID] = 3
	config.starting_inventory[PIECE_ID] = 3
	check(state.reset_demo_state(config) and state.inventory.get_unit(EXTRA_ID) == &"spoonful",
		"DayConfig quantities and Catalog units initialize new authoritative stock without InventoryState changes")
	await check_pagination_page()
	await check_source_binding()
	await check_modal_new_item()
	screen.queue_free()
	await frames()
	catalog.items.erase(EXTRA_ID)
	catalog.items.erase(PIECE_ID)
	check(item_ids(catalog.get_pantry_items()) == DEFAULT_IDS and state.reset_demo_state(), "Temporary test items leave no new default content")
	print("PORTION_CATALOG: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
