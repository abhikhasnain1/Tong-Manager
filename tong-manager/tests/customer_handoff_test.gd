extends SceneTree
## Real scene/controller/stock handoff, with deliberate recipe mistakes.

const TONG := preload("res://scenes/gameplay/tong/TongDayScreen.tscn")
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var queue: CustomerQueueManager
var service: CustomerService
var stock: InventoryState
var received: Array[Dictionary] = []
var sequence := 0
var capture_dir := ""


func _init() -> void:
	run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func setup() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		await frames()
	root.get_node("GameState").reset_demo_state()
	screen = TONG.instantiate()
	screen.customer_queue_auto_start = false
	root.add_child(screen)
	await frames()
	controller = screen.get_node("InteractionController")
	queue = screen.customer_queue
	service = screen.customer_service
	stock = root.get_node("GameState").inventory
	queue.set_process(false)
	queue.reduced_motion = true
	controller.set_mode(InteractionController.MODE_INTERACT)
	received.clear()
	service.service_accepted.connect(func(record: Dictionary): received.append(record))
	check(service != null and service.get_records().is_empty(), "Live screen owns a fresh customer service")


func start_order(request_id: StringName, second: StringName = &"") -> Customer:
	sequence += 1
	var day := DayConfig.new()
	var schedule := CustomerSchedule.new()
	schedule.id = &"handoff_test"
	schedule.mode = CustomerSchedule.Mode.AUTHORED
	schedule.max_active = 2
	var catalog := root.get_node("Catalog")
	for id in [request_id] if second.is_empty() else [request_id, second]:
		var entry := CustomerArrivalDef.new()
		entry.id = StringName("visit_%s" % schedule.arrivals.size())
		entry.customer = catalog.get_customer(&"customer_a" if schedule.arrivals.is_empty() else &"customer_b")
		entry.request = catalog.get_order_request(id)
		entry.patience_override = 180.0
		schedule.arrivals.append(entry)
	day.customer_schedule = schedule
	check(queue.start(day, 66, StringName("handoff_run_%s" % sequence)), "A saved request starts in the real queue")
	queue.advance(0.0)
	return queue.get_active_customers()[0]


func point_for(actor: Customer) -> Vector2:
	var rect := actor.get_serve_bounds()
	# Sample visible alpha throughout the body; roof/counter/hanging stock must
	# remain in front, including at cropped aspect ratios.
	for y in range(int(rect.position.y), int(rect.end.y), 8):
		for x in range(int(rect.position.x), int(rect.end.x), 8):
			var point := actor.get_canvas_transform() * Vector2(x, y)
			if service.pick_customer_at(point) == actor and not (controller._drag_pointer_over_ui(point) if controller.is_dragging() else controller.is_pointer_over_ui_at(point)): return point
	return Vector2(INF, INF)


func move_pointer(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless": root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if is_instance_valid(controller) and controller.is_dragging() else 0
	root.push_input(motion, true)
	await frames()


func source(item_id: StringName) -> IngredientPortionSource:
	for value: IngredientPortionSource in screen.portion_sources:
		if value.item_id == item_id: return value
	return null


func mouse(point: Vector2, pressed: bool) -> void:
	await move_pointer(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await frames()


func take_snack(item_id: StringName) -> bool:
	var physical := source(item_id)
	if DisplayServer.get_name() == "headless": return physical.begin_portion(Vector2(900, 500))
	var hanging := physical.source_owner as HangingSourceBody
	var point := Vector2(INF, INF)
	var size := root.get_visible_rect().size
	for y in range(90, int(size.y * 0.6), 10):
		for x in range(200, int(size.x - 200), 10):
			if hanging.contains_pointer(Vector2(x, y)) and hanging.is_frontmost_at(Vector2(x, y)):
				point = Vector2(x, y)
				break
		if point.is_finite(): break
	if not point.is_finite(): return false
	await mouse(point, true)
	return controller.is_dragging() and controller.current_payload.item_id == item_id


func release_at(actor: Customer) -> void:
	var point := point_for(actor)
	check(point.is_finite(), "Customer exposes its visible body as the handoff target")
	await move_pointer(point)
	controller.update_drag(point)
	check(controller.hovered_drop_zone is CustomerServiceZone, "Actual controller selects the customer's silhouette target")
	if DisplayServer.get_name() == "headless": controller.release_drop(point)
	else: await mouse(point, false)
	await frames()


func take_cup(cup: Cup) -> void:
	await move_pointer(Vector2(960, 950))
	if DisplayServer.get_name() == "headless":
		check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Use picks up the actual placed cup")
	else:
		await mouse(cup.get_global_transform_with_canvas().origin, true)
		check(controller.current_drag_node == cup, "Actual mouse press picks up the placed cup")


func fill(cup: Cup, kind := &"black_tea", quality := &"ready", temperature := 90.0, amount := 250.0) -> void:
	var counts := {} if kind == &"water" else {&"black_tea": 1}
	check(is_equal_approx(cup.receive_liquid(kind, amount, temperature, {}, true,
		{"state": quality, "infused_counts": counts, "used_boiling_water": true, "batch_volume": 1500.0}), amount), "Review cup receives a declared brew contribution")


func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Saved serving review " + label)


func warm_and_empty() -> void:
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	var original_parent := cup.get_parent()
	var original_transform := cup.transform
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	await take_cup(cup)
	await release_at(actor)
	check(not order.fulfilled and cup.get_parent() == original_parent and cup.transform.is_equal_approx(original_transform), "Empty cup returns to its exact origin without fulfilling")
	check(handle.surface.is_registered(cup) and service.get_records().is_empty(), "Empty attempt retains footprint and creates no review/payment record")
	fill(cup)
	await take_cup(cup)
	var old_payload := controller.current_payload
	await move_pointer(point_for(actor))
	controller.update_drag(point_for(actor))
	var zone := controller.hovered_drop_zone as CustomerServiceZone
	check(zone != null and zone.accepts(old_payload).is_valid, "Nonempty warm cup is serveable")
	await capture("01-warm-cup-target")
	await release_at(actor)
	check(order.fulfilled and not order.get_accepted_result().bad_review, "Correct warm tea fulfils its frozen order happily")
	check(cup.state == Cup.CupState.SERVED and cup.assigned_order_id == order.order_id, "Served state and order identity commit together")
	check(service.get_served_cup(order.order_id) == cup and not cup.is_visible_in_tree(), "The same cup is retained off table")
	check(not handle.surface.is_registered(cup) and not screen.get_cups().has(cup), "Served cup frees its old footprint and leaves active targets")
	check(not cup.begin_interaction_drag(Vector2.ZERO) and not handle.begin_drag(Vector2.ZERO), "Retained cup cannot be served or organized again")
	check(received.size() == 1 and received[0].price == order.get_request().price, "One future payment event retains the saved quoted price")
	check(not zone.try_apply_drop(old_payload) and received.size() == 1, "Replayed handoff cannot fulfil or notify twice")
	await capture("02-happy-reaction")
	queue.advance(0.0)
	check(queue.get_active_entries()[0].phase == &"served_reaction" and actor.emotion_icon.visible, "Happy reaction stays visible before walking away")
	queue.advance(queue.served_reaction_seconds)
	check(service.get_served_cup(order.order_id) == cup and queue.get_active_customers().is_empty(), "Customer departure preserves the served cup")
	check(queue.get_snapshot().history[0].service_result == order.get_accepted_result(), "Departure history retains the exact review outcome")
	start_order(&"ready_banana")
	check(service.get_served_cup(order.order_id) == cup and service.get_records().size() == 1, "Restarting customers neither loses nor returns a served cup")


func cup_mistakes() -> void:
	for sample in [
		[&"black_tea", &"ready", 20.0, 250.0, &"cold_tea"],
		[&"water", &"water", 70.0, 250.0, &"wrong_liquid"],
		[&"black_tea", &"underbrewed", 80.0, 250.0, &"underbrewed"],
		[&"black_tea", &"oversteeped", 80.0, 250.0, &"oversteeped"],
		[&"black_tea", &"ready", 80.0, 100.0, &"insufficient_volume"],
	]:
		var actor := start_order(&"tea_cha_no_sugar")
		var cup: Cup = screen.get_cups()[0]
		fill(cup, sample[0], sample[1], sample[2], sample[3])
		await take_cup(cup)
		await release_at(actor)
		var outcome := actor.order.get_accepted_result()
		check(outcome.get("accepted", false) and outcome.get("bad_review", false), "A deliberately poor brew is still handed over")
		check(outcome.get("reasons", []).has(sample[4]), "Poor brew records its specific cause: " + String(sample[4]))
		check(actor.get_presentation_snapshot().review_count == 1, "Each poor serving produces one bad-review outcome")
		if sample[4] == &"oversteeped": await capture("03-unhappy-reaction")


func ready_items_and_cross_orders() -> void:
	for request in [&"ready_banana", &"ready_biscuits", &"tea_cha_no_sugar"]:
		var actor := start_order(request)
		var order := actor.order
		var before := stock.remaining(&"banana")
		await move_pointer(Vector2(960, 950))
		check(await take_snack(&"banana"), "Hanging source reserves one real banana")
		check(stock.remaining(&"banana") == before and stock.available(&"banana") == before - 1, "Pickup reserves without consuming")
		await release_at(actor)
		check(stock.remaining(&"banana") == before - 1 and order.fulfilled, "Any order takes one committed banana")
		check(order.get_accepted_result().bad_review == (request != &"ready_banana"), "Wrong snack or drink request becomes an accepted bad review")
		check(order.get_accepted_result().served_kind == &"ready_item", "Result distinguishes offered kind from requested kind")
	var actor := start_order(&"ready_banana")
	var cup: Cup = screen.get_cups()[0]
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	check(actor.order.fulfilled and actor.order.get_accepted_result().bad_review and service.get_served_cup(actor.order.order_id) == cup,
		"A cup can fulfil a snack request with a bad review and retained cup custody")


func canceled_and_removed() -> void:
	var actor := start_order(&"ready_biscuits")
	var order := actor.order
	var before := stock.remaining(&"biscuits")
	await move_pointer(Vector2(960, 950))
	check(await take_snack(&"biscuits"), "Snack starts before cancellation")
	controller.cancel_drag()
	check(stock.remaining(&"biscuits") == before and stock.available(&"biscuits") == before and not order.fulfilled, "Cancel restores reservation with no review")
	check(await take_snack(&"biscuits"), "Snack starts before customer leaves")
	var point := point_for(actor)
	actor.leave()
	controller.release_drop(point)
	await frames()
	check(stock.remaining(&"biscuits") == before and stock.available(&"biscuits") == before and not order.fulfilled, "Departed target cannot consume the held snack")
	check(order.get_results().is_empty(), "Non-handoffs never manufacture review results")


func pantry_exports() -> void:
	var modal: KhataModal = screen.khata_modal
	for peeking in [true, false]:
		var actor := start_order(&"ready_biscuits", &"ready_banana")
		check(modal.open_peek() if peeking else modal.open(), "Notebook opens for real customer export")
		await settle_book(modal)
		modal.select_page(0)
		await settle_book(modal)
		var before := stock.remaining(&"biscuits")
		var cell := modal.inventory_item_screen_rect(&"biscuits").get_center()
		if DisplayServer.get_name() == "headless":
			check(modal.begin_inventory_export(&"biscuits", cell), "Pantry reserves a real biscuit")
		else:
			await mouse(cell, true)
			check(controller.is_modal_export_active() and controller.current_payload.item_id == &"biscuits", "Actual pantry press reserves a real biscuit")
		var payload := controller.current_payload
		queue.advance(0.0)
		await frames()
		check(controller.current_payload == payload and controller.is_modal_export_active(), "A new arrival does not cancel the pantry gesture")
		await release_at(actor)
		check(actor.order.fulfilled and stock.remaining(&"biscuits") == before - 1, "Peek/Full pantry can serve its original visible customer")
		check(modal.is_peeking() if peeking else modal.is_open(), "Serving keeps the notebook in its chosen pose")
		await capture("04-pantry-peek-service" if peeking else "05-pantry-full-service")
		modal.close()
		await settle_book(modal)
		controller.set_mode(InteractionController.MODE_INTERACT)


func settle_book(modal: KhataModal) -> void:
	var until := Time.get_ticks_msec() + 8000
	while (modal.is_traveling() or modal.book.busy) and Time.get_ticks_msec() < until: await process_frame
	await frames()
	check(not modal.is_traveling() and not modal.book.busy, "Notebook animation settles")


func lifecycle_callbacks() -> void:
	await setup()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	var recorded := order.get_accepted_result()
	actor.free()
	await frames()
	check(service.get_served_cup(order.order_id) == cup and service.get_records()[0].result == recorded,
		"Immediate customer deletion cannot erase accepted custody or history")
	root.remove_child(screen)
	check(service.get_records()[0].result == recorded, "Same-screen detachment preserves committed history")
	root.add_child(screen)
	await frames()
	check(service.get_served_cup(order.order_id) == cup and cup.state == Cup.CupState.SERVED,
		"Same-screen re-entry retains the same served cup")
	check(received.size() == 1 and not screen.get_cups().has(cup), "Re-entry neither republishes payment intent nor returns a cup")
	actor = start_order(&"ready_biscuits")
	var before := stock.remaining(&"biscuits")
	await move_pointer(Vector2(960, 950))
	check(await take_snack(&"biscuits"), "Ready portion starts before synchronous retirement")
	order = actor.order
	var old_payload := controller.current_payload
	var target_point := point_for(actor)
	var callback := func():
		if order.fulfilled:
			check(service.get_records().back().result == order.get_accepted_result(), "Stock observers see the already recorded acceptance")
			check(not service.try_handoff(actor.get_node("CustomerHandoff"), old_payload), "Synchronous replay cannot consume twice")
			root.remove_child(screen)
	stock.changed.connect(callback)
	controller.release_drop(target_point)
	stock.changed.disconnect(callback)
	check(order.fulfilled and stock.remaining(&"biscuits") == before - 1 and not screen.is_inside_tree(),
		"Successful stock callback can detach its screen without rollback or duplicate debit")
	root.add_child(screen)
	await frames()
	check(service.get_records().size() == 2 and not controller.is_dragging(), "Re-entry has two outcomes and no stale gesture")
	# A freed target leaves a stale map entry until the next process tick.
	actor = start_order(&"ready_banana")
	var zone := actor.get_node("CustomerHandoff")
	zone.free()
	check(service.get_drop_targets().is_empty(), "Freed zone references are safely skipped before synchronization")
	await frames()
	check(service.get_drop_targets().size() == 1, "A live customer can recover its removed presentation target")
	await setup()
	actor = start_order(&"ready_biscuits")
	order = actor.order
	before = stock.remaining(&"biscuits")
	await move_pointer(Vector2(960, 950))
	check(await take_snack(&"biscuits"), "Ready portion starts before controller disposal")
	target_point = point_for(actor)
	var retire_controller := func():
		if order.fulfilled and is_instance_valid(controller):
			controller.get_parent().remove_child(controller)
			controller.queue_free()
	stock.changed.connect(retire_controller)
	controller.release_drop(target_point)
	stock.changed.disconnect(retire_controller)
	await frames()
	check(order.fulfilled and stock.remaining(&"biscuits") == before - 1 and service.get_records().size() == 1,
		"Controller disposal during committed-stock notification preserves the completed handoff")
	check(received.size() == 1, "Controller disposal still publishes one stable accepted outcome")


func ownership_guards() -> void:
	await setup()
	var actor := start_order(&"ready_banana")
	var order := actor.order
	var zone := actor.get_node("CustomerHandoff") as CustomerServiceZone
	var parent := actor.get_parent()
	var before := stock.remaining(&"banana")
	await move_pointer(Vector2(960, 950))
	check(await take_snack(&"banana"), "Owned source starts before target context changes")
	var payload := controller.current_payload
	parent.reparent(root, true)
	check(not zone.accepts(payload).is_valid and not zone.try_apply_drop(payload), "Customer moved outside this stall cannot consume its stock")
	controller.cancel_drag()
	check(not order.fulfilled and stock.remaining(&"banana") == before and stock.available(&"banana") == before, "Cross-context target leaves stock and order unchanged")
	parent.reparent(screen.get_node("WorldRoot/CustomerLayer"), true)
	actor = start_order(&"ready_banana")
	var cup: Cup = screen.get_cups()[0]
	fill(cup)
	await take_cup(cup)
	payload = controller.current_payload
	zone = actor.get_node("CustomerHandoff") as CustomerServiceZone
	payload.metadata.transient = true
	check(not zone.accepts(payload).is_valid, "A real cup cannot masquerade as a disposable portion")
	payload.metadata.erase("transient")
	controller.cancel_drag()
	check(is_instance_valid(cup) and cup.state == Cup.CupState.FILLED, "Malformed cup metadata never deletes or serves the real cup")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	await setup()
	await warm_and_empty()
	await cup_mistakes()
	await setup()
	await ready_items_and_cross_orders()
	await canceled_and_removed()
	await pantry_exports()
	await lifecycle_callbacks()
	await ownership_guards()
	screen.queue_free()
	await frames()
	print("CUSTOMER_HANDOFF: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
