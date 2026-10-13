extends SceneTree
## Rendered viewport input for the production notebook shell, not pantry/export content.

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: Control
var book: Node2D
var capture_dir := ""


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
	check(modal.is_open() and controller.is_world_input_blocked(), "Real hotspot click opens modal ownership")
	await settle()
	check(book.opened, "Hotspot opens the shared notebook visual")


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
	await settle()
	check(modal.is_open() and controller.is_world_input_blocked(), "K shortcut opens the notebook without changing mode")


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
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames(4)
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Normal scene starts without notebook input ownership")
	await capture("initial")
	await check_hotspot_and_tabs()
	await check_edges()
	await check_world_and_cancellation()
	screen.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Scene teardown preserves visible pointer state")
	print("KHATA_MODAL_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
