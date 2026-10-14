extends "res://tests/customer_payment_test.gd"
## Authored refusal responses exercise real gestures, custody, stock and payment.


func response_order(response: int, patience := 0, request_id: StringName = &"tea_cha_no_sugar") -> Customer:
	sequence += 1
	var catalog := root.get_node("Catalog")
	var arrival := CustomerArrivalDef.new()
	arrival.id = &"response_visit"
	arrival.customer = catalog.get_customer(&"customer_a")
	arrival.request = catalog.get_order_request(request_id)
	arrival.patience_override = 180.0
	arrival.unhappy_response_override = response
	arrival.remake_patience_override = patience
	var schedule := CustomerSchedule.new()
	schedule.id = &"response_test"
	schedule.mode = CustomerSchedule.Mode.AUTHORED
	schedule.arrivals.append(arrival)
	var day := DayConfig.new()
	day.customer_schedule = schedule
	check(queue.start(day, 68, StringName("response_%s" % sequence)), "Authored response starts in the live queue")
	queue.advance(0.0)
	return queue.get_active_customers()[0]


func no_payment(label: String) -> void:
	check(finance.cash_on_hand == 100 and finance.transaction_log.is_empty(), label + ": no cash or transaction")
	check(payments.get_pending_count() == 0 and cues.is_empty() and sounds.is_empty(), label + ": no pending payment, coins or sound")


func retry_cup(patience: int) -> void:
	await setup()
	var actor := response_order(CustomerDef.UnhappyResponse.REFUSE_RETRY, patience)
	var order := actor.order
	queue.advance(15.0)
	var cup: Cup = screen.get_cups()[0]
	fill(cup, &"water", &"water", 80.0)
	var parent := cup.get_parent()
	var transform := cup.transform
	var stage: StringName = cup.get_ingredient_stage()
	var original_stock := stock.quantities
	await take_cup(cup)
	var payload := controller.current_payload
	await release_at(actor)
	queue.advance(0.0)
	check(service.get_records().size() == 1 and order.get_results().size() == 1, "One refusal keeps one factual attempt")
	var record := service.get_records()[0]
	check(record.result.response == &"refuse_retry" and record.result.bad_review and not record.result.accepted, "Wrong contents produce the authored unhappy retry")
	check(record.returned_cup_id == cup.get_instance_id() and record.served_cup_id == 0, "Returned cup retains its exact identity without entering served custody")
	check(cup.get_parent() == parent and cup.transform.is_equal_approx(transform), "The same cup returns to its reserved original position")
	check(cup.volume_ml == 250.0 and cup.get_ingredient_stage() == stage and cup.assigned_order_id.is_empty(), "Return preserves contents and vessel lifecycle")
	check((cup.get_node("PlacementHandle") as TablePlaceable).surface.is_registered(cup), "Returned footprint stays registered")
	check(not order.closed and not order.fulfilled and actor.is_serve_enabled(), "Retry leaves the same order and customer available")
	check(screen.customer_order_overlay.get_bubble_for(actor).visible, "Retry keeps the original request visible beside the unhappy reaction")
	check(stock.quantities == original_stock, "Refusing a prepared cup neither refunds nor consumes ingredients")
	no_payment("Refused cup")
	var remaining: float = queue.get_active_entries()[0].patience_remaining
	check(is_equal_approx(remaining, 180.0 if patience == CustomerDef.RemakePatience.RESET else 165.0), "Designer policy chooses continued or reset remake patience")
	queue.advance(5.0)
	service._publish_committed(record.handoff_id)
	await frames()
	queue.advance(0.0)
	check(is_equal_approx(queue.get_active_entries()[0].patience_remaining, remaining - 5.0), "Replaying presentation cannot reset patience again")
	check(not service.try_handoff(service.get_drop_targets()[0] as CustomerServiceZone, payload), "Reusing the old gesture cannot duplicate refusal history")
	await take_cup(cup)
	await release_at(actor)
	queue.advance(0.0)
	check(order.get_results().size() == 2 and service.get_records().size() == 2, "A new gesture can retry the same cup without closing the order")
	no_payment("Repeated refused cup")
	await capture("01-retry-cup")
	check(cup.discard_contents() == 250.0, "Player can empty the returned cup for a remake")
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	await assert_payment(order, 100, false)
	check(order.fulfilled and order.closed and order.get_results().size() == 3, "Correct remake completes that same order once after two refused attempts")
	check(service.get_served_cup(order.order_id) == cup, "Only the accepted remake transfers the original cup into served custody")
	check(not order.get_results()[0].accepted and order.get_results()[0].bad_review, "Later acceptance does not erase previous dissatisfied attempt facts")


func leave_cup() -> void:
	await setup()
	var actor := response_order(CustomerDef.UnhappyResponse.REFUSE_LEAVE)
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	fill(cup, &"black_tea", &"ready", 20.0)
	var parent := cup.get_parent()
	var transform := cup.transform
	await take_cup(cup)
	await release_at(actor)
	check(order.closed and not order.fulfilled and not actor.is_serve_enabled(), "Unpaid departure closes the refused order immediately")
	check(cup.get_parent() == parent and cup.transform.is_equal_approx(transform) and cup.volume_ml == 250.0, "A departing customer also returns the same filled cup")
	check(service.get_served_cup(order.order_id) == null and cup.assigned_order_id.is_empty(), "Refused departure never claims served-cup custody")
	no_payment("Refused departure")
	await capture("02-leave-unpaid")
	queue.advance(0.0)
	check(queue.get_active_entries()[0].phase == &"refused_reaction", "Brief refusal reaction reserves the customer's place")
	queue.advance(1.0)
	await frames()
	check(queue.get_active_customers().is_empty(), "Customer visibly departs without completing the order or receiving payment")
	check(cup.is_inside_tree() and cup.visible and cup.volume_ml == 250.0, "Returned vessel survives customer removal")
	no_payment("After unpaid departure")


func refused_snacks() -> void:
	for export_view in [&"hanging", &"peek", &"full"]:
		await setup()
		var actor := response_order(CustomerDef.UnhappyResponse.REFUSE_RETRY, 0, &"ready_banana")
		var order := actor.order
		var before := stock.remaining(&"biscuits")
		if export_view == &"hanging":
			check(await take_snack(&"biscuits"), "Pick an actual wrong hanging snack")
		else:
			check(screen.khata_modal.open_peek() if export_view == &"peek" else screen.khata_modal.open(), "Open pantry for refused-snack export")
			await settle_book(screen.khata_modal)
			screen.khata_modal.select_page(0)
			await settle_book(screen.khata_modal)
			var point: Vector2 = screen.khata_modal.inventory_item_screen_rect(&"biscuits").get_center()
			if DisplayServer.get_name() == "headless":
				check(screen.khata_modal.begin_inventory_export(&"biscuits", point), "Reserve an actual pantry snack")
			else:
				await mouse(point, true)
				check(controller.is_modal_export_active(), "Actual pantry press reserves the snack")
		var portion := controller.current_payload.metadata.portion as IngredientPortion
		await release_at(actor)
		check(stock.remaining(&"biscuits") == before and portion.finished, "Refused untouched snack releases its reservation without consuming stock")
		check(not order.closed and order.get_results().size() == 1 and not controller.is_dragging(), "Refused snack ends the gesture but preserves the pending order")
		no_payment("Refused " + String(export_view) + " snack")
		await capture("03-snack-" + String(export_view))
		if export_view != &"hanging":
			screen.khata_modal.close()
			await settle_book(screen.khata_modal)
			controller.set_mode(InteractionController.MODE_INTERACT)
		check(await take_snack(&"banana"), "Take the requested snack after a refusal")
		await release_at(actor)
		await assert_payment(order, 100, false)
		check(stock.remaining(&"biscuits") == before, "Accepting the corrected snack does not later consume the refused one")


func retirement_and_timeout() -> void:
	await setup()
	var actor := response_order(CustomerDef.UnhappyResponse.REFUSE_RETRY)
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	fill(cup, &"water", &"water")
	await take_cup(cup)
	controller.release_drop(point_for(actor))
	queue.stop()
	await frames()
	check(service.get_records().size() == 1 and not order.closed and cup.is_inside_tree() and cup.visible, "Removing a customer before deferred presentation retains the refused attempt and cup")
	no_payment("Removed refusal target")
	actor = response_order(CustomerDef.UnhappyResponse.REFUSE_RETRY)
	await take_cup(cup)
	await release_at(actor)
	queue.advance(181.0)
	await frames()
	check(queue.get_active_entries()[0].phase == &"timeout_reaction", "Waiting for a remake can still run out of patience")
	no_payment("Remake timeout")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	await retry_cup(CustomerDef.RemakePatience.CONTINUE)
	await retry_cup(CustomerDef.RemakePatience.RESET)
	await leave_cup()
	await refused_snacks()
	await retirement_and_timeout()
	if is_instance_valid(screen): screen.queue_free()
	await frames()
	await create_timer(0.35).timeout
	print("CUSTOMER_REFUSAL_HANDOFF: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
