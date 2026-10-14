extends "res://tests/customer_handoff_test.gd"
## Real serving inputs drive the shared ledger and disposable payment cues.

var finance: FinanceState
var payments: CustomerPayments
var cues: Array[StringName] = []
var sounds: Array[StringName] = []


func setup() -> void:
	await super.setup()
	finance = root.get_node("GameState").finance
	payments = screen.customer_payments
	cues.clear()
	sounds.clear()
	watch_feedback()
	check(finance.cash_on_hand == 100 and finance.transaction_log.is_empty(), "Explicit fixture reset starts one clean ledger")
	check(screen.get_node("HUDLayer/RootUI").cash_label.text == "৳ 100", "HUD reads configured starting cash, not a sample balance")


func watch_feedback() -> void:
	screen.payment_feedback.feedback_started.connect(func(id: StringName): cues.append(id))
	screen.payment_feedback.sound_requested.connect(func(id: StringName): sounds.append(id))


func assert_payment(order: OrderState, before: int, expected_bad: bool) -> Dictionary:
	var record := finance.get_transaction(StringName("order:" + String(order.order_id)))
	check(not record.is_empty(), "Accepted order has one ledger transaction")
	if record.is_empty(): return {}
	var sound_deadline := Time.get_ticks_msec() + 1500
	while sounds.count(record.source_id) < 2 and Time.get_ticks_msec() < sound_deadline:
		await process_frame
	check(record.amount == order.get_request().price, "Payment uses the saved normal quote")
	check(finance.cash_on_hand == before + record.amount, "Payment increases shared cash once")
	check(record.metadata.order_id == order.order_id and record.metadata.request_id == order.request_id, "Receipt retains order and request identity")
	check(record.metadata.bad_review == expected_bad, "Financial history retains the accepted review outcome without a penalty")
	check(finance.get_transaction(StringName("handoff:" + String(record.metadata.handoff_id))) == record, "Handoff and order resolve to the same transaction")
	check(screen.get_node("HUDLayer/RootUI").cash_label.text == "৳ %d" % finance.cash_on_hand, "Live HUD and ledger agree")
	check(cues.count(record.source_id) == 1 and sounds.count(record.source_id) == 2, "A new payment produces one coin cue and one sound per coin")
	return record


func correct_and_replays() -> void:
	await setup()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	var transaction := await assert_payment(order, 100, false)
	var receipt := service.get_records()[0]
	var original := finance.get_snapshot()
	check(not payments.enqueue_accepted(service, receipt, Vector2.ZERO), "Direct receipt replay cannot pay twice")
	service.service_accepted.emit(receipt)
	payments.payment_recorded.emit(transaction, screen.get_instance_id(), Vector2(600, 400))
	var edited: Dictionary = receipt.duplicate(true)
	edited.price += 500
	edited.request.price += 500
	check(not payments.enqueue_accepted(service, edited, Vector2.ZERO), "Edited quote is not a committed receipt")
	edited = receipt.duplicate(true)
	edited.handoff_id = &"forged_handoff"
	check(not payments.enqueue_accepted(service, edited, Vector2.ZERO), "Rewritten handoff identity is not accepted")
	await frames()
	check(finance.get_snapshot() == original and cues.size() == 1 and sounds.size() == 2, "Signal replay and conflicting receipts change neither money nor cues")
	check(not screen.get_cups().has(cup) and service.get_served_cup(order.order_id) == cup, "Payment preserves the accepted cup custody")
	await capture("01-paid-tea")


func accepted_mistakes() -> void:
	for sample in [[&"water", &"water", 80.0, 250.0], [&"black_tea", &"underbrewed", 80.0, 250.0],
		[&"black_tea", &"oversteeped", 80.0, 250.0], [&"black_tea", &"ready", 20.0, 250.0],
		[&"black_tea", &"ready", 80.0, 50.0]]:
		await setup()
		var actor := start_order(&"tea_cha_no_sugar")
		var order := actor.order
		var cup: Cup = screen.get_cups()[0]
		fill(cup, sample[0], sample[1], sample[2], sample[3])
		await take_cup(cup)
		await release_at(actor)
		await assert_payment(order, 100, true)
		check(finance.day_expenses == 0 and finance.transaction_log.size() == 1, "Poor quality has no invented fine or refund")
	await capture("02-cold-paid")
	await setup()
	var actor := start_order(&"ready_banana")
	var order := actor.order
	var stock_before := stock.remaining(&"biscuits")
	check(await take_snack(&"biscuits"), "Take a real wrong snack")
	await release_at(actor)
	await assert_payment(order, 100, true)
	check(stock.remaining(&"biscuits") == stock_before - 1, "Wrong snack still consumes exactly one real piece")


func saved_quote_and_concurrent() -> void:
	await setup()
	var first := start_order(&"ready_banana", &"ready_biscuits")
	queue.advance(1.0)
	var second := queue.get_active_customers()[1]
	var first_order := first.order
	var second_order := second.order
	var banana: ItemDef = root.get_node("Catalog").get_item(&"banana")
	var saved_price := banana.sell_price
	banana.sell_price += 100
	check(await take_snack(&"banana"), "Take real banana after catalog price edit")
	await release_at(first)
	banana.sell_price = saved_price
	await assert_payment(first_order, 100, false)
	var before := finance.cash_on_hand
	check(await take_snack(&"biscuits"), "Take second customer's actual snack")
	await release_at(second)
	await assert_payment(second_order, before, false)
	check(finance.transaction_log.size() == 2 and cues.size() == 2, "Two customers generate distinct once-only payments")
	check(finance.day_income == first_order.get_request().price + second_order.get_request().price, "Totals use captured quotes for both customers")
	await capture("03-two-payments")


func rejected_cancelled_timeout() -> void:
	await setup()
	var actor := start_order(&"ready_banana")
	var original := finance.get_snapshot()
	var stock_before := stock.remaining(&"banana")
	var cup: Cup = screen.get_cups()[0]
	await take_cup(cup)
	await release_at(actor)
	check(await take_snack(&"banana"), "Reserve snack before cancellation")
	controller.cancel_drag()
	queue.advance(181.0)
	await frames()
	check(finance.get_snapshot() == original and cues.is_empty() and sounds.is_empty(), "Empty/cancelled/timeout attempts pay nothing and play no cue")
	check(stock.remaining(&"banana") == stock_before, "Cancellation returns the reserved stock")


func pantry_and_preservation() -> void:
	await setup()
	for peek in [true, false]:
		var actor := start_order(&"ready_banana")
		var order := actor.order
		var before := finance.cash_on_hand
		check(screen.khata_modal.open_peek() if peek else screen.khata_modal.open(), "Open pantry without pausing or resetting money")
		await settle_book(screen.khata_modal)
		screen.khata_modal.select_page(0)
		await settle_book(screen.khata_modal)
		var cell: Vector2 = screen.khata_modal.inventory_item_screen_rect(&"banana").get_center()
		if DisplayServer.get_name() == "headless":
			check(screen.khata_modal.begin_inventory_export(&"banana", cell), "Export a real pantry serving")
		else:
			await mouse(cell, true)
			check(controller.is_modal_export_active(), "Actual pantry cell begins a serving export")
		await release_at(actor)
		await assert_payment(order, before, false)
		screen.khata_modal.close()
		await settle_book(screen.khata_modal)
		controller.set_mode(InteractionController.MODE_INTERACT)
	var saved := finance.get_snapshot()
	start_order(&"ready_biscuits")
	check(finance.get_snapshot() == saved, "Restarting a customer schedule preserves money and history")
	root.remove_child(screen)
	await frames()
	root.add_child(screen)
	await frames()
	check(finance.get_snapshot() == saved and screen.get_node("HUDLayer/RootUI").cash_label.text == "৳ %d" % finance.cash_on_hand, "Same-screen reentry rebinds HUD without resetting or paying again")
	screen.queue_free()
	await frames()
	screen = TONG.instantiate()
	screen.customer_queue_auto_start = false
	root.add_child(screen)
	await frames()
	check(root.get_node("GameState").finance == finance and finance.get_snapshot() == saved, "Full scene recreation preserves the run ledger identity/history")
	check(screen.get_node("HUDLayer/RootUI").cash_label.text == "৳ %d" % finance.cash_on_hand and screen.payment_feedback.get_active_count() == 0, "Recreated HUD reads current money without replaying old cues")


func retirement_and_reset() -> void:
	await setup()
	var actor := start_order(&"ready_banana")
	var quote: int = actor.order.get_request().price
	check(await take_snack(&"banana"), "Take portion before scene retirement")
	var old_stock := stock.remaining(&"banana")
	var retiring_screen := screen
	var retire := func():
		if stock.remaining(&"banana") < old_stock and retiring_screen.is_inside_tree():
			root.remove_child(retiring_screen)
			retiring_screen.queue_free()
	stock.changed.connect(retire)
	controller.release_drop(point_for(actor))
	await frames()
	stock.changed.disconnect(retire)
	check(finance.cash_on_hand == 100 + quote and finance.transaction_log.size() == 1, "Accepted payment survives source scene retirement during stock notification")
	check(cues.is_empty(), "Retired scene receives no stale presentation")
	await setup()
	actor = start_order(&"ready_banana")
	check(await take_snack(&"banana"), "Take portion before explicit run reset")
	controller.release_drop(point_for(actor))
	var old_receipt := service.get_records()[0]
	check(payments.get_pending_count() == 1, "Committed serving queues a receipt before deferred presentation")
	check(root.get_node("GameState").reset_demo_state(), "Explicit new-demo reset succeeds")
	await frames()
	check(finance.cash_on_hand == 100 and finance.transaction_log.is_empty() and cues.is_empty(), "Previous-generation queued sale cannot enter a reset ledger")
	check(not payments.enqueue_accepted(service, old_receipt, Vector2.ZERO), "Old authoritative receipt cannot be replayed after reset")
	actor = start_order(&"ready_banana")
	var order := actor.order
	check(await take_snack(&"banana"), "Same scene can serve a new-run order")
	await release_at(actor)
	await assert_payment(order, 100, false)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	await correct_and_replays()
	await accepted_mistakes()
	await saved_quote_and_concurrent()
	await rejected_cancelled_timeout()
	await pantry_and_preservation()
	await retirement_and_reset()
	await ledger_replacement()
	await ledger_replacement(true)
	if is_instance_valid(screen): screen.queue_free()
	await frames()
	await create_timer(0.35).timeout
	print("CUSTOMER_PAYMENT: %s checks; %s failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func ledger_replacement(restore_binding := false) -> void:
	await setup()
	var actor := start_order(&"ready_banana", &"ready_biscuits")
	queue.advance(0.0)
	var second := queue.get_active_customers()[1]
	var first_quote: int = actor.order.get_request().price
	check(source(&"banana").begin_portion(Vector2(900, 500)), "Queue first receipt without yielding")
	controller.release_drop(point_for(actor))
	check(source(&"biscuits").begin_portion(Vector2(1000, 500)), "Queue second receipt without yielding")
	controller.release_drop(point_for(second))
	check(payments.get_pending_count() == 2, "Two accepted sales wait in the same deferred batch")
	var replacement := FinanceState.new()
	replacement.reset(300)
	var rebind := func(_record: Dictionary):
		payments.configure(replacement)
		if restore_binding: payments.configure(finance)
	finance.transaction_recorded.connect(rebind, CONNECT_ONE_SHOT)
	await frames()
	check(finance.cash_on_hand == 100 + first_quote, "First sale commits to its original ledger")
	check(replacement.cash_on_hand == 300 and replacement.transaction_log.is_empty(), "Remaining old receipts cannot credit a replacement ledger with the same generation")
	check(cues.is_empty(), "A replaced finance binding cannot emit a stale payment cue")
	payments.configure(finance)
