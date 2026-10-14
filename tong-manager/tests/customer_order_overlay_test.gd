extends SceneTree
## Live queue order cues. Scenario results below are fixtures, not handoff rules.

const PREVIEW := preload("res://scenes/development/CustomerQueuePreview.tscn")
const REQUESTS: Array[StringName] = [&"tea_cha_no_sugar", &"tea_cha", &"tea_dudh_cha_no_sugar",
	&"tea_dudh_cha", &"ready_banana", &"ready_biscuits"]

class WorldInputProbe extends Node:
	var presses := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			presses += 1

var checks := 0
var failures: Array[String] = []
var rendered := false
var capture_dir := ""
var sequence := 0
var view: Node
var screen: Node2D
var queue: CustomerQueueManager
var overlay: CustomerOrderOverlay
var controller: InteractionController
var catalog: Node
var game_state: Node
var supplies_before: Dictionary
var cups_before: Array[Dictionary]
var cash_before := ""


func _init() -> void:
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


func wait_until(predicate: Callable, label: String, timeout := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed := bool(predicate.call())
	check(passed, label)
	return passed


func capture(label: String) -> void:
	if not rendered or capture_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK,
		"Saved order review: " + label)


func move_pointer(point: Vector2) -> void:
	if rendered: root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await frames()


func click_at(point: Vector2) -> void:
	await move_pointer(point)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await frames()


func tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func supplies() -> Dictionary:
	var stock: InventoryState = game_state.inventory
	var water: DailyWaterSupply = game_state.water_supply
	return {"stock_id": stock.get_instance_id(), "stock": stock.quantities,
		"water_id": water.get_instance_id(), "water": water.remaining_ml}


func cup_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cup: Cup in screen.get_cups():
		result.append({"id": cup.get_instance_id(), "state": cup.state, "volume": cup.volume_ml,
			"order": cup.assigned_order_id, "ingredients": cup.get_ingredient_amounts()})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return result


func make_day(request_ids: Array[StringName], same_profile := false) -> DayConfig:
	var day := (load("res://data/balance/demo_day_1.tres") as DayConfig).duplicate(false) as DayConfig
	var schedule := CustomerSchedule.new()
	sequence += 1
	schedule.id = StringName("order_overlay_fixture_%d" % sequence)
	schedule.mode = CustomerSchedule.Mode.AUTHORED
	schedule.max_active = 2
	schedule.timeout_reaction_seconds = 0.8
	for index in request_ids.size():
		var entry := CustomerArrivalDef.new()
		entry.id = StringName("visit_%d" % index)
		entry.due_seconds = 0.0
		entry.patience_override = 120.0
		entry.customer = catalog.get_customer(&"customer_a" if same_profile or index % 2 == 0 else &"customer_b") as CustomerDef
		entry.request = catalog.get_order_request(request_ids[index]) as OrderRequestDef
		schedule.arrivals.append(entry)
	day.customer_schedule = schedule
	return day


func start_pair(request_ids: Array[StringName], same_profile := false, instant := true) -> Array[Customer]:
	queue.reduced_motion = instant
	check(screen.start_customer_queue(make_day(request_ids, same_profile), 65), "Review schedule starts through production Tong binding")
	queue.set_process(false)
	queue.advance(0.01)
	queue.advance(0.01)
	await frames(3)
	overlay.refresh()
	var actors := queue.get_active_customers()
	check(actors.size() == request_ids.size(), "Every scheduled active request has its own live customer")
	return actors


func assert_passive(node: Node) -> void:
	if node is Control:
		var control := node as Control
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.focus_mode == Control.FOCUS_NONE,
			"Order presentation cannot steal mouse or focus: " + String(control.name))
	for child in node.get_children(): assert_passive(child)


func check_layout(label: String, expected_visible := -1) -> void:
	overlay.refresh()
	var visible: Array[Rect2] = []
	var safe := Rect2(Vector2.ONE * overlay.screen_margin, overlay.size - Vector2.ONE * overlay.screen_margin * 2.0)
	var exclusions := overlay.get_exclusion_rects()
	for actor in queue.get_active_customers():
		var bubble := overlay.get_bubble_for(actor)
		if bubble == null or not bubble.is_visible_in_tree(): continue
		var bounds := Rect2(bubble.position, bubble.size)
		check(safe.encloses(bounds), label + ": bubble fits viewport in overlay coordinates")
		var clear := true
		for obstacle in exclusions:
			if bounds.intersects(obstacle): clear = false
		check(clear, label + ": fixed HUD/visible notebook/review controls stay uncovered")
		for previous in visible:
			check(not bounds.intersects(previous), label + ": simultaneous request groups do not overlap")
		visible.append(bounds)
		var projected := overlay.get_global_transform_with_canvas().affine_inverse() * actor.order_anchor.get_global_transform_with_canvas().origin
		check(overlay.get_anchor_position(actor).distance_to(projected) < 0.01,
			label + ": anchor follows the customer's actual canvas transform")
		for token_rect in bubble.get_token_rects():
			check(Rect2(Vector2.ZERO, bubble.size).encloses(token_rect), label + ": all requested tokens fit the bubble group")
	if expected_visible >= 0:
		check(visible.size() == expected_visible, label + ": all eligible requests remain visible")


func check_request(actor: Customer) -> String:
	var order := actor.order
	var bubble := overlay.get_bubble_for(actor)
	check(bubble != null and bubble.is_visible_in_tree(), "Eligible live order has a visible bubble")
	if bubble == null: return ""
	var display := bubble.get_display_snapshot()
	var request := order.get_request()
	check(bubble.order == order and display.order_id == order.order_id and display.request_id == order.request_id,
		"Bubble binds its own authoritative order and request identities")
	check(display.valid and display.request_kind == request.kind, "Presentation retains tea versus ready-item identity")
	var tokens: Array = display.tokens
	var expected_count: int = 1 + (request.cup_portion_counts.size() if request.kind == &"tea" else 0)
	check(tokens.size() == expected_count, "Request shows one vessel/item and precisely its cup additions")
	if request.kind == &"tea":
		check(tokens[0].kind == &"tea" and tokens[0].unit == &"cup" and tokens[0].amount == 1,
			"Tea begins with one cup, not a batch teabag count")
		check(tokens[0].icon == CustomerOrderBubble.CUP_ICON and tokens[0].identity_icon == request.icon,
			"Tea uses the cup and authoritative shared liquid identity artwork")
		var found: Dictionary = {}
		for token: Dictionary in tokens.slice(1):
			found[token.item_id] = token.amount
			var item: ItemDef = catalog.get_item(token.item_id)
			check(token.kind == &"addition" and item != null and token.icon == item.icon,
				"Requested cup addition uses exactly the shared pantry ItemDef icon")
			check(token.unit == request.cup_portion_units[token.item_id] and token.amount_text == str(token.amount),
				"Addition count keeps the request's abstract unit and amount")
		check(found == request.cup_portion_counts, "All and only requested cup additions are visible")
		check(not found.has(&"black_tea"), "Default tea does not imply one whole batch bag in each cup")
	else:
		var item: ItemDef = catalog.get_item(request.item_id)
		check(tokens[0].kind == &"ready_item" and tokens[0].item_id == request.item_id
			and tokens[0].icon == item.icon and tokens[0].unit == &"piece" and tokens[0].amount == 1,
			"Ready-item cue preserves exact banana/biscuit icon and one-piece identity")
	var summary := bubble.get_accessibility_summary()
	check(not summary.is_empty() and not summary.contains("ml") and not summary.contains("°"),
		"Accessible request explanation has no precision liquid or temperature readout")
	var before := bubble.get_display_snapshot()
	display.tokens.clear()
	display.request_id = &"caller_mutation"
	check(bubble.get_display_snapshot() == before and order.get_request() == request,
		"Inspecting a bubble cannot mutate its presentation or order authority")
	check(not actor.emotion_icon.visible, "Production overlay replaces the old neutral cue without duplicating it")
	assert_passive(bubble)
	return summary


func check_all_requests() -> void:
	var summaries: Dictionary = {}
	for index in range(0, REQUESTS.size(), 2):
		var actors := await start_pair([REQUESTS[index], REQUESTS[index + 1]])
		for actor in actors: summaries[check_request(actor)] = true
		check_layout("Typed pair %d" % index, 2)
		await capture("requests-%d-%d" % [index + 1, index + 2])
	check(summaries.size() == 6, "All four teas, banana and biscuits have distinguishable request explanations")
	var same := await start_pair([&"tea_cha", &"tea_cha"], true)
	if same.size() != 2: return
	check(same[0].customer_def.id == same[1].customer_def.id and same[0].order.order_id != same[1].order.order_id,
		"Repeated customer profile visits retain independent order identities")
	check(overlay.get_bubble_for(same[0]) != overlay.get_bubble_for(same[1]),
		"Repeated profiles never share a live bubble")


func check_motion_layout() -> void:
	var actors := await start_pair([&"tea_dudh_cha", &"ready_banana"], false, false)
	if actors.size() != 2: return
	for actor in actors:
		var bubble := overlay.get_bubble_for(actor)
		check(bubble != null and not bubble.visible, "Request stays hidden during the accepted walk-up")
	await wait_until(func(): return actors[0].is_serve_enabled() and actors[1].is_serve_enabled(), "Actual arrivals settle before requests appear")
	await frames()
	check_layout("Settled arrival", 2)
	await capture("two-live-orders")
	var first := actors[0]
	var original := first.transform
	var anchor_before := overlay.get_anchor_position(first)
	var bubble_before := overlay.get_bubble_for(first).position
	first.position += Vector2(35, 20)
	first.scale *= Vector2(0.94, 1.04)
	await frames()
	check(overlay.get_anchor_position(first).distance_to(anchor_before) > 5.0,
		"Anchor responds to owner movement and a nonuniform authored scale")
	check(overlay.get_bubble_for(first).position.distance_to(bubble_before) > 1.0,
		"Live bubble follows its transformed owner instead of staying at a stale screen point")
	check_layout("Moved owner", 2)
	first.transform = original
	await frames()
	var saved_size := root.size
	root.size = Vector2i(1280, 800) if saved_size != Vector2i(1280, 800) else Vector2i(1600, 900)
	await frames(5)
	check_layout("Live viewport resize", 2)
	root.size = saved_size
	await frames(5)
	check_layout("Restored viewport", 2)
	# Deliberately author a crowded head layout while preserving both queue owners.
	var second_transform := actors[1].transform
	actors[1].position = first.position + Vector2(25, 0)
	await frames()
	check_layout("Nearby customers", 2)
	actors[1].transform = second_transform
	await frames()


func check_input_and_khata() -> void:
	var actors := await start_pair([&"tea_dudh_cha", &"ready_biscuits"])
	if actors.size() != 2: return
	assert_passive(overlay)
	var bubble := overlay.get_bubble_for(actors[0])
	var point := bubble.get_global_transform_with_canvas() * (bubble.size * 0.5)
	check(not controller.is_pointer_over_ui_at(point), "A visible request bubble is not a world-input blocker")
	if rendered:
		var probe := WorldInputProbe.new()
		screen.add_child(probe)
		await click_at(point)
		check(probe.presses == 1, "A real click through the bubble reaches unhandled world input exactly once")
		probe.queue_free()
	controller.set_mode(InteractionController.MODE_INTERACT)
	var cup: Cup = screen.get_cups()[0]
	var origin := cup.global_transform
	var cup_point := cup.get_global_transform_with_canvas().origin
	await move_pointer(cup_point)
	await wait_until(func(): return not controller.is_pointer_over_ui(), "Pointer clears UI before the existing cup gesture", 1.0)
	check(cup.begin_interaction_drag(cup_point), "Live order overlay leaves the existing cup gesture available")
	controller.cancel_drag()
	check(cup.global_transform.is_equal_approx(origin), "Order overlay does not change cup cancellation")
	(view.day_picker as OptionButton).release_focus()
	await tap(KEY_K)
	var modal: KhataModal = screen.khata_modal
	check(modal.is_peeking() and not controller.is_world_input_blocked(), "K still opens nonmodal Peek with live requests")
	await wait_until(func(): return not modal.is_traveling() and not modal.book.busy, "Peek finishes its existing motion")
	check_layout("Peek open", 2)
	var peek := screen.get_node("HUDLayer/RootUI/KhataPeek") as Control
	var peek_rect := Rect2(overlay.get_global_transform_with_canvas().affine_inverse() * peek.get_global_transform_with_canvas().origin, peek.size)
	for actor in actors:
		bubble = overlay.get_bubble_for(actor)
		check(not Rect2(bubble.position, bubble.size).intersects(peek_rect), "Live request group avoids the visible Peek controls")
	await capture("peek-live-orders")
	var open_button := peek.get_node("OpenButton") as Button
	if rendered: await click_at(open_button.get_global_rect().get_center())
	else: open_button.pressed.emit()
	await frames()
	check(modal.is_open() and controller.is_world_input_blocked(), "Full notebook retains exclusive world-input ownership")
	await wait_until(func(): return not modal.is_traveling() and not modal.book.busy, "Full notebook finishes its existing motion")
	var before := queue.get_snapshot()
	queue.set_process(true)
	await create_timer(0.18).timeout
	queue.set_process(false)
	var after := queue.get_snapshot()
	check(not paused and float(after.elapsed) > float(before.elapsed)
		and float(after.active[0].patience_remaining) < float(before.active[0].patience_remaining),
		"Full notebook input ownership does not pause live order patience")
	check(overlay.get_bubble_for(actors[0]).order == actors[0].order,
		"Opening Full never replaces the order presentation authority")
	await capture("full-live-orders")
	await tap(KEY_ESCAPE)
	await wait_until(func(): return not modal.is_open() and not modal.is_traveling() and not controller.is_world_input_blocked(), "Escape returns to the unblocked stall")
	check_layout("After notebook closes", 2)


func result_for(order: OrderState, suffix: String, accepted: bool, cold := false) -> ServiceResult:
	return ServiceResult.create(StringName(String(order.order_id) + "/" + suffix), order.order_id,
		order.customer_id, order.request_kind, accepted, cold, &"" if accepted else &"wrong_fixture")


func check_reactions_and_replacement() -> void:
	var actors := await start_pair([&"tea_cha", &"ready_banana"])
	if actors.size() != 2: return
	var first := actors[0]
	var second := actors[1]
	var first_bubble := overlay.get_bubble_for(first)
	var second_bubble := overlay.get_bubble_for(second)
	var first_order := first.order
	var wrong := result_for(first_order, "wrong", false)
	check(first.apply_service_result(wrong), "Existing result seam presents a wrong-item review fixture")
	await frames()
	check(first_bubble.visible and first.emotion_icon.visible and not first_order.fulfilled,
		"Wrong reaction preserves the requested ingredients without fulfilling that order")
	check(second_bubble.visible and second_bubble.order == second.order, "Another customer's request remains unaffected")
	await capture("wrong-keeps-order")
	first.show_emotion(&"")
	await frames()
	check(first_bubble.visible and first_bubble.order == first_order, "Ending a wrong reaction restores the same unfulfilled request")
	var replacement: OrderState = catalog.create_order(&"overlay/replacement", first_order.customer_id, &"tea_dudh_cha", 0.0)
	check(first.set_order(replacement), "Customer accepts a genuinely different bound order")
	await frames()
	check(overlay.get_bubble_for(first) == first_bubble and first_bubble.order == replacement
		and first_bubble.get_display_snapshot().request_id == &"tea_dudh_cha",
		"Replacement updates this owner's group without retaining the old order")
	check(first_order.record_result(result_for(first_order, "stale_accept", true)), "Old order can independently receive its late fixture result")
	await frames()
	check(first_bubble.visible and not replacement.fulfilled and first_bubble.order == replacement,
		"Late old-order fulfillment cannot hide or fulfill the replacement")
	check(second_bubble == overlay.get_bubble_for(second) and second_bubble.visible,
		"Replacement never rebinds its neighbor")
	queue.advance(0.01)
	await frames()
	check(not is_instance_valid(first) and not is_instance_valid(first_bubble),
		"Queue retirement of a mismatched binding leaves no orphaned presentation")
	actors = await start_pair([&"tea_cha_no_sugar", &"ready_biscuits"])
	if actors.size() != 2: return
	first = actors[0]
	first_bubble = overlay.get_bubble_for(first)
	var acceptance := result_for(first.order, "external_accept", true, true)
	check(first.order.record_result(acceptance), "Authoritative fulfillment may be recorded before presentation")
	await frames()
	check(not first_bubble.visible, "Direct OrderState fulfillment hides a request without requiring a Customer callback")
	check(first.apply_service_result(acceptance), "Already recorded cold acceptance presents once through the accepted seam")
	await frames()
	check(first.emotion_icon.visible and first.get_presentation_snapshot().emotion == &"cold" and not first_bubble.visible,
		"Accepted cold feedback has precedence without reviving an active request")
	check(not first.apply_service_result(acceptance), "Overlay does not enable duplicate service feedback")
	await capture("cold-feedback-order-hidden")


func check_timeout_and_lifecycle() -> void:
	var actors := await start_pair([&"tea_cha", &"ready_banana"])
	if actors.size() != 2: return
	var first := actors[0]
	var first_bubble := overlay.get_bubble_for(first)
	first.hide()
	await frames()
	check(not first_bubble.visible, "Hidden owner has no floating request")
	first.show()
	await frames()
	check(first_bubble.visible, "Re-shown eligible owner restores its own request")
	overlay.hide()
	await frames()
	check(not first_bubble.is_visible_in_tree() and first.emotion_icon.visible, "Disabling overlay restores the actor's original neutral cue")
	overlay.show()
	await frames()
	check(first_bubble.visible and not first.emotion_icon.visible, "Re-enabling overlay restores a single request presentation")
	var retained_order := first.order
	queue.advance(121.0)
	await frames()
	check(not first_bubble.visible and first.emotion_icon.visible and first.get_presentation_snapshot().emotion == &"unhappy",
		"Timeout shows disappointment instead of a still-active order")
	check(not retained_order.fulfilled and retained_order.get_results().is_empty(), "Timeout presentation does not invent service or a bad review")
	await capture("timeout-orders-hidden")
	queue.advance(0.81)
	await frames()
	check(not is_instance_valid(first_bubble) and overlay.get_child_count() == 0,
		"Finished timeout departures dispose every bound group")
	actors = await start_pair([&"tea_dudh_cha", &"ready_biscuits"])
	if actors.size() != 2: return
	first = actors[0]
	var removed_ref: WeakRef = weakref(overlay.get_bubble_for(first))
	var parent := first.get_parent()
	parent.remove_child(first)
	await frames()
	check(removed_ref.get_ref() == null, "Detached customer loses its live overlay entry immediately")
	if is_instance_valid(first): first.queue_free()
	actors[1].queue_free()
	await frames()
	check(overlay.get_child_count() == 0, "Freed customer cannot retain an orphaned bubble")
	actors = await start_pair([&"tea_cha_no_sugar", &"ready_banana"])
	var old_bubbles: Array[WeakRef] = []
	for actor in actors: old_bubbles.append(weakref(overlay.get_bubble_for(actor)))
	view.restart_schedule()
	queue.set_process(false)
	await frames()
	for reference in old_bubbles:
		check(reference.get_ref() == null, "Schedule restart retires old visit UI identities")
	check(overlay.get_child_count() == 0, "Delayed restarted schedule starts without old request cues")
	await start_pair([&"tea_cha", &"ready_banana"])
	root.remove_child(view)
	await frames()
	check(overlay.get_child_count() == 0, "Whole scene detachment clears order presentation children")
	root.add_child(view)
	await frames()
	await start_pair([&"tea_dudh_cha_no_sugar", &"ready_biscuits"])
	check_layout("Scene re-entry", 2)
	queue.stop()
	await frames()
	check(overlay.get_child_count() == 0, "Stopped queue leaves no order groups")


func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	catalog = root.get_node("Catalog")
	game_state = root.get_node("GameState")
	view = PREVIEW.instantiate()
	root.add_child(view)
	await frames(5)
	screen = view.screen
	queue = view.queue
	controller = view.controller
	overlay = screen.customer_order_overlay
	queue.set_process(false)
	supplies_before = supplies()
	cups_before = cup_snapshot()
	cash_before = (screen.get_node("HUDLayer/RootUI/TopHud/CashPanel/CashLabel") as Label).text
	await check_all_requests()
	await check_motion_layout()
	await check_input_and_khata()
	await check_reactions_and_replacement()
	await check_timeout_and_lifecycle()
	check(supplies() == supplies_before, "Order presentation and review fixtures preserve finite inventory and water")
	check(cup_snapshot() == cups_before, "Order presentation never consumes or rewrites live cups")
	check((screen.get_node("HUDLayer/RootUI/TopHud/CashPanel/CashLabel") as Label).text == cash_before,
		"Presentation fixtures do not credit payment")
	view.queue_free()
	await frames(4)
	print("CUSTOMER_ORDER_OVERLAY: %d checks; %d failures; rendered=%s" % [checks, failures.size(), rendered])
	quit(0 if failures.is_empty() else 1)
