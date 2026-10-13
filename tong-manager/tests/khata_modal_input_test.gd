extends SceneTree
## Rendered viewport input for the production notebook shell, not pantry/export content.

class PeekTarget extends DropZone:
	var controller: InteractionController
	var applied := 0
	func _init() -> void:
		var preview := Sprite2D.new()
		preview.name = "DebugPreview"
		preview.hide()
		add_child(preview)
		snap_radius = 35
	func is_relevant_to(payload: HeldItemPayload) -> bool:
		return payload != null and payload.metadata.get("category") == &"ingredient_portion"
	func accepts(payload: HeldItemPayload) -> DropValidation:
		if not is_relevant_to(payload) or not controller.can_address_drop_zone(payload, self):
			return DropValidation.invalid("Inactive test target")
		var portion := payload.metadata.get("portion") as IngredientPortion
		return DropValidation.valid() if portion != null and portion.is_available() else DropValidation.invalid("Expired portion")
	func try_apply_drop(payload: HeldItemPayload) -> bool:
		return accepts(payload).is_valid and (payload.metadata.portion as IngredientPortion).commit(_apply)
	func _apply() -> bool:
		applied += 1
		return true

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: Control
var book: Node2D
var capture_dir := ""
var stock: InventoryState


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 3) -> void:
	for index in count:
		await physics_frame
		await process_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while book.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not book.busy, "Notebook motion settles")
	await frames()


func move_pointer(to: Vector2, held := false, relative := Vector2.ZERO) -> void:
	root.warp_mouse(to)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = relative
	event.velocity = relative * 60
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


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func book_point(offset: Vector2) -> Vector2:
	return book.get_global_transform_with_canvas() * (book._book_origin() + offset)


func button(name: String) -> Vector2:
	return (modal.get_node(name) as Control).get_global_rect().get_center()


func capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Saved " + name)


func open_hotspot() -> void:
	var hotspot := screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot/InteractionAnchor") as Node2D
	check(root.get_visible_rect().has_point(point(hotspot)), "Existing hotspot anchor remains visible at this viewport")
	await click(point(hotspot))
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(), "Real hotspot click first opens nonmodal Peek")
	await expand_peek()


func settle_peek() -> void:
	await settle()
	await create_timer(0.4).timeout
	await frames()


func expand_peek() -> void:
	await click((modal.peek.get_node("OpenButton") as Control).get_global_rect().get_center())
	check(modal.is_open() and controller.is_world_input_blocked(), "Open fully transfers Peek into full modal ownership")
	await settle()
	check(book.opened and not modal.is_peeking(), "Expanded view opens the shared notebook and retires Peek")


func check_peek_input() -> void:
	var peek := modal.peek as Control
	var source := screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/SugarCan/IngredientSource") as IngredientPortionSource
	# Right-side jars are intentionally covered. Move this fixture source to the
	# clear middle table before testing world gestures, then restore it below.
	var source_transform := source.source_owner.global_transform
	source.source_owner.global_position = Vector2(960, 700)
	var stove := screen.get_node("WorldRoot/ToolLayer/StoveStation") as Stove
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var water: DailyWaterSupply = root.get_node("GameState").water_supply
	var quantities := stock.quantities
	var supply := water.remaining_ml
	var day := water.day_id
	await tap(KEY_K)
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(), "K first opens Peek without locking the world")
	var paper_rect := peek.get_global_rect()
	check(root.get_visible_rect().encloses(paper_rect), "Peek paper and footer fit this actual viewport")
	check(peek.mouse_filter == Control.MOUSE_FILTER_STOP and paper_rect.size.x < root.size.x * 0.6,
		"Peek covers only its page-sized rectangle, not the whole viewport")
	for name in ["OpenButton", "CloseButton"]:
		check(paper_rect.encloses((peek.get_node(name) as Control).get_global_rect()), "%s remains inside Peek bounds" % name)
	check(not (peek.get_node("OpenButton") as Control).get_global_rect().intersects(
		(peek.get_node("CloseButton") as Control).get_global_rect()), "Peek footer actions do not overlap")
	await capture("peek")
	await tap(KEY_U)
	check(modal.is_peeking() and controller.current_mode == InteractionController.MODE_USE, "Use shortcut keeps Peek open")
	var dial := stove.get_node("DialA") as Node2D
	check(not paper_rect.has_point(point(dial)), "The stove dial remains outside Peek coverage")
	var heat := stove.burners[0].heat_level
	await click(point(dial))
	check(stove.burners[0].heat_level != heat and modal.is_peeking(), "Real uncovered dial input still changes heat without dismissing Peek")
	kettle.add_water(300)
	kettle.temperature = 50
	stove.burners[0].set_heat(1)
	var temperature := kettle.temperature
	await create_timer(0.15).timeout
	check(kettle.temperature > temperature and not paused, "Heating continues while Peek and world input coexist")
	stove.burners[0].set_heat(0)
	kettle.discard_contents()
	# A real target behind the page must not receive a held world release.
	var target := PeekTarget.new()
	target.controller = controller
	screen.get_node("WorldRoot/DropZoneRoot").add_child(target)
	target.global_position = (target.get_canvas_transform().affine_inverse() * paper_rect.get_center())
	controller.register_drop_zone(target)
	await frames()
	await mouse(point(source.source_owner), true)
	check(controller.is_dragging() and modal.is_peeking(), "Physical-source pickup works while Peek remains visible")
	await move_pointer(point(target), true)
	check(controller.is_pointer_over_ui_at(point(target)), "Peek page participates in world-input coverage checks")
	await mouse(point(target), false)
	check(not controller.is_dragging() and target.applied == 0 and stock.quantities == quantities
		and stock.available(&"sugar") == stock.remaining(&"sugar"), "Release over Peek cannot consume a portion through the paper")
	await mouse(point(source.source_owner), true)
	check(controller.is_dragging(), "A second world portion can start beside Peek")
	await tap(KEY_ESCAPE)
	check(not controller.is_dragging() and modal.is_peeking() and stock.quantities == quantities,
		"Escape first cancels a held world gesture while preserving Peek")
	await mouse(point(source.source_owner), false)
	controller.unregister_drop_zone(target)
	target.queue_free()
	# Prove page click-through suppression against an actual physics pick target.
	var probe := Area2D.new()
	probe.input_pickable = true
	probe.z_index = 100
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24
	shape.shape = circle
	probe.add_child(shape)
	var clicks := {"count": 0}
	probe.input_event.connect(func(_viewport, event, _shape):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicks.count += 1)
	screen.add_child(probe)
	probe.global_position = probe.get_canvas_transform().affine_inverse() * paper_rect.get_center()
	modal.close_peek()
	await frames()
	await click(point(probe))
	check(clicks.count == 1, "Exposed probe confirms that the covered world target is pickable")
	check(modal.open_peek(), "Peek reopens above the known world pick target")
	await settle_peek()
	await click(point(probe))
	check(clicks.count == 1 and modal.is_peeking() and not controller.is_dragging(), "Paper consumes clicks instead of activating the world target beneath it")
	probe.queue_free()
	await tap(KEY_G)
	check(modal.is_peeking() and controller.current_mode == InteractionController.MODE_ORGANIZE, "Organize shortcut keeps Peek open")
	var owner_node := source.source_owner
	var origin := owner_node.global_transform
	await mouse(point(owner_node), true)
	check(controller.is_dragging() and modal.is_peeking(), "Real Organize pickup remains available beside Peek")
	await move_pointer(point(owner_node) + Vector2(-25, -20), true)
	controller.cancel_drag()
	await mouse(point(owner_node), false)
	check(modal.is_peeking() and owner_node.global_transform.is_equal_approx(origin), "Canceling the world drag preserves Peek and restores placement")
	await expand_peek()
	await click(button("TabContainer/InventoryTab"))
	await settle()
	await click(button("PeekButton"))
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(), "Pantry Peek button releases full-modal ownership into the working view")
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Full-to-Peek transition preserves Organize")
	await tap(KEY_G)
	check(modal.is_peeking() and controller.current_mode == InteractionController.MODE_NEUTRAL, "Neutral toggle also retains Peek")
	await click((peek.get_node("CloseButton") as Control).get_global_rect().get_center())
	check(not modal.is_peeking() and not modal.is_open(), "Peek Close button closes the current view")
	await tap(KEY_K)
	await settle_peek()
	await tap(KEY_K)
	check(not modal.is_peeking() and not modal.is_open(), "K closes an existing Peek instead of opening full mode")
	await tap(KEY_K)
	await settle_peek()
	await tap(KEY_ESCAPE)
	check(not modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(), "Escape closes Peek without a stale lock")
	check(stock.quantities == quantities and water.remaining_ml == supply and water.day_id == day,
		"Rendered Peek gestures and transitions do not reset shared stock or water")
	source.source_owner.global_transform = source_transform


func check_hotspot_and_tabs() -> void:
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_USE]:
		controller.set_mode(mode)
		await open_hotspot()
		check(controller.current_mode == mode, "Hotspot preserves the prior %s selection" % mode)
		await click(button("CloseButton"))
		await settle()
		check(not modal.is_open() and not controller.is_world_input_blocked() and controller.current_mode == mode,
			"Close button releases input and restores %s" % mode)
	await open_hotspot()
	await capture("open")
	var names := ["InventoryTab", "RecipesTab", "FinanceTab", "QuestsTab"]
	var previous_rect := (modal.get_node("PreviousButton") as Control).get_global_rect()
	for tab_name in names:
		var tab_rect := (modal.get_node("TabContainer/" + tab_name) as Control).get_global_rect()
		check(not previous_rect.intersects(tab_rect), "Previous-page button does not overlap %s" % tab_name)
	for index in names.size():
		await click(button("TabContainer/" + names[index]))
		await settle()
		check(modal.page_index == index and book.spread == index, "Real %s click selects its shell page" % names[index])
	await capture("quests")
	await tap(KEY_RIGHT)
	check(book.spread == 3 and not book.busy, "Right arrow cannot pass the last shell page")
	await tap(KEY_LEFT)
	await settle()
	check(book.spread == 2, "Left arrow changes the notebook page")
	await click(button("TabContainer/InventoryTab"))
	await settle()
	await tap(KEY_LEFT)
	check(book.spread == 0 and not book.busy, "Left arrow cannot precede Inventory")
	await click(button("NextButton"))
	await settle()
	check(book.spread == 1, "Next-page button turns to Recipes through real input")
	await click(button("PreviousButton"))
	await settle()
	check(book.spread == 0, "Previous-page button returns to Inventory through real input")
	await tap(KEY_G)
	await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked()
		and controller.current_mode == InteractionController.MODE_ORGANIZE, "Explicit Organize shortcut closes the notebook and selects Organize")
	await open_hotspot()
	await tap(KEY_U)
	await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked()
		and controller.current_mode == InteractionController.MODE_USE, "Explicit Use shortcut closes the notebook and selects Use")
	await tap(KEY_K)
	await settle_peek()
	check(modal.is_peeking() and not controller.is_world_input_blocked(), "K shortcut opens Peek without changing mode")
	await expand_peek()


func check_edges() -> void:
	for y in [2.0, 330.0, 658.0]:
		await click(book_point(Vector2(460, y)))
		await settle()
		check(book.spread == 1, "Full-height right edge turns at y=%s" % y)
		await click(book_point(Vector2(-460, y)))
		await settle()
		check(book.spread == 0, "Full-height left edge reverses at y=%s" % y)
	await click(book_point(Vector2(200, 330)))
	check(book.spread == 0 and not book.busy, "Page interior does not accidentally turn the sheet")
	var edge := book_point(Vector2(460, 330))
	await mouse(edge, true)
	await move_pointer(book_point(Vector2(300, 330)), true)
	check(book.dragging, "Held outer edge uses pointer-driven page curl")
	await mouse(book_point(Vector2(300, 330)), false)
	await settle()
	check(book.spread == 0, "Short drag returns to the original spread")
	await mouse(edge, true)
	await move_pointer(book_point(Vector2(-50, 330)), true)
	check(book.dragging and book.turn_progress > 0.35, "Long drag crosses the turn threshold")
	await capture("turn-held")
	await mouse(book_point(Vector2(-50, 330)), false)
	await settle()
	check(book.spread == 1, "Releasing a long edge drag commits one spread")
	var left := book_point(Vector2(-460, 330))
	await mouse(left, true)
	await move_pointer(book_point(Vector2(50, 330)), true)
	await tap(KEY_ESCAPE)
	await settle()
	check(book.spread == 1 and not book.dragging and modal.is_open(), "Escape cancels a held turn before closing the notebook")
	await mouse(book_point(Vector2(50, 330)), false)
	await tap(KEY_RIGHT)
	await click(button("CloseButton"))
	await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Close during animated navigation settles and relinquishes input")


func check_world_and_cancellation() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var stove := screen.get_node("WorldRoot/ToolLayer/StoveStation") as Stove
	kettle.add_water(500)
	kettle.temperature = 50
	stove.burners[0].set_heat(1)
	await open_hotspot()
	var before := kettle.temperature
	await create_timer(0.12).timeout
	check(kettle.temperature > before, "World heat advances during rendered modal interaction")
	var dial := stove.get_node("DialA") as Node2D
	var heat_level := stove.burners[0].heat_level
	await click(point(dial))
	await settle()
	check(stove.burners[0].heat_level == heat_level, "Click over covered world dial cannot change heat")
	# That point can be dimmer or paper depending on the actual viewport/layout.
	if modal.is_open():
		await click(Vector2(5, root.size.y * 0.5))
		await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Dimmer click closes without a world action")
	stove.burners[0].set_heat(0)
	var origin := kettle.global_transform
	await mouse(point(kettle.get_node("GripAnchor")), true)
	check(controller.is_dragging(), "Real input holds kettle before opening")
	check(modal.open(), "Notebook can interrupt the existing held gesture")
	await settle()
	await mouse(Vector2(5, 5), false)
	check(not controller.is_dragging() and not kettle.is_held and kettle.global_transform.is_equal_approx(origin), "Modal safely restores the held kettle and consumes its release")
	await click(button("TabContainer/InventoryTab"))
	await settle()
	var edge := book_point(Vector2(460, 330))
	await mouse(edge, true)
	await move_pointer(book_point(Vector2(-50, 330)), true)
	modal.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await settle()
	check(not book.dragging and book.spread == 0, "Focus loss cancels even a long uncommitted turn")
	await mouse(book_point(Vector2(-50, 330)), false)
	await mouse(book_point(Vector2(460, 330)), true)
	await move_pointer(book_point(Vector2(-50, 330)), true)
	var original_size := root.size
	root.size = original_size + Vector2i(40, 20)
	await settle()
	check(not book.dragging and book.spread == 0 and modal.is_open(), "Resize cancels the turn while preserving modal ownership")
	await mouse(Vector2(5, 5), false)
	root.size = original_size
	await frames()
	await tap(KEY_ESCAPE)
	await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Escape closes the stable notebook without stale ownership")
	await capture("closed-again")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Khata modal input checks require a rendered window; use khata_modal_test.gd for headless checks.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	check(root.get_node("GameState").reset_demo_state(), "Rendered fixture initializes shared supplies")
	stock = root.get_node("GameState").inventory
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames(4)
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	screen.set_portion_provider(stock)
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Normal scene starts without notebook input ownership")
	await capture("initial")
	await check_peek_input()
	await check_hotspot_and_tabs()
	await check_edges()
	await check_world_and_cancellation()
	screen.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Scene teardown preserves visible pointer state")
	print("KHATA_MODAL_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
