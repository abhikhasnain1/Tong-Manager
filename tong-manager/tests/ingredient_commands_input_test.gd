extends SceneTree
## Real player input in normal Tong; only heat/liquid preparation is a test fixture.

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: KhataModal
var stock: InventoryState
var cup: Cup
var kettle: Kettle
var capture_dir := ""


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for _index in count:
		await physics_frame
		await process_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while (modal.book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not modal.book.busy and not modal.is_traveling(), "Notebook motion settles")
	await frames()


func move_pointer(to: Vector2, held := false) -> void:
	var from := root.get_mouse_position()
	root.warp_mouse(to)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await frames()


func mouse(to: Vector2, pressed: bool) -> void:
	await move_pointer(to, pressed)
	var event := InputEventMouseButton.new()
	event.position = to
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await frames()


func click(to: Vector2) -> void:
	await mouse(to, true)
	await mouse(to, false)


func tap(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func target_point(vessel: Node2D) -> Vector2:
	return point(vessel.get_node("IngredientTarget"))


func source_for(id: StringName) -> IngredientPortionSource:
	for source in screen.portion_sources:
		if source.item_id == id: return source
	return null


func pickup(id: StringName, pantry := false) -> bool:
	var before := stock.remaining(id)
	var location: Vector2
	if pantry:
		var rect := modal.inventory_item_screen_rect(id)
		check(rect.has_area() and root.get_visible_rect().encloses(rect), "Pantry ingredient is reachable in this viewport")
		location = rect.get_center()
	else:
		var source := source_for(id)
		check(source != null and source.provider == stock, "Physical ingredient uses production inventory")
		if source == null: return false
		location = point(source.source_owner)
	await mouse(location, true)
	var active := controller.is_dragging() and controller.current_payload != null
	check(active, "%s %s press begins a real held portion" % ["Pantry" if pantry else "Physical", id])
	if not active:
		await mouse(location, false)
		return false
	check(controller.current_payload.item_id == id and controller.current_payload.quantity == 1
		and controller.current_payload.source == (&"khata" if pantry else &"physical_source"),
		"Input creates the correct one-unit portion from its actual source")
	check(stock.remaining(id) == before and stock.available(id) == before - 1,
		"Pickup reserves one unit without consuming it")
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Held portion has one visible drawn cursor")
	return true


func drop(id: StringName, vessel: Node2D, expected: bool, pantry := false) -> void:
	var before := stock.remaining(id)
	var ingredients := cup.get_relish_counts()
	var contains_tea := kettle.contains_tea
	if not await pickup(id, pantry): return
	var zone := vessel.get_node("IngredientTarget") as DropZone
	await move_pointer(target_point(vessel), true)
	check(controller.hovered_drop_zone == zone and zone.accepts(controller.current_payload).is_valid == expected,
		"Pointer selects the intended vessel and reports its production eligibility")
	await mouse(target_point(vessel), false)
	check(not controller.is_dragging() and stock.remaining(id) == before - (1 if expected else 0)
		and stock.available(id) == stock.remaining(id), "Release resolves once with the correct shared-stock effect")
	if not expected:
		check(cup.get_relish_counts() == ingredients and kettle.contains_tea == contains_tea,
			"Rejected release leaves both vessels unchanged")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Release restores the regular cursor")


func returned_to(peeking: bool) -> void:
	check(not modal.exporting and not controller.is_modal_export_active()
		and modal.is_peeking() == peeking and modal.is_open() != peeking,
		"Ingredient gesture returns to its original notebook view")
	check(controller.is_world_input_blocked() != peeking
		and controller.current_mode == InteractionController.MODE_NEUTRAL,
		"Notebook gesture restores its input ownership without changing world mode")


func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Saved " + name)


func check_physical_flow() -> void:
	await tap(KEY_U)
	check(controller.current_mode == InteractionController.MODE_USE, "Actual U key selects physical ingredient use")
	cup.reset_clean()
	await drop(&"sugar", cup, true)
	await drop(&"condensed_milk", cup, true)
	check(cup.volume_ml == 0 and cup.get_relish_counts() == {&"sugar": 1, &"condensed_milk": 1},
		"Actual sugar and milk spoons are retained in an empty cup")
	# Heat is prepared directly: this suite tests ingredient input, not the
	# independently covered kettle heating and hold-to-pour gestures.
	kettle.discard_contents()
	check(kettle.add_water(500) == 500, "Fixture prepares a measured kettle batch")
	kettle.temperature = kettle.config.boiling_temperature
	await drop(&"black_tea", kettle, true)
	check(kettle.contains_tea, "Real teabag release starts the prepared boiling batch")
	await drop(&"black_tea", kettle, false)
	await drop(&"sugar", kettle, false)
	await drop(&"black_tea", cup, false)
	check(cup.receive_liquid(&"black_tea", cup.capacity_ml, 65) == cup.capacity_ml,
		"Fixture fills the ingredient-first cup to capacity")
	check(cup.get_relish_counts() == {&"sugar": 1, &"condensed_milk": 1},
		"Filling tea preserves the spoons added before the base")
	await capture("ingredient-first-cup")
	await tap(KEY_U)
	check(controller.current_mode == InteractionController.MODE_NEUTRAL, "Notebook test begins in neutral")


func check_pantry_flow(peeking: bool) -> void:
	if peeking:
		await tap(KEY_K)
	else:
		await click((modal.peek.get_node("OpenButton") as Control).get_global_rect().get_center())
	await settle()
	returned_to(peeking)
	var expected_count := 2 if peeking else 3
	for id: StringName in [&"sugar", &"condensed_milk"]:
		await drop(id, cup, true, true)
		check(cup.get_relish_count(id) == expected_count and cup.volume_ml == cup.capacity_ml
			and cup.temperature == 65, "Real pantry spoon increments its dose in a full cup without volume or heat changes")
		check(modal.inventory_page.item_display(id).remaining == stock.remaining(id),
			"Successful production drop immediately updates the displayed stock")
		returned_to(peeking)
	check(cup.relish_item_ids.size() == expected_count * 2,
		"Fourth and subsequent spoonfuls remain counted without a legacy cap")
	await drop(&"black_tea", cup, false, true)
	returned_to(peeking)
	var before := stock.remaining(&"sugar")
	if await pickup(&"sugar", true):
		await mouse(Vector2(5, root.size.y - 5), false)
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before,
			"Pantry release outside every target consumes no stock")
		returned_to(peeking)
	if await pickup(&"sugar", true):
		await move_pointer(target_point(cup), true)
		await tap(KEY_ESCAPE)
		await mouse(target_point(cup), false)
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before
			and cup.get_relish_count(&"sugar") == expected_count,
			"Escape prevents both consumption and a later-release replay")
		returned_to(peeking)
	await capture("production-pantry-peek" if peeking else "production-pantry-full")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ingredient commands input checks need a rendered window; use ingredient_commands_test.gd headless.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	check(root.get_node("GameState").reset_demo_state(), "Input test initializes real production inventory")
	stock = root.get_node("GameState").inventory
	for id: StringName in [&"black_tea", &"sugar", &"condensed_milk"]: stock.set_quantity(id, 20)
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames(4)
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	modal.book.sound_enabled = false
	cup = screen.get_cups()[0]
	kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	kettle.set_process(false)
	for vessel: Cup in screen.get_cups(): vessel.set_process(false)
	for burner in screen.get_node("WorldRoot/ToolLayer/StoveStation").burners: burner.set_process(false)
	check(modal.inventory == stock, "Normal Tong shares one authority with physical sources and Khata")
	await check_physical_flow()
	await check_pantry_flow(true)
	await check_pantry_flow(false)
	await tap(KEY_K)
	await settle()
	check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked(),
		"K closes Full and returns normal world input")
	screen.queue_free()
	await frames()
	for id: StringName in [&"black_tea", &"sugar", &"condensed_milk"]:
		check(stock.available(id) == stock.remaining(id), "Teardown leaves no reserved ingredient")
	print("INGREDIENT_COMMANDS_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
