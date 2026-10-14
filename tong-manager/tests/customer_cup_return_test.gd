extends "res://tests/customer_handoff_test.gd"
## Focused lifecycle tests. Transfer geometry has a deliberate test double;
## production table/tray/bucket placement is verified by the integration suite.

class TransferFixture extends Node:
	var available := false
	var held := false
	var attempts := 0
	var holder: Node2D
	var cup: Cup
	var validate_callback: Callable
	var commit_callback: Callable
	func is_transferring(value: Cup) -> bool:
		return held and cup == value
	func try_place_on_free_surface(value: Cup) -> bool:
		attempts += 1
		if not available or held: return false
		value.reparent(holder, true)
		value.process_mode = Node.PROCESS_MODE_INHERIT
		value.show()
		return true
	func begin_transfer(value: Cup, _point: Vector2, _source: Node, validate: Callable, commit: Callable) -> bool:
		if held or not validate.call(value): return false
		cup = value
		validate_callback = validate
		commit_callback = commit
		held = true
		return true
	func complete() -> bool:
		if not held or not validate_callback.call(cup): return false
		cup.reparent(holder, true)
		cup.show()
		cup.process_mode = Node.PROCESS_MODE_INHERIT
		commit_callback.call(cup)
		held = false
		return true
	func cancel() -> void:
		held = false

var returns: CustomerCupReturns
var transfer: TransferFixture
var finance: FinanceState


func fixture() -> void:
	await setup()
	finance = root.get_node("GameState").finance
	returns = service.cup_returns as CustomerCupReturns
	if returns == null:
		returns = CustomerCupReturns.new()
		screen.add_child(returns)
	returns.set_process(false)
	returns.config = CupReturnConfig.new()
	transfer = TransferFixture.new()
	screen.add_child(transfer)
	transfer.holder = Node2D.new()
	screen.add_child(transfer.holder)
	returns.configure(screen, controller, queue, service, transfer)


func accept_cup(actor: Customer) -> Cup:
	var cup: Cup = screen.get_cups()[0]
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	return cup


func lifecycle() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var before_stock := stock.quantities
	var cup := await accept_cup(actor)
	var receipt := service.get_records()[0]
	check(order.fulfilled and service.get_served_cup(order.order_id) == cup, "Accepted drink keeps the original cup authority")
	check(not service.is_payment_due(receipt) and finance.transaction_log.is_empty(), "Accepted drink cannot pay before cup return")
	check(not screen.customer_payments.enqueue_accepted(service, receipt, Vector2.ZERO), "Direct payment enqueue cannot bypass return timing")
	queue.advance(200.0)
	check(queue.get_active_customers().has(actor) and queue.get_active_entries()[0].phase == &"cup_return", "Closed order retains its queue slot without patience expiry")
	returns.advance(7.0)
	check(cup.state == Cup.CupState.SERVED and cup.volume_ml == 250.0 and not cup.visible, "Drink remains intact during its copied drinking duration")
	returns.advance(1.0)
	check(cup.state == Cup.CupState.DIRTY and not cup.has_contents() and cup.assigned_order_id == order.order_id, "Consumption empties and dirties the same cup without clearing order identity")
	check(cup.visible and actor.get_presentation_snapshot().cup_return_offered, "Customer visibly offers the original dirty cup")
	check(returns.get_dirty_return_cup(order.order_id) == cup, "Collection getter exposes that exact identity")
	check(not cup.finish_consumption(), "Consumption cannot be repeated on an already dirty cup")
	returns.advance(8.0)
	check(transfer.attempts == 1 and returns.get_entries()[0].phase == &"waiting_for_space", "Expired return timer attempts free placement once")
	returns.advance(0.1)
	check(transfer.attempts == 1, "Full-surface retries are throttled")
	queue.advance(10000.0)
	check(queue.get_active_customers().has(actor) and finance.transaction_log.is_empty(), "Full surface preserves cup/customer without payment or extra timeout")
	var old_basis: Transform2D = screen.world_root.global_transform.affine_inverse() * cup.global_transform
	screen.world_root.scale *= 0.8
	returns.advance(0.0)
	var resized_basis: Transform2D = screen.world_root.global_transform.affine_inverse() * cup.global_transform
	check(old_basis.x.is_equal_approx(resized_basis.x) and old_basis.y.is_equal_approx(resized_basis.y), "Resize preserves physical cup basis independently of customer scale")
	transfer.available = true
	returns.advance(0.4)
	await frames()
	check(cup.get_parent() == transfer.holder and cup.state == Cup.CupState.DIRTY, "Successful automatic placement retains the same empty dirty cup")
	check(service.get_served_cup(order.order_id) == null and service.is_payment_due(receipt), "Committed destination retires service custody and authorizes payment")
	check(finance.transaction_log.size() == 1 and finance.cash_on_hand == 100 + order.get_request().price, "Return pays the original quote exactly once")
	check(queue.get_active_customers().is_empty(), "Customer departs only after return commit")
	returns.advance(100.0)
	check(not screen.customer_payments.enqueue_accepted(service, receipt, Vector2.ZERO), "Returned receipt replay cannot pay twice")
	check(stock.quantities == before_stock, "Drinking/return do not refund or debit ingredient stock")
	var snapshot := returns.get_entries()
	snapshot[0].phase = &"altered"
	check(returns.get_entries()[0].phase == &"returned", "Return snapshots are detached")


func manual_and_cancel() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup := await accept_cup(actor)
	returns.advance(8.0)
	var point := returns.get_return_pick_point(order.order_id)
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(not returns.begin_return(order.order_id, point), "Customer collection is Use-only")
	controller.set_mode(InteractionController.MODE_INTERACT)
	check(returns.begin_return(order.order_id, point), "Use begins a source-owned dirty-cup transfer")
	returns.advance(100.0)
	check(transfer.attempts == 0 and service.get_served_cup(order.order_id) == cup, "Automatic return never competes with a held transfer")
	transfer.cancel()
	check(returns.get_dirty_return_cup(order.order_id) == cup and finance.transaction_log.is_empty(), "Cancelled collection preserves source cup and unpaid receipt")
	check(returns.begin_return(order.order_id, point) and transfer.complete(), "A new collection commits the same cup to a destination")
	await frames()
	check(finance.transaction_log.size() == 1 and service.get_served_cup(order.order_id) == null, "Manual return also authorizes exactly one payment")
	check(not returns.begin_return(order.order_id, point), "Returned cup cannot be taken from the customer again")


func removed_customer() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup := await accept_cup(actor)
	queue.reset()
	await frames()
	check(is_instance_valid(cup) and cup.is_inside_tree(), "Queue reset cannot destroy a service-owned cup")
	returns.advance(8.0)
	returns.advance(8.0)
	check(cup.state == Cup.CupState.DIRTY and finance.transaction_log.is_empty(), "Removed customer still preserves unpaid dirty custody while surface is full")
	transfer.available = true
	returns.advance(0.4)
	await frames()
	check(cup.get_parent() == transfer.holder and service.get_served_cup(order.order_id) == null, "Orphaned custody recovers when valid space becomes available")
	check(finance.transaction_log.size() == 1, "Removed presentation does not lose or duplicate the delayed payment")


func snacks() -> void:
	await fixture()
	var actor := start_order(&"ready_banana")
	check(await take_snack(&"banana"), "Ready snack reserves real shared stock")
	await release_at(actor)
	check(finance.transaction_log.size() == 1 and returns.get_entries().is_empty(), "Accepted snack still pays at acceptance with no cup-return phase")


func delayed_ledger_replacement(restore_binding := false) -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup := await accept_cup(actor)
	var receipt: Dictionary = service.get_records()[0]
	var payments: CustomerPayments = screen.customer_payments
	var captured_binding := payments.get_binding_snapshot()
	var replacement := FinanceState.new()
	for _index in finance.generation: replacement.reset(100)
	check(replacement.generation == finance.generation, "Replacement fixture deliberately shares the original ledger generation")
	payments.finance = replacement
	if restore_binding: payments.finance = finance
	check(payments.get_binding_snapshot() != captured_binding, "Changing payment authority invalidates a handoff binding, including away and back")
	transfer.available = true
	returns.advance(16.0)
	await frames()
	check(cup.get_parent() == transfer.holder and service.is_payment_due(receipt), "Ledger replacement does not prevent physical cup return")
	check(finance.transaction_log.is_empty() and replacement.transaction_log.is_empty(), "Delayed receipt cannot credit a replacement or restored ledger binding")
	check(not payments.enqueue_accepted(service, receipt, Vector2.ZERO), "Returned old receipt cannot be replayed into a different payment binding")
	check(service.get_served_cup(order.order_id) == null, "Replacement leaves the successfully returned cup out of service custody")
	payments.finance = finance


func hidden_consumption_callback() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup := await accept_cup(actor)
	cup.contents_changed.connect(func(_base: StringName, _items: Array[StringName], _order: StringName):
		screen.hide(), CONNECT_ONE_SHOT)
	returns.advance(8.0)
	check(not screen.visible and cup.state == Cup.CupState.DIRTY, "Consumption observer can hide the screen after dirty state commits")
	check(cup.visible and actor.get_presentation_snapshot().cup_return_offered, "Hidden screen still completes the offered-cup presentation state")
	check(not returns.begin_return(order.order_id, returns.get_return_pick_point(order.order_id)), "Hidden screen never permits a new collection gesture")
	screen.show()
	await frames()
	check(cup.is_visible_in_tree() and returns.get_dirty_return_cup(order.order_id) == cup, "Showing again exposes the same dirty cup instead of stranding it")
	check(returns.begin_return(order.order_id, returns.get_return_pick_point(order.order_id)) and transfer.complete(), "Resumed collection commits normally")
	await frames()
	check(queue.get_active_customers().is_empty() and finance.transaction_log.size() == 1, "Resumed collection releases the slot and pays once")
	returns.advance(100.0)
	await frames()
	check(finance.transaction_log.size() == 1, "Consumption visibility changes cannot replay payment")


func hidden_return_callback() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup := await accept_cup(actor)
	returns.advance(8.0)
	check(returns.begin_return(order.order_id, returns.get_return_pick_point(order.order_id)), "Begin collection before a synchronous destination observer")
	var commit: Callable = transfer.commit_callback
	transfer.commit_callback = func(value: Cup):
		commit.call(value)
		screen.hide()
	check(transfer.complete() and not screen.visible, "Destination callback can hide the screen after source retirement")
	await frames()
	check(returns.get_entries()[0].phase == &"returned" and cup.get_parent() == transfer.holder, "Hidden callback preserves committed destination custody")
	check(queue.get_active_customers().has(actor), "Hidden customer retains a resumable departure until its presentation can run")
	check(finance.transaction_log.size() == 1, "Deferred return payment survives temporary screen hiding")
	screen.show()
	await frames()
	check(queue.get_active_customers().is_empty(), "Showing again resumes departure and releases the held queue slot")
	returns.advance(100.0)
	await frames()
	check(cup.is_visible_in_tree() and finance.transaction_log.size() == 1, "Showing the returned cup cannot replay departure or payment")


func run() -> void:
	await frames()
	await lifecycle()
	await manual_and_cancel()
	await removed_customer()
	await snacks()
	await delayed_ledger_replacement()
	await delayed_ledger_replacement(true)
	await hidden_consumption_callback()
	await hidden_return_callback()
	if is_instance_valid(screen): screen.queue_free()
	await frames()
	print("CUP_RETURN_LIFECYCLE: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
