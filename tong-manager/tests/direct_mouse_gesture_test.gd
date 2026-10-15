extends SceneTree
## Deterministic button-event routing through the real controller and adapters.
## Native friend-demo checks additionally verify physics/GUI event delivery.

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func button(index: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = position
	controller._input(event)
	return event

func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin

func move_cup(cup: Cup) -> Vector2:
	var location := point(cup)
	var event := button(MOUSE_BUTTON_RIGHT, true, location)
	cup._on_input(root, event, 0)
	cup.get_node("PlacementHandle")._on_input_event(root, event, 0)
	return location

func settle_book(modal: KhataModal) -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while (modal.book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not modal.book.busy and not modal.is_traveling(), "Notebook settles")

func run() -> void:
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	screen.customer_queue_auto_start = false
	controller = screen.get_node("InteractionController") as InteractionController
	root.add_child(screen)
	await process_frame
	controller.set_process(false)
	check(not controller.direct_mouse_gestures and controller.current_mode == InteractionController.MODE_NEUTRAL,
		"Ordinary scenes retain neutral and explicit modes by default")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Legacy Organize remains available outside direct mode")
	controller.configure_direct_mouse_gestures(true)
	check(controller.current_mode == InteractionController.MODE_INTERACT, "Opt-in begins directly in Use")
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	controller.select_mode(InteractionController.MODE_ORGANIZE)
	check(controller.current_mode == InteractionController.MODE_INTERACT, "Demo has no toggle into neutral or a persistent organize mode")
	var tray: TrayStation = screen.get_node("WorldRoot/ToolLayer/TrayStation")
	var cup: Cup = tray.get_cups()[0]
	var handle: TablePlaceable = cup.get_node("PlacementHandle")
	var original: Transform2D = cup.transform
	var original_parent := cup.get_parent()
	var location := move_cup(cup)
	check(controller.current_drag_node == cup and controller.is_move_drag()
		and controller.current_payload.source == &"table_surface", "Right cup press starts placement, not serving")
	var move_payload := controller.current_payload
	button(MOUSE_BUTTON_LEFT, true, location)
	button(MOUSE_BUTTON_LEFT, false, Vector2(-1000, -1000))
	check(controller.current_payload == move_payload and controller.is_dragging(), "Opposite left press/release cannot finish a right move")
	button(MOUSE_BUTTON_RIGHT, false, Vector2(-1000, -1000))
	check(not controller.is_dragging() and cup.get_parent() == original_parent and cup.transform == original,
		"Only the initiating right release resolves and rolls back invalid placement exactly")
	check(controller.current_mode == InteractionController.MODE_INTERACT, "Right completion restores direct Use")
	location = move_cup(cup)
	var destination: Vector2 = screen.get_node("WorldRoot").get_global_transform_with_canvas() * Vector2(860, 900)
	var pointer := location + destination - point(cup)
	button(MOUSE_BUTTON_RIGHT, false, pointer)
	check(handle.surface == screen.table_surface and handle.surface.is_registered(cup), "Right release can commit the same cup from tray to table")
	check(cup.receive_liquid(&"black_tea", 60.0, 65.0) == 60.0, "Fixture gives the moved cup contents")
	var discard: DiscardDropZone = screen.get_node("WorldRoot/DropZoneRoot/DiscardArea")
	location = move_cup(cup)
	check(not controller.can_address_drop_zone(controller.current_payload, discard), "Right move cannot address the discard action")
	button(MOUSE_BUTTON_RIGHT, false, point(discard))
	check(cup.volume_ml == 60.0, "Moving over the wastebasket does not empty a cup")
	location = point(cup)
	var left := button(MOUSE_BUTTON_LEFT, true, location)
	cup._on_input(root, left, 0)
	check(controller.current_payload != null and controller.current_payload.source == &"cup" and not controller.is_move_drag(),
		"Left cup press retains the existing use/service payload")
	button(MOUSE_BUTTON_RIGHT, true, location)
	button(MOUSE_BUTTON_RIGHT, false, point(discard))
	check(controller.current_drag_node == cup and cup.volume_ml == 60.0, "Opposite right release cannot resolve a left use gesture")
	button(MOUSE_BUTTON_LEFT, false, point(discard))
	check(not controller.is_dragging() and cup.volume_ml == 0.0, "Left release still deliberately discards contents and keeps the cup")

	var source: IngredientPortionSource
	for candidate: IngredientPortionSource in screen.portion_sources:
		if candidate.item_id == &"sugar":
			source = candidate
			break
	var stock: InventoryState = root.get_node("GameState").inventory
	var quantity := stock.remaining(&"sugar")
	location = point(source.source_owner)
	var right := button(MOUSE_BUTTON_RIGHT, true, location)
	source._on_input(root, right, 0)
	source.placement_handle._on_input_event(root, right, 0)
	check(controller.current_drag_node == source.source_owner and stock.available(&"sugar") == quantity,
		"Right container press moves its source without reserving an ingredient")
	controller.cancel_drag()
	button(MOUSE_BUTTON_RIGHT, false, location)
	left = button(MOUSE_BUTTON_LEFT, true, location)
	source._on_input(root, left, 0)
	var portion_payload := controller.current_payload
	check(controller.is_portion_drag() and stock.available(&"sugar") == quantity - 1,
		"Left source press extracts one reserved portion")
	button(MOUSE_BUTTON_RIGHT, true, location)
	button(MOUSE_BUTTON_RIGHT, false, location)
	check(controller.current_payload == portion_payload, "Right crossing cannot steal a held physical portion")
	button(MOUSE_BUTTON_LEFT, false, Vector2(-1000, -1000))
	check(stock.remaining(&"sugar") == quantity and stock.available(&"sugar") == quantity, "Invalid left portion release restores its reservation")

	var kettle: Kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	var kettle_origin := kettle.transform
	var kettle_parent := kettle.get_parent()
	kettle.discard_contents()
	kettle.add_water(200.0)
	location = point(kettle.grip_anchor)
	right = button(MOUSE_BUTTON_RIGHT, true, location)
	kettle._on_input(root, right, 0)
	check(controller.current_drag_node == kettle and controller.is_move_drag(), "Right kettle press begins burner movement")
	check(not controller.can_address_drop_zone(controller.current_payload, cup.get_node("PourTarget"))
		and not controller.can_address_drop_zone(controller.current_payload, discard), "Right kettle cannot address cup pouring or discard")
	kettle.update_held_pour(true)
	check(not kettle.is_pouring and kettle.volume_ml == 200.0, "Holding pour during a right move transfers no liquid")
	button(MOUSE_BUTTON_RIGHT, false, Vector2(-1000, -1000))
	check(kettle.get_parent() == kettle_parent and kettle.transform == kettle_origin and not kettle.is_held,
		"Invalid right kettle drop restores its exact seat pose")
	location = point(kettle.grip_anchor)
	right = button(MOUSE_BUTTON_RIGHT, true, location)
	kettle._on_input(root, right, 0)
	var burner: Burner = screen.get_node("WorldRoot/ToolLayer/StoveStation/BurnerA")
	button(MOUSE_BUTTON_RIGHT, false, point(burner.get_node("DropZone")))
	check(not controller.is_dragging() and kettle.current_burner == burner and burner.seated_kettle == kettle and not kettle.is_held,
		"Right kettle release can reseat on an authorized burner")

	location = move_cup(cup)
	var cancel := InputEventAction.new()
	cancel.action = InteractionController.INPUT_CANCEL
	cancel.pressed = true
	controller._input(cancel)
	check(not controller.is_dragging() and controller.current_mode == InteractionController.MODE_INTERACT, "Esc cancels a right move and restores idle Use")
	button(MOUSE_BUTTON_RIGHT, false, location)
	location = move_cup(cup)
	controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not controller.is_dragging() and controller.current_mode == InteractionController.MODE_INTERACT, "Focus loss cancels direct movement")
	button(MOUSE_BUTTON_RIGHT, false, location)
	var modal: KhataModal = screen.khata_modal
	modal.open_peek()
	await settle_book(modal)
	location = modal.inventory_item_screen_rect(&"sugar").get_center()
	button(MOUSE_BUTTON_LEFT, true, location)
	check(modal.begin_inventory_export(&"sugar", location), "Left pantry use remains available in direct mode")
	var pantry_payload := controller.current_payload
	right = button(MOUSE_BUTTON_RIGHT, true, location)
	modal._input(right)
	modal._input(button(MOUSE_BUTTON_RIGHT, false, location))
	check(modal.exporting and controller.current_payload == pantry_payload, "Right crossing does not cancel or replace a left pantry export")
	button(MOUSE_BUTTON_LEFT, false, Vector2(-1000, -1000))
	check(not modal.exporting and modal.is_peeking() and stock.remaining(&"sugar") == quantity
		and controller.current_mode == InteractionController.MODE_INTERACT, "Canceled pantry export restores its view, stock and direct Use")
	modal.close_peek()
	await settle_book(modal)
	controller.configure_direct_mouse_gestures(false)
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(controller.current_mode == InteractionController.MODE_NEUTRAL, "Disabling the opt-in restores ordinary mode semantics")
	screen.queue_free()
	await process_frame
	print("DIRECT_MOUSE_GESTURES: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
