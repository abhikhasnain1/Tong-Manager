extends SceneTree
## Real rendered input against shared-stock pantry UI; target acceptance is a contract fixture.

class ContractTarget extends DropZone:
	var controller: InteractionController
	var applied := 0
	func _init() -> void:
		var marker := Sprite2D.new()
		marker.name = "DebugPreview"
		marker.hide()
		add_child(marker)
		snap_radius = 35.0
	func is_relevant_to(payload: HeldItemPayload) -> bool:
		return payload != null and payload.metadata.get("portion") is IngredientPortion
	func accepts(payload: HeldItemPayload) -> DropValidation:
		if not is_relevant_to(payload) or not controller.can_address_drop_zone(payload, self):
			return DropValidation.invalid("Unavailable contract target")
		return DropValidation.valid() if (payload.metadata.portion as IngredientPortion).is_available() else DropValidation.invalid("Expired portion")
	func try_apply_drop(payload: HeldItemPayload) -> bool:
		return accepts(payload).is_valid and (payload.metadata.portion as IngredientPortion).commit(_apply)
	func _apply() -> bool:
		applied += 1
		return true

const ITEMS := [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: Control
var book: Node2D
var stock: InventoryState
var target: ContractTarget
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
	while (book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not book.busy and not modal.is_traveling(), "Notebook motion settles")
	await frames()


func move_pointer(to: Vector2, held := false) -> void:
	var from := root.get_mouse_position()
	root.warp_mouse(to)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = to - from
	event.velocity = event.relative * 60
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


func item_point(id: StringName) -> Vector2:
	var rect: Rect2 = modal.inventory_item_screen_rect(id)
	check(rect.has_area() and root.get_visible_rect().encloses(rect), "%s item is visible and reachable at this viewport" % id)
	return rect.get_center()


func capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Saved " + name)


func return_to_view(peeking: bool, label: String) -> void:
	check(not controller.is_dragging() and not modal.exporting and not controller.is_modal_export_active(), "%s finishes the exact pantry gesture" % label)
	check(modal.is_peeking() == peeking and modal.is_open() != peeking and controller.is_world_input_blocked() != peeking, "%s returns to its originating input/view state" % label)
	check(modal.page_index == 0 and book.get_visible_page_index() == 1, "%s keeps the selected shared pantry page" % label)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s restores the cursor" % label)


func check_view(peeking: bool) -> void:
	if peeking:
		await tap(KEY_K)
	else:
		await click((modal.peek.get_node("OpenButton") as Control).get_global_rect().get_center())
	await settle()
	check(modal.is_peeking() == peeking and modal.is_open() != peeking, "Real input opens the requested pantry view")
	var identity: int = modal.inventory_page.get_instance_id()
	await capture("pantry-peek" if peeking else "pantry-full")
	for id: StringName in ITEMS:
		var before := stock.remaining(id)
		var applied := target.applied
		await mouse(item_point(id), true)
		check(controller.is_dragging() and modal.exporting and controller.current_payload.source == &"khata", "%s cell press picks up its pantry portion" % id)
		if not controller.is_dragging():
			await mouse(Vector2(5, 5), false)
			continue
		check(controller.current_payload.item_id == id and stock.remaining(id) == before and stock.available(id) == before - 1, "Actual item input reserves one matching unit without a debit")
		await move_pointer(point(target), true)
		check(controller.hovered_drop_zone == target and target.debug_preview.visible, "Actual pointer motion finds its permitted target")
		if id == &"sugar": await capture("held-peek-spoon" if peeking else "held-full-spoon")
		await mouse(point(target), false)
		check(target.applied == applied + 1 and stock.remaining(id) == before - 1 and stock.available(id) == before - 1, "Actual release applies and debits once")
		check(modal.inventory_page.item_display(id).remaining == before - 1, "Released quantity reaches the live pantry display")
		check(modal.inventory_page.get_instance_id() == identity, "Repeated grabs reuse one live inventory page")
		return_to_view(peeking, "%s success" % id)
	var before := stock.remaining(&"sugar")
	await mouse(item_point(&"sugar"), true)
	await move_pointer(Vector2(6, root.size.y - 6), true)
	await mouse(Vector2(6, root.size.y - 6), false)
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Invalid real release preserves shared stock")
	return_to_view(peeking, "Invalid release")
	await mouse(item_point(&"sugar"), true)
	await move_pointer(point(target), true)
	await tap(KEY_ESCAPE)
	await mouse(point(target), false)
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Escape cancels the held export before its later mouse release")
	return_to_view(peeking, "Escape cancellation")
	stock.set_quantity(&"sugar", 0)
	await click(item_point(&"sugar"))
	check(not controller.is_dragging() and stock.remaining(&"sugar") == 0 and not book.busy and book.spread == 0, "Depleted cell gives feedback without exporting or turning the page")
	await capture("empty-peek" if peeking else "empty-full")
	stock.set_quantity(&"sugar", before)
	await mouse(item_point(&"banana"), true)
	modal.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await mouse(point(target), false)
	return_to_view(peeking, "Focus interruption")
	await mouse(item_point(&"banana"), true)
	root.size_changed.emit()
	await mouse(point(target), false)
	return_to_view(peeking, "Resize interruption")
	check(stock.available(&"banana") == stock.remaining(&"banana"), "Interrupted pieces leave no reserved stock")
	# Inventory cells must not steal the paper's dedicated outer-edge navigation.
	var edge: Vector2 = book.get_global_transform_with_canvas() * (book._book_origin() + Vector2(460, 330))
	await click(edge)
	await settle()
	check(book.spread == 1 and not controller.is_dragging(), "Outside the item grid, the full-height page edge still turns")
	await click((modal.get_node("TabContainer/InventoryTab") as Control).get_global_rect().get_center())
	await settle()
	check(book.spread == 0 and modal.inventory_page.get_instance_id() == identity, "Bookmark returns to the unchanged shared-stock page")


func check_peek_mode_and_world() -> void:
	var before := stock.remaining(&"sugar")
	await mouse(item_point(&"sugar"), true)
	await tap(KEY_G)
	await mouse(point(target), false)
	check(modal.is_peeking() and controller.current_mode == InteractionController.MODE_ORGANIZE and stock.available(&"sugar") == before, "Mode key cancels Peek's own export but preserves Peek")
	await tap(KEY_U)
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var origin := kettle.global_transform
	await mouse(point(kettle.get_node("GripAnchor")), true)
	check(controller.is_dragging() and not modal.exporting, "An uncovered world kettle remains usable beside Peek")
	await tap(KEY_K)
	await settle()
	check(controller.is_dragging() and not modal.is_peeking() and not controller.is_world_input_blocked(), "K closes only Peek while preserving an independently held kettle")
	await tap(KEY_ESCAPE)
	await mouse(point(kettle.get_node("GripAnchor")), false)
	check(not controller.is_dragging() and kettle.global_transform.is_equal_approx(origin), "World cancel still restores the kettle after Peek closes")
	await tap(KEY_K)
	await settle()
	check(modal.is_peeking(), "K can reopen the same populated Peek")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Khata inventory input checks need a rendered window; use khata_inventory_test.gd headless.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	check(root.get_node("GameState").reset_demo_state(), "Rendered test initializes the production stock authority")
	stock = root.get_node("GameState").inventory
	for id: StringName in ITEMS: stock.set_quantity(id, 8)
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames(4)
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	target = ContractTarget.new()
	target.controller = controller
	target.position = Vector2(root.size.x * 0.18, root.size.y * 0.76)
	screen.add_child(target)
	controller.register_drop_zone(target)
	var allowed: Array[DropZone] = [target]
	# Keep this contract fixture alongside the scene's live vessel targets. Kettle
	# dragging refreshes that list as its target exits and returns to the stall.
	screen.set_extra_portion_targets(allowed)
	await check_view(true)
	await check_peek_mode_and_world()
	await check_view(false)
	await mouse(item_point(&"sugar"), true)
	await tap(KEY_G)
	await mouse(point(target), false)
	await settle()
	check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked(), "Full export retains its accepted mode-change close behavior")
	check(stock.available(&"sugar") == stock.remaining(&"sugar"), "Full close returns the unused reservation")
	screen.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Rendered teardown leaves the pointer visible")
	print("KHATA_INVENTORY_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
