extends "res://tests/customer_handoff_test.gd"
## Actual TongDayScreen custody, geometry, bucket and ledger integration.
## Brew contents are a declared Cup fixture; transfers/payments are never doubles.

var returns: CustomerCupReturns
var transfers: CupTransfer
var bucket: BucketStation
var finance: FinanceState
var table: PlacementSurface
var tray: TrayStation


func fixture() -> void:
	await setup()
	returns = screen.cup_returns
	transfers = screen.cup_transfers
	bucket = screen.bucket
	finance = root.get_node("GameState").finance
	table = screen.table_surface
	tray = screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	returns.set_process(false)
	bucket.set_process(false)
	returns.config = returns.config.duplicate() as CupReturnConfig
	bucket.config = bucket.config.duplicate() as BucketConfig
	check(transfers is CupTransfer and bucket.transfers == transfers and returns.transfers == transfers,
		"Real scene shares one production transfer owner across customer, bucket and surfaces")
	check(bucket.config.capacity == 6 and is_equal_approx(bucket.config.wash_seconds, 2.4),
		"Real bucket exposes six-cup and 2.4-second editable review defaults")
	check(is_equal_approx(returns.config.drinking_seconds, 8.0) and is_equal_approx(returns.config.attention_seconds, 8.0),
		"Real return owner exposes the two eight-second review defaults")


func bucket_point() -> Vector2:
	var polygon := bucket.body_shape.polygon
	var local := Vector2.ZERO
	for vertex in polygon: local += vertex
	local /= polygon.size()
	return bucket.body_shape.get_global_transform_with_canvas() * local


func table_cup_origin() -> Vector2:
	return screen.world_root.to_global(Vector2(860.0, 900.0))


func canvas_position(world_position: Vector2) -> Vector2:
	return screen.get_canvas_transform() * world_position


func drop_bucket() -> bool:
	var cup := controller.current_drag_node as Cup
	if cup == null:
		check(false, "Bucket release has an actual held cup")
		return false
	var point := bucket_point()
	await move_pointer(point)
	controller.update_drag(point)
	check(controller.hovered_drop_zone is BucketDropZone, "Real controller prioritizes the physical bucket drop zone")
	if DisplayServer.get_name() == "headless": controller.release_drop(point)
	else: await mouse(point, false)
	await frames()
	check(not controller.is_dragging(), "Bucket release retires its input gesture")
	return bucket.has_cup(cup)


func pickup_clean() -> bool:
	var point := bucket.clean_pickup.get_global_transform_with_canvas().origin
	await move_pointer(point)
	var result := false
	if DisplayServer.get_name() == "headless": result = bucket.begin_clean_pickup(point)
	else:
		await mouse(point, true)
		result = controller.is_dragging() and transfers.is_transferring(controller.current_drag_node as Cup)
	check(result, "Manual bucket pickup starts through the real transfer owner")
	return result


func drop_surface(world_origin: Vector2, target: PlacementSurface) -> bool:
	var cup := controller.current_drag_node as Cup
	if cup == null:
		check(false, "Surface release has an actual held cup")
		return false
	# The clean-pickup handle is offset from the hidden cup's origin. Preserve
	# the controller's real grip offset instead of teleporting a test object.
	var point := controller._last_pointer + canvas_position(world_origin) - cup.get_global_transform_with_canvas().origin
	await move_pointer(point)
	controller.update_drag(point)
	check(controller.hovered_drop_zone is CupTransferDropZone, "Real controller selects free-surface recovery for a source transfer")
	if DisplayServer.get_name() == "headless": controller.release_drop(point)
	else: await mouse(point, false)
	await frames()
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	var placed := handle.surface == target and target.is_registered(cup)
	check(placed, "Valid release commits the intended table/tray reservation")
	check(not controller.is_dragging() and not transfers.is_transferring(cup), "Surface commit retires gesture and transfer ownership")
	return placed


func consume(actor: Customer, cup: Cup) -> StringName:
	var order_id := actor.order.order_id
	var before_income := finance.day_income
	fill(cup)
	await take_cup(cup)
	await release_at(actor)
	check(actor.order.fulfilled and service.get_served_cup(order_id) == cup, "Accepted drink retains the exact served cup")
	check(finance.day_income == before_income, "Accepted drink does not pay at handoff")
	queue.advance(40.0)
	check(queue.get_active_customers().has(actor), "Accepted drink keeps its queue slot while drinking")
	returns.advance(7.0)
	check(cup.state == Cup.CupState.SERVED and is_equal_approx(cup.volume_ml, 250.0), "Cup retains contents before drinking finishes")
	returns.advance(1.0)
	check(cup.state == Cup.CupState.DIRTY and not cup.has_contents(), "Consumption empties and dirties the original cup")
	check(cup.assigned_order_id == order_id and returns.get_dirty_return_cup(order_id) == cup, "Dirty return preserves order/cup identity")
	check(finance.day_income == before_income, "Offering the dirty cup still does not pay")
	return order_id


func begin_return(order_id: StringName) -> bool:
	var point := returns.get_return_pick_point(order_id)
	await move_pointer(point)
	var result := false
	if DisplayServer.get_name() == "headless": result = returns.begin_return(order_id, point)
	else:
		await mouse(point, true)
		result = controller.is_dragging() and transfers.is_transferring(controller.current_drag_node as Cup)
	check(result and controller.current_drag_node == returns.get_dirty_return_cup(order_id),
		"Use extracts the customer's original dirty cup")
	return result


func wash_complete(cup: Cup) -> void:
	await move_pointer(bucket_point())
	if DisplayServer.get_name() == "headless": check(bucket.begin_wash(), "Real bucket obtains held washing ownership")
	else:
		await mouse(bucket_point(), true)
		check(bucket.get_snapshot().washing and controller.action_owner == bucket, "Actual mouse hold acquires bucket washing ownership")
	bucket.advance_washing(bucket.config.wash_seconds)
	check(cup.state == Cup.CupState.CLEAN and cup.assigned_order_id.is_empty(), "Wash makes the original cup clean and clears its old assignment")
	check(bucket.has_cup(cup) and not cup.visible and bucket.get_snapshot().clean == 1,
		"Clean cup remains in bucket custody until manual pickup")
	check(not bucket.get_snapshot().washing and not controller.has_active_action(), "Finishing the only cup releases held washing ownership")


func seven_reuse_cycles() -> void:
	await fixture()
	var cup: Cup = screen.get_cups()[0]
	var cup_id := cup.get_instance_id()
	var tray_origin := cup.global_position
	var stock_before := stock.quantities.duplicate(true)
	var water_before: float = root.get_node("GameState").water_supply.remaining_ml
	var expected_income := 0
	await capture("00-integration-initial")
	for index in 7:
		var actor := start_order(&"tea_cha_no_sugar")
		var quote: int = actor.order.get_request().price
		var order_id := await consume(actor, cup)
		if index == 0: await capture("01-offered-dirty-cup")
		if not await begin_return(order_id): return
		check(await drop_bucket(), "Cycle %d deposits the real customer cup into the real bucket" % (index + 1))
		if not bucket.has_cup(cup): return
		expected_income += quote
		check(finance.day_income == expected_income and finance.transaction_log.size() == index + 1,
			"Cycle %d pays the saved quote exactly once at committed return" % (index + 1))
		check(service.get_served_cup(order_id) == null and queue.get_active_customers().is_empty(),
			"Committed bucket return retires customer custody and permits departure")
		await wash_complete(cup)
		if not await pickup_clean(): return
		if index == 0: await capture("02-clean-cup-picked-up")
		var desired := tray_origin if index % 2 == 0 else table_cup_origin()
		var surface := tray.interior_surface if index % 2 == 0 else table
		if not await drop_surface(desired, surface): return
		if index == 0: await capture("03-clean-cup-on-tray")
		if index == 1: await capture("04-clean-cup-on-table")
		check(cup.get_instance_id() == cup_id and cup.state == Cup.CupState.CLEAN and screen.get_cups().has(cup),
			"Cycle %d returns the same clean physical cup to playable surfaces" % (index + 1))
		check(bucket.get_snapshot().total == 0, "Manual pickup frees one bucket place only after placement")
		check(stock.quantities == stock_before and is_equal_approx(root.get_node("GameState").water_supply.remaining_ml, water_before),
			"Return and wash never alter ingredient stock or brewing water")
	check(service.get_records().size() == 7 and finance.transaction_log.size() == 7,
		"Seven complete drink cycles preserve seven immutable receipts on one reused cup")
	check(finance.cash_on_hand == 100 + expected_income, "Run cash agrees with seven once-only delayed payments")
	for record in service.get_records():
		check(record.served_cup_id == cup_id and not screen.customer_payments.enqueue_accepted(service, record, Vector2.ZERO),
			"Each reuse receipt retains physical identity and refuses replay")


func wash_interruptions_and_cancellation() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var cup: Cup = screen.get_cups()[0]
	var order_id := await consume(actor, cup)
	if not await begin_return(order_id): return
	controller.cancel_drag()
	check(service.get_served_cup(order_id) == cup and returns.get_dirty_return_cup(order_id) == cup,
		"Cancelled customer pickup restores its original custody")
	check(finance.day_income == 0 and cup.state == Cup.CupState.DIRTY, "Cancelled return neither pays nor changes dirty contents")
	if not await begin_return(order_id): return
	controller.release_drop(Vector2(-1000.0, -1000.0))
	check(not transfers.is_transferring(cup) and returns.get_dirty_return_cup(order_id) == cup and finance.day_income == 0,
		"Invalid customer drop restores the unpaid original cup")
	if not await begin_return(order_id): return
	if not await drop_bucket(): return
	var paid_snapshot := finance.get_snapshot()
	await move_pointer(bucket_point())
	check(bucket.begin_wash(), "Washing begins after real return")
	bucket.advance_washing(0.6)
	var progress: float = bucket.get_snapshot().progress
	check(is_equal_approx(progress, 0.25), "Quarter wash advances the real cup's stored progress")
	await capture("05-bucket-washing")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	bucket._input(release)
	bucket.advance_washing(10.0)
	check(not bucket.get_snapshot().washing and is_equal_approx(bucket.get_snapshot().progress, progress), "Mouse release pauses without erasing or completing progress")
	check(bucket.begin_wash(), "Explicit hold resumes a paused cup")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	bucket.advance_washing(10.0)
	check(not bucket.get_snapshot().washing and is_equal_approx(bucket.get_snapshot().progress, progress), "Organize switch pauses the wash")
	controller.set_mode(InteractionController.MODE_INTERACT)
	check(bucket.begin_wash(), "Hold starts before actual Khata Full opens")
	check(screen.khata_modal.open(), "Actual Full notebook opens")
	bucket.advance_washing(10.0)
	check(not bucket.get_snapshot().washing and is_equal_approx(bucket.get_snapshot().progress, progress), "Full notebook cancels only washing input, retaining progress")
	screen.khata_modal.close()
	await settle_book(screen.khata_modal)
	check(bucket.begin_wash(), "Washing resumes after the Full notebook releases input")
	bucket.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	bucket.advance_washing(10.0)
	check(not bucket.begin_wash() and is_equal_approx(bucket.get_snapshot().progress, progress), "Focus loss retains progress and prevents background restart")
	bucket.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await wash_complete(cup)
	if not await pickup_clean(): return
	controller.cancel_drag()
	check(bucket.has_cup(cup) and cup.get_parent() == bucket.holder and not cup.visible,
		"Cancelled clean pickup restores hidden bucket custody")
	if not await pickup_clean(): return
	controller.release_drop(Vector2(-1000.0, -1000.0))
	check(bucket.has_cup(cup) and cup.state == Cup.CupState.CLEAN and not cup.visible,
		"Invalid clean destination preserves the reusable cup and capacity")
	if not await pickup_clean(): return
	await drop_surface(table_cup_origin(), table)
	check(finance.get_snapshot() == paid_snapshot, "Wash, repeated pickup and cancellation never replay the return payment")


func placement_modes() -> void:
	await fixture()
	var cup: Cup = screen.get_cups()[0]
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	var origin := cup.global_transform
	var parent := cup.get_parent()
	check(not handle.begin_drag(cup.get_global_transform_with_canvas().origin), "Use cannot begin ordinary table/tray reorganization")
	check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Use can still lift an ordinary cup for tool/service actions")
	controller.release_drop(canvas_position(table_cup_origin()))
	check(cup.get_parent() == parent and cup.global_transform.is_equal_approx(origin), "Ordinary Use cup release onto table returns to its previous placement")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(not cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Organize does not begin a service drag")
	var start := cup.get_global_transform_with_canvas().origin
	check(handle.begin_drag(start), "Organize begins the existing placement transaction")
	controller.release_drop(canvas_position(table_cup_origin()))
	check(handle.surface == table and table.is_registered(cup), "Organize moves an ordinary cup from tray to free table space")
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(not handle.begin_drag(cup.get_global_transform_with_canvas().origin) and not bucket.begin_wash(), "Neutral starts neither reorganization nor washing")


func manual_return_to_both_surfaces() -> void:
	await fixture()
	var cups: Array[Cup] = screen.get_cups()
	var expected_income := 0
	for index in 2:
		var cup := cups[index]
		var target := table if index == 0 else tray.interior_surface
		var destination := table_cup_origin() if index == 0 else cup.global_position
		var actor := start_order(&"tea_cha_no_sugar")
		expected_income += int(actor.order.get_request().price)
		var order_id := await consume(actor, cup)
		if not await begin_return(order_id): return
		if not await drop_surface(destination, target): return
		check(cup.state == Cup.CupState.DIRTY and cup.assigned_order_id == order_id,
			"Manual customer-to-surface return retains dirty lifecycle and assignment until wash")
		check(finance.day_income == expected_income and service.get_served_cup(order_id) == null,
			"Each manual table/tray customer return authorizes exactly one quoted payment")
	# A returned dirty table cup may still be lifted in Use for the wash station.
	await take_cup(cups[0])
	check(await drop_bucket(), "A dirty cup already returned onto the table can be deposited in Use")
	check(finance.day_income == expected_income, "Subsequent bucket deposit does not pay the same return again")


func block_surface(surface: PlacementSurface) -> Polygon2D:
	var exclusions := surface.get_node_or_null("Exclusions") as Node2D
	if exclusions == null:
		exclusions = Node2D.new()
		exclusions.name = "Exclusions"
		surface.add_child(exclusions)
	var blocker := Polygon2D.new()
	blocker.name = "IntegrationFullSurface"
	blocker.polygon = surface.usable_polygon.duplicate()
	exclusions.add_child(blocker)
	blocker.hide()
	return blocker


func full_surfaces_then_recover() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	var cup: Cup = screen.get_cups()[0]
	await consume(actor, cup)
	# Real exclusion polygons fill both surfaces; the actual geometry and return
	# search run unchanged. No transfer availability flag/test double is used.
	var table_block := block_surface(table)
	var tray_block := block_surface(tray.interior_surface)
	check(table.get_free_regions().is_empty() and tray.interior_surface.get_free_regions().is_empty(), "Fixture makes both actual surface geometries full")
	returns.advance(8.0)
	queue.advance(300.0)
	check(returns.get_dirty_return_cup(order.order_id) == cup and queue.get_active_customers().has(actor), "Attention timeout on full surfaces keeps the real cup and customer")
	check(finance.day_income == 0 and not transfers.is_transferring(cup), "Full-surface waiting is unpaid and does not fabricate a transfer")
	check(order.get_results().size() == 1 and order.get_results()[0].reasons.is_empty(), "No-space waiting adds no result, penalty or review reason")
	returns.advance(30.0)
	check(service.get_served_cup(order.order_id) == cup and finance.day_income == 0, "Repeated full-surface retries preserve custody without early income")
	table_block.free()
	tray_block.free()
	returns.advance(0.4)
	await frames()
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	check(handle.surface.is_registered(cup) and cup.is_visible_in_tree() and cup.state == Cup.CupState.DIRTY,
		"Freeing real surface space automatically returns the same dirty cup to a valid reservation")
	check(finance.day_income == order.get_request().price and queue.get_active_customers().is_empty(),
		"Successful deferred placement pays once and releases customer capacity")
	returns.advance(100.0)
	await frames()
	check(finance.transaction_log.size() == 1, "Further return ticks cannot repeat the sale")


func active_pickup_reentry() -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var cup: Cup = screen.get_cups()[0]
	var cup_id := cup.get_instance_id()
	var order_id := await consume(actor, cup)
	if not await begin_return(order_id): return
	root.remove_child(screen)
	await frames()
	root.add_child(screen)
	await frames(4)
	check(not controller.is_dragging() and not transfers.is_transferring(cup), "Screen re-entry retires an interrupted customer pickup")
	check(is_instance_valid(cup) and cup.get_instance_id() == cup_id and cup.is_inside_tree(), "Customer pickup re-entry preserves the physical cup")
	check(returns.get_dirty_return_cup(order_id) == cup and service.get_served_cup(order_id) == cup and finance.day_income == 0,
		"Re-entry restores unpaid customer-source custody without a phantom return")
	if not await begin_return(order_id): return
	if not await drop_bucket(): return
	await wash_complete(cup)
	if not await pickup_clean(): return
	var income_before := finance.get_snapshot()
	root.remove_child(screen)
	await frames()
	root.add_child(screen)
	await frames(4)
	check(not controller.is_dragging() and not transfers.is_transferring(cup), "Screen re-entry retires an interrupted clean-bucket pickup")
	check(bucket.has_cup(cup) and cup.get_parent() == bucket.holder and cup.state == Cup.CupState.CLEAN and not cup.visible,
		"Clean pickup re-entry restores the original cup to retrievable bucket custody")
	check(finance.get_snapshot() == income_before, "Clean pickup re-entry does not pay again")
	if not await pickup_clean(): return
	await drop_surface(table_cup_origin(), table)
	check(cup.get_instance_id() == cup_id and screen.get_cups().has(cup), "After both interruptions the same cup is playable again")


func removed_bucket_during_pickup(immediate_cancel := false) -> void:
	await fixture()
	var actor := start_order(&"tea_cha_no_sugar")
	var cup: Cup = screen.get_cups()[0]
	var cup_id := cup.get_instance_id()
	var order_id := await consume(actor, cup)
	if not await begin_return(order_id): return
	if not await drop_bucket(): return
	await wash_complete(cup)
	if not await pickup_clean(): return
	var income_before := finance.get_snapshot()
	bucket.queue_free()
	if not immediate_cancel: await frames()
	# Cover both a source that is gone and an ancestor queued for deletion in
	# this same frame; rollback must not reattach the cup to a doomed holder.
	controller.cancel_drag()
	await create_timer(0.6).timeout
	await frames()
	check(is_instance_valid(cup) and cup.get_instance_id() == cup_id and cup.is_inside_tree(),
		"Deleting a bucket source during pickup preserves its surviving held cup")
	check(not controller.is_dragging() and not transfers.is_transferring(cup),
		"Cancellation after source deletion retires the stale transfer")
	if not is_instance_valid(cup): return
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	check(is_instance_valid(handle.surface) and handle.surface.is_registered(cup) and cup.is_visible_in_tree(),
		"Removed source recovers the clean cup onto available real surface geometry")
	check(cup.state == Cup.CupState.CLEAN and finance.get_snapshot() == income_before,
		"Source deletion neither dirties the recovered cup nor replays income")


func add_rect_exclusion(surface: PlacementSurface, rectangle: Rect2) -> Polygon2D:
	var exclusions := surface.get_node_or_null("Exclusions") as Node2D
	if exclusions == null:
		exclusions = Node2D.new()
		exclusions.name = "Exclusions"
		surface.add_child(exclusions)
	var shape := Polygon2D.new()
	shape.polygon = PackedVector2Array([rectangle.position,
		Vector2(rectangle.end.x, rectangle.position.y), rectangle.end,
		Vector2(rectangle.position.x, rectangle.end.y)])
	exclusions.add_child(shape)
	shape.hide()
	return shape


func exact_fractional_vacancy() -> void:
	await fixture()
	var cup: Cup = screen.get_cups()[0]
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	var origin: Vector2 = screen.world_root.to_global(Vector2(860.123, 900.456))
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(handle.begin_drag(cup.get_global_transform_with_canvas().origin), "Fractional vacancy fixture begins ordinary Organize placement")
	controller.release_drop(canvas_position(origin))
	check(handle.surface == table and table.is_registered(cup) and cup.global_position.distance_to(origin) < 0.001,
		"Fractional fixture registers the real cup at a non-grid authored position")
	var original := cup.global_transform
	var polygon := table.get_committed_polygons(cup)[0]
	var footprint_bounds := Rect2(polygon[0], Vector2.ZERO)
	for vertex in polygon: footprint_bounds = footprint_bounds.expand(vertex)
	controller.set_mode(InteractionController.MODE_INTERACT)
	var actor := start_order(&"tea_cha_no_sugar")
	var order := actor.order
	await consume(actor, cup)
	check(not table.get_vacated_positions().is_empty(), "Serving records the actual released footprint as a return candidate")
	# Leave just this exact footprint AABB with a tiny numerical margin. Four
	# real exclusion rectangles occupy every other part of the table.
	var hole := footprint_bounds.grow(0.001)
	var bounds := Rect2(table.usable_polygon[0], Vector2.ZERO)
	for vertex in table.usable_polygon: bounds = bounds.expand(vertex)
	var blockers: Array[Polygon2D] = []
	blockers.append(add_rect_exclusion(table, Rect2(bounds.position, Vector2(hole.position.x - bounds.position.x, bounds.size.y))))
	blockers.append(add_rect_exclusion(table, Rect2(Vector2(hole.end.x, bounds.position.y), Vector2(bounds.end.x - hole.end.x, bounds.size.y))))
	blockers.append(add_rect_exclusion(table, Rect2(Vector2(hole.position.x, bounds.position.y), Vector2(hole.size.x, hole.position.y - bounds.position.y))))
	blockers.append(add_rect_exclusion(table, Rect2(Vector2(hole.position.x, hole.end.y), Vector2(hole.size.x, bounds.end.y - hole.end.y))))
	var tray_block := block_surface(tray.interior_surface)
	var offered_pose := cup.global_transform
	cup.global_transform = original
	check(table.validate_candidate(cup, handle.get_footprints()).is_valid, "Exactly vacated fractional footprint remains geometrically valid")
	cup.global_position += Vector2(2.0, 0.0)
	check(not table.validate_candidate(cup, handle.get_footprints()).is_valid, "A shifted candidate cannot fit the deliberately tight vacancy")
	cup.global_transform = offered_pose
	check(tray.interior_surface.get_free_regions().is_empty(), "No tray fallback can conceal a failed fractional table return")
	returns.advance(8.0)
	await frames()
	check(handle.surface == table and table.is_registered(cup) and table.validate_item(cup).is_valid,
		"Automatic return books the original cup into the exact fractional vacancy")
	check(cup.global_position.distance_to(original.origin) < 0.001 and cup.state == Cup.CupState.DIRTY,
		"Automatic recovery keeps the original dirty identity and fractional pose")
	check(finance.transaction_log.size() == 1 and finance.day_income == order.get_request().price,
		"Tight-vacancy return pays the original quote exactly once")
	returns.advance(100.0)
	await frames()
	check(finance.transaction_log.size() == 1, "Exact-vacancy retry cannot repeat the accepted sale")
	for blocker in blockers: blocker.free()
	tray_block.free()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	await seven_reuse_cycles()
	await wash_interruptions_and_cancellation()
	await placement_modes()
	await manual_return_to_both_surfaces()
	await full_surfaces_then_recover()
	await active_pickup_reentry()
	await removed_bucket_during_pickup()
	await removed_bucket_during_pickup(true)
	await exact_fractional_vacancy()
	if is_instance_valid(screen): screen.queue_free()
	await frames(4)
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		var preview: Node = load("res://scenes/development/CupReusePreview.tscn").instantiate()
		root.add_child(preview)
		await frames(5)
		var live_screen := preview.get_node("TongDayScreen")
		check(live_screen.bucket is BucketStation and live_screen.cup_returns is CustomerCupReturns,
			"Actual CupReusePreview wires production bucket and cup-return owners")
		await capture("06-actual-reuse-preview")
		preview.queue_free()
		await frames(4)
	print("BUCKET_RETURN_INTEGRATION: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
