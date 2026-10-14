extends SceneTree
## Pantry UI/export contracts use explicit test targets, not final recipe rules.

class ContractTarget extends DropZone:
	var controller: InteractionController
	var applied := 0
	var reject := false
	var apply_success := true
	var callback: Callable
	func _init() -> void:
		var marker := Sprite2D.new()
		marker.name = "DebugPreview"
		marker.hide()
		add_child(marker)
		snap_radius = 32.0
	func is_relevant_to(payload: HeldItemPayload) -> bool:
		return payload != null and payload.metadata.get("portion") is IngredientPortion
	func accepts(payload: HeldItemPayload) -> DropValidation:
		if (not is_inside_tree() or is_queued_for_deletion() or reject
			or not is_relevant_to(payload) or not controller.can_address_drop_zone(payload, self)):
			return DropValidation.invalid("Unavailable contract target")
		return DropValidation.valid() if (payload.metadata.portion as IngredientPortion).is_available() else DropValidation.invalid("Expired portion")
	func try_apply_drop(payload: HeldItemPayload) -> bool:
		return accepts(payload).is_valid and (payload.metadata.portion as IngredientPortion).commit(_apply)
	func _apply() -> bool:
		if not apply_success:
			return false
		applied += 1
		if callback.is_valid():
			callback.call()
		return true

const ITEMS := [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]
const UNITS := [&"teabag", &"spoonful", &"spoonful", &"piece", &"piece"]
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: Control
var book: Node2D
var stock: InventoryState
var target: ContractTarget
var forbidden: ContractTarget
var page: Control
var page_identity := 0
var page_viewport_identity := 0
var display_changes := 0
var dropped := 0
var canceled := 0
var reentry_started := false


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
	while (book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not book.busy and not modal.is_traveling(), "Notebook motion settles")
	await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func source() -> IngredientPortionSource:
	return screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/SugarCan/IngredientSource")


func allow_target() -> void:
	var allowed: Array[DropZone] = [target]
	modal.configure_export_targets(allowed)


func open_view(peeking: bool) -> void:
	if modal.is_open() or modal.is_peeking():
		modal.close()
		await settle()
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(modal.open_peek() if peeking else modal.open(), "Requested pantry view opens")
	await settle()
	modal.select_page(0)
	await settle()
	check(modal.is_peeking() == peeking and modal.is_open() != peeking, "Requested pantry view owns the correct input state")
	check(controller.is_world_input_blocked() != peeking, "Only Full reading blocks ordinary world input")


func take(item_id: StringName) -> HeldItemPayload:
	var before := stock.remaining(item_id)
	check(modal.begin_inventory_export(item_id, modal.inventory_item_screen_rect(item_id).get_center()), "%s starts a pantry portion" % item_id)
	var payload := controller.current_payload
	check(payload != null and payload.source == &"khata", "Pantry exports identify their source")
	if payload == null:
		return null
	check(payload.item_id == item_id and payload.quantity == 1 and payload.metadata.unit == stock.get_unit(item_id), "Pantry payload keeps the shared item, unit and single quantity")
	check(payload.metadata.category == (&"ready_item" if stock.get_unit(item_id) == &"piece" else &"ingredient_portion"), "Pantry payload uses the existing portion category")
	check(stock.remaining(item_id) == before and stock.available(item_id) == before - 1, "Pickup reserves without consuming")
	check(controller.is_world_input_blocked() and not source().begin_portion(point(source().source_owner)), "Export exclusively owns one gesture even from Peek")
	check(not modal.begin_inventory_export(item_id, Vector2.ZERO), "A held portion cannot begin a second export")
	return payload


func reading(peeking: bool, label: String) -> void:
	check(not controller.is_dragging() and not controller.is_modal_export_active() and not modal.exporting, "%s clears only its export session" % label)
	check(modal.is_peeking() == peeking and modal.is_open() != peeking, "%s returns to its originating view" % label)
	check(controller.is_world_input_blocked() != peeking, "%s restores reading input ownership" % label)
	check(modal.page_index == 0 and page.get_instance_id() == page_identity and page.get_parent().get_instance_id() == page_viewport_identity, "%s retains the exact shared page and spread" % label)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not target.debug_preview.visible, "%s clears its cursor and target highlight" % label)


func check_display() -> void:
	check(page == modal.inventory_page and page.get_parent() == book._pages[1], "Pantry is the existing right-page viewport content")
	for index in ITEMS.size():
		var id: StringName = ITEMS[index]
		var rect: Rect2 = page.item_rect(id)
		var shown: Dictionary = page.item_display(id)
		check(rect.has_area() and Rect2(0, 0, 480, 660).encloses(rect), "%s cell lies inside the authored right page" % id)
		check(page.item_at(rect.get_center()) == id, "%s cell is independently hit-testable" % id)
		check(shown.unit == UNITS[index] and shown.remaining == stock.remaining(id) and shown.available == stock.available(id) and shown.stock_bound, "%s display reads the single stock authority and agreed unit" % id)
		for other in range(index):
			check(not rect.intersects(page.item_rect(ITEMS[other])), "Pantry cells do not overlap")
	check(page.item_at(Vector2(5, 5)) == &"" and not page.item_rect(&"unknown").has_area(), "Margin and unknown item never become a pantry cell")
	var before := display_changes
	check(stock.set_quantity(&"sugar", 7), "Fixture can update shared stock")
	check(display_changes > before and page.item_display(&"sugar").remaining == 7, "Shared stock changes refresh the existing page immediately")
	page.set_hovered_item(&"sugar")
	check(page.item_display(&"sugar").hovered, "Hovered cell reports feedback without reserving stock")
	page.set_hovered_item(&"")
	check(stock.available(&"sugar") == 7, "Page refresh and hover do not consume or reserve")
	modal.configure_inventory(null)
	check(not page.item_display(&"sugar").stock_bound and page.item_display(&"sugar").status == "Unavailable", "A missing provider is distinct from depleted inventory")
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO), "An unavailable provider cannot reserve a portion")
	modal.configure_inventory(stock)
	check(page.item_display(&"sugar").remaining == 7 and page.item_display(&"sugar").stock_bound, "Rebinding restores existing quantities without replenishment")


func check_exports(peeking: bool) -> void:
	await open_view(peeking)
	for id: StringName in ITEMS:
		var before := stock.remaining(id)
		var payload := take(id)
		if payload == null:
			continue
		var shown: Dictionary = page.item_display(id)
		check(shown.remaining == before and shown.available == before - 1 and not String(shown.status).is_empty(), "Held quantity is distinguished from consumed stock on the page")
		controller.update_drag(point(target))
		controller.cancel_drag()
		await frames()
		check(stock.remaining(id) == before and stock.available(id) == before, "Cancellation restores the unused reservation")
		reading(peeking, "%s cancel" % id)
		payload = take(id)
		if payload == null:
			continue
		var applied_before := target.applied
		controller.release_drop(point(target))
		await frames()
		check(target.applied == applied_before + 1 and stock.remaining(id) == before - 1 and stock.available(id) == before - 1, "Accepted contract drop commits one unit exactly once")
		check(not target.try_apply_drop(payload), "A repeated payload cannot execute its command twice")
		controller.release_drop(point(target))
		check(target.applied == applied_before + 1 and stock.remaining(id) == before - 1, "Repeated release cannot consume or apply again")
		check(page.item_display(id).remaining == before - 1 and page.item_display(id).available == before - 1, "Committed quantity immediately reaches both notebook views")
		reading(peeking, "%s success" % id)
	for reason in ["empty space", "not allowlisted", "rejected", "command failure", "detached target", "queued target"]:
		var before := stock.remaining(&"sugar")
		var payload := take(&"sugar")
		if payload == null:
			continue
		var destination := point(target)
		match reason:
			"empty space": destination = Vector2(3, 3)
			"not allowlisted": destination = point(forbidden)
			"rejected": target.reject = true
			"command failure": target.apply_success = false
			"detached target": screen.remove_child(target)
			"queued target": target.queue_free()
		controller.release_drop(destination)
		await frames()
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "%s cannot consume a pantry portion" % reason)
		if reason == "queued target":
			target = make_target(Vector2(220, 700))
			allow_target()
		elif reason == "detached target":
			screen.add_child(target)
		target.reject = false
		target.apply_success = true
		reading(peeking, reason)
	var saved := stock.remaining(&"sugar")
	check(stock.set_quantity(&"sugar", 0), "Shared stock can be exhausted")
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO) and not controller.is_dragging(), "An empty cell never creates a consumable payload")
	check(page.item_display(&"sugar").remaining == 0 and not String(page.item_display(&"sugar").status).is_empty(), "Exhausted cell reports empty feedback")
	check(stock.set_quantity(&"sugar", saved), "Fixture restores exhausted supply explicitly")
	check(not modal.begin_inventory_export(&"unknown", Vector2.ZERO), "An unknown item cannot create a portion")
	var no_targets: Array[DropZone] = []
	modal.configure_export_targets(no_targets)
	var before := stock.remaining(&"sugar")
	take(&"sugar")
	controller.release_drop(point(target))
	await frames()
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Explicitly disabling every allowed target permits only carry/cancel")
	reading(peeking, "No configured targets")
	allow_target()


func check_interruptions(peeking: bool) -> void:
	for reason in ["focus", "resize", "mode", "reset", "close", "provider replacement", "source removal"]:
		await open_view(peeking)
		var before := stock.remaining(&"sugar")
		take(&"sugar")
		controller.update_drag(point(target))
		var export_source := modal.get_node("ExportSource")
		match reason:
			"focus": modal.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"resize": root.size_changed.emit()
			"mode": controller.set_mode(InteractionController.MODE_ORGANIZE)
			"reset":
				var quantities := stock.quantities
				var units: Dictionary = {}
				for id: StringName in quantities: units[id] = stock.get_unit(id)
				check(stock.reset(quantities, units), "Stock reset invalidates the outstanding token")
			"close": modal.close()
			"provider replacement": modal.configure_inventory(new_stock())
			"source removal": modal.remove_child(export_source)
		await settle()
		check(not controller.is_dragging() and not modal.exporting and stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "%s safely releases the pantry gesture" % reason)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not target.debug_preview.visible, "%s clears pointer and target state" % reason)
		if reason == "provider replacement": modal.configure_inventory(stock)
		if reason == "source removal":
			check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO)
				and not controller.is_dragging() and stock.remaining(&"sugar") == before
				and stock.available(&"sugar") == before,
				"Retrying pickup while ExportSource is absent is refused without changing stock")
			modal.add_child(export_source)
		if reason == "close" or (reason == "mode" and not peeking):
			check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked(), "%s deliberately closes its view" % reason)
		else:
			reading(peeking, reason)


func new_stock() -> InventoryState:
	var result := InventoryState.new()
	var quantities: Dictionary = {}
	var units: Dictionary = {}
	for index in ITEMS.size():
		quantities[ITEMS[index]] = 9
		units[ITEMS[index]] = UNITS[index]
	result.reset(quantities, units)
	return result


func check_shared_physical_source() -> void:
	await open_view(true)
	controller.set_mode(InteractionController.MODE_USE)
	var sugar := source()
	var original := sugar.source_owner.global_transform
	sugar.source_owner.global_position = Vector2(700, 650)
	var before := stock.remaining(&"sugar")
	check(sugar.provider == stock and sugar.begin_portion(point(sugar.source_owner)), "Physical source reads the same pantry stock while Peek stays open")
	check(page.item_display(&"sugar").remaining == before and page.item_display(&"sugar").available == before - 1, "Physical reservation refreshes the pantry page")
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO), "Pantry cannot replace an independently held physical portion")
	modal.close_peek()
	await settle()
	check(controller.is_dragging() and stock.available(&"sugar") == before - 1, "Closing Peek preserves independently held world stock")
	controller.cancel_drag()
	check(stock.available(&"sugar") == before, "Independent world cancellation returns stock")
	check(modal.open_peek(), "Peek reopens after a world gesture")
	await settle()
	check(sugar.begin_portion(point(sugar.source_owner)), "Physical source can repeat extraction after Peek reopens")
	controller.release_drop(point(target))
	check(stock.remaining(&"sugar") == before - 1 and page.item_display(&"sugar").remaining == before - 1, "Physical commit reaches the same notebook display")
	sugar.source_owner.global_transform = original


func check_reentry() -> void:
	await open_view(true)
	var before := stock.remaining(&"sugar")
	take(&"sugar")
	var count_before := target.applied
	var drops_before := dropped
	var cancels_before := canceled
	reentry_started = false
	target.callback = func() -> void:
		controller.cancel_drag()
		reentry_started = modal.begin_inventory_export(&"condensed_milk", Vector2.ZERO)
		controller.set_mode(InteractionController.MODE_ORGANIZE)
	controller.release_drop(point(target))
	target.callback = Callable()
	await frames()
	check(not reentry_started and target.applied == count_before + 1 and dropped == drops_before + 1 and canceled == cancels_before, "Synchronous command observers cannot replace or recancel the accepted gesture")
	check(stock.remaining(&"sugar") == before - 1 and controller.current_mode == InteractionController.MODE_ORGANIZE, "Accepted commit happens once before requested mode change")
	reading(true, "Reentrant command")
	before = stock.remaining(&"sugar")
	stock.changed.connect(func() -> void: modal.close_peek(), CONNECT_ONE_SHOT)
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO), "A synchronous close during reservation prevents gesture creation")
	await settle()
	check(not controller.is_dragging() and stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Reservation interrupted by close is returned without a held visual")
	await open_view(true)
	var replacement := new_stock()
	stock.changed.connect(func() -> void: modal.configure_inventory(replacement), CONNECT_ONE_SHOT)
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO), "A synchronous provider replacement invalidates the original reservation")
	check(stock.available(&"sugar") == before and replacement.available(&"sugar") == 9, "Provider swap loses neither old nor new stock")
	modal.configure_inventory(stock)


func check_interrupted_pickup() -> void:
	for reason in ["mode", "focus", "resize"]:
		await open_view(true)
		var before := stock.remaining(&"sugar")
		var interrupted := [false]
		var on_reserve := func() -> void:
			interrupted[0] = true
			match reason:
				"mode": controller.set_mode(InteractionController.MODE_ORGANIZE)
				"focus": modal.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
				"resize": root.size_changed.emit()
		stock.changed.connect(on_reserve, CONNECT_ONE_SHOT)
		check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO) and interrupted[0], "%s during reserve aborts pickup before a held payload exists" % reason)
		await frames()
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "%s during reserve releases the original token" % reason)
		reading(true, "%s during reserve" % reason)
	for reason in ["close", "hide"]:
		await open_view(true)
		var before := stock.remaining(&"sugar")
		var interrupted := [false]
		controller.report_hint("Before the temporary export lock")
		var on_lock_hint := func(_text: String) -> void:
			interrupted[0] = true
			if reason == "close": modal.close_peek()
			else: modal.peek.hide()
		controller.hint_changed.connect(on_lock_hint, CONNECT_ONE_SHOT)
		check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO) and interrupted[0], "%s while acquiring the export lock aborts pickup" % reason)
		check(not controller.is_dragging() and not modal.exporting and not controller.is_world_input_blocked(), "%s during lock notification synchronously clears gesture and temporary blocker" % reason)
		await settle()
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before and not modal.is_peeking(), "%s during lock notification loses no stock and leaves no phantom view" % reason)
	await open_view(true)
	var before := stock.remaining(&"sugar")
	take(&"sugar")
	modal.peek.hide()
	check(not controller.is_dragging() and not modal.exporting and not controller.is_world_input_blocked(), "Hiding active Peek synchronously cancels its owned export and blocker")
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Hiding active Peek releases its unused reservation")
	await frames()
	check(not modal.is_peeking() and not modal.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "External Peek hiding retires the shared renderer and cursor")


func check_scene_lifecycle() -> void:
	await open_view(true)
	var before := stock.remaining(&"sugar")
	take(&"sugar")
	root.remove_child(screen)
	check(not controller.is_dragging() and stock.available(&"sugar") == before, "Scene detachment returns a held pantry reservation synchronously")
	root.add_child(screen)
	await frames()
	check(modal.inventory_page == page and page.get_instance_id() == page_identity, "Scene reentry reuses the same page instead of duplicating inventory")
	check(modal.open_peek(), "Reentered scene can reopen its pantry")
	await settle()
	take(&"sugar")
	controller.cancel_drag()
	check(stock.available(&"sugar") == before, "Reentered pantry still resolves portions against the same authority")
	modal.select_page(1)
	await settle()
	check(not modal.begin_inventory_export(&"sugar", Vector2.ZERO), "Recipe spread cannot silently export a hidden pantry item")
	modal.select_page(0)
	await settle()
	take(&"sugar")
	screen.queue_free()
	await frames()
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Scene destruction clears source, reservation and cursor without consuming")


func make_target(at: Vector2) -> ContractTarget:
	var result := ContractTarget.new()
	result.controller = controller
	result.position = at
	screen.add_child(result)
	controller.register_drop_zone(result)
	return result


func run() -> void:
	root.size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(root.get_node("GameState").reset_demo_state(), "Test initializes the existing production inventory authority")
	stock = root.get_node("GameState").inventory
	for id: StringName in ITEMS: stock.set_quantity(id, 8)
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames()
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	page = modal.inventory_page
	page_identity = page.get_instance_id()
	page_viewport_identity = page.get_parent().get_instance_id()
	page.content_changed.connect(func() -> void: display_changes += 1)
	controller.drag_dropped.connect(func(_payload: HeldItemPayload, _zone: DropZone) -> void: dropped += 1)
	controller.drag_canceled.connect(func(_payload: HeldItemPayload) -> void: canceled += 1)
	screen.set_portion_provider(stock)
	target = make_target(Vector2(220, 700))
	forbidden = make_target(Vector2(350, 700))
	allow_target()
	await open_view(true)
	check_display()
	for peeking in [true, false]:
		await check_exports(peeking)
		await check_interruptions(peeking)
	await check_shared_physical_source()
	await check_reentry()
	await check_interrupted_pickup()
	await check_scene_lifecycle()
	print("KHATA_INVENTORY: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
