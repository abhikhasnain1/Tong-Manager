extends SceneTree

var checks := 0
var failures: Array[String] = []
var cleaned_ids: Array[int] = []
var reentrant_pickup := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func dirty(cup: Cup) -> void:
	cup.receive_liquid(&"black_tea", 50.0, 60.0)
	cup.mark_served()
	cup.mark_dirty()

func deliver(cup: Cup, bucket: BucketStation, controller: InteractionController) -> HeldItemPayload:
	check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Table cup starts a real Use drag")
	var payload: HeldItemPayload = controller.current_payload
	controller.release_drop(bucket.get_global_transform_with_canvas().origin)
	return payload

func block_surface(surface: PlacementSurface) -> Polygon2D:
	var exclusions := surface.get_node_or_null("Exclusions") as Node2D
	if exclusions == null:
		exclusions = Node2D.new()
		exclusions.name = "Exclusions"
		surface.add_child(exclusions)
	var blocker := Polygon2D.new()
	blocker.polygon = surface.usable_polygon.duplicate()
	exclusions.add_child(blocker)
	blocker.hide()
	return blocker

func run() -> void:
	var screen: Node2D = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	screen.customer_queue_auto_start = false
	root.add_child(screen)
	await process_frame
	var bucket: BucketStation = screen.get_node("WorldRoot/ToolLayer/BucketStation")
	var controller: InteractionController = screen.get_node("InteractionController")
	var tray: TrayStation = screen.get_node("WorldRoot/ToolLayer/TrayStation")
	var table: PlacementSurface = screen.table_surface
	var cups: Array[Cup] = tray.get_cups()
	var water_before: float = root.get_node("GameState").water_supply.remaining_ml
	var stock_before: Dictionary = root.get_node("GameState").inventory.quantities
	bucket.set_process(false)
	bucket.config = bucket.config.duplicate() as BucketConfig
	check(bucket.config.capacity == 6 and is_equal_approx(bucket.config.wash_seconds, 2.4)
		and is_equal_approx(bucket.config.first_output_fraction, 0.2), "Editable defaults are six places, one 2.4-second batch and first output at 20 percent")
	bucket.config.capacity = 2
	bucket.cup_cleaned.connect(func(cup: Cup): cleaned_ids.append(cup.get_instance_id()))
	check(bucket.get_snapshot().total == 0 and not bucket.begin_wash(), "Empty neutral bucket cannot wash")
	controller.set_mode(InteractionController.MODE_INTERACT)
	var clean_origin: Transform2D = cups[3].transform
	deliver(cups[3], bucket, controller)
	check(bucket.get_snapshot().total == 0 and cups[3].transform == clean_origin, "Clean cup rejected and restored")
	for cup in [cups[0], cups[1], cups[2]]:
		dirty(cup)
	var first: Cup = cups[0]
	var second: Cup = cups[1]
	var third: Cup = cups[2]
	var first_surface: PlacementSurface = first.get_node("PlacementHandle").surface
	var first_id := first.get_instance_id()
	var payload := deliver(first, bucket, controller)
	check(bucket.has_cup(first) and bucket.get_snapshot().dirty == 1, "Dirty table cup booked into bucket")
	check(first.get_instance_id() == first_id and first.get_parent() == bucket.holder and not first.visible, "Receipt retains original hidden cup")
	check(not first_surface.is_registered(first) and not first.input_pickable, "Receipt releases table reservation and input")
	check(not bucket.try_receive(payload) and bucket.get_snapshot().total == 1, "Replayed payload cannot duplicate bucket cup")
	deliver(second, bucket, controller)
	var third_parent: Node = third.get_parent()
	var third_origin: Transform2D = third.transform
	deliver(third, bucket, controller)
	check(bucket.get_snapshot().total == 2 and not bucket.has_cup(third), "Configured capacity rejects a third dirty cup")
	check(third.get_parent() == third_parent and third.transform == third_origin and third.state == Cup.CupState.DIRTY, "Full bucket restores dirty cup without mutation")
	check(controller.current_hint.contains("full"), "Full release reports actionable feedback")
	var table_block := block_surface(table)
	var tray_block := block_surface(tray.interior_surface)
	check(bucket.begin_wash() and controller.action_owner == bucket, "Holding bucket acquires action ownership")
	check(bucket.get_snapshot().batch_total == 2 and bucket.get_snapshot().batch_remaining == 2, "Hold captures the existing dirty cup identities")
	bucket.advance_washing(0.24)
	var partial: float = bucket.get_snapshot().progress
	check(is_equal_approx(partial, 0.1) and first.state == Cup.CupState.DIRTY, "Shared batch progress advances before the first output threshold")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	bucket._input(release)
	bucket.advance_washing(10.0)
	check(not bucket.get_snapshot().washing and not controller.has_active_action() and is_equal_approx(bucket.get_snapshot().progress, partial), "Release pauses instead of resetting or completing wash")
	check(bucket.begin_wash(), "Paused wash can resume")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	bucket.advance_washing(10.0)
	check(is_equal_approx(bucket.get_snapshot().progress, partial) and not bucket.get_snapshot().washing, "Mode change pauses wash")
	controller.set_mode(InteractionController.MODE_INTERACT)
	check(bucket.begin_wash(), "Wash starts before modal interruption")
	var blocker := Node.new()
	screen.add_child(blocker)
	controller.set_world_input_blocked(blocker, true)
	bucket.advance_washing(10.0)
	check(not bucket.get_snapshot().washing and is_equal_approx(bucket.get_snapshot().progress, partial), "Modal cancels only hold, preserving progress")
	controller.set_world_input_blocked(blocker, false)
	blocker.queue_free()
	check(bucket.begin_wash(), "Wash starts before retained bucket detachment")
	var bucket_parent: Node = bucket.get_parent()
	bucket_parent.remove_child(bucket)
	check(not controller.has_active_action(), "Detaching bucket releases wash action")
	bucket_parent.add_child(bucket)
	await process_frame
	check(not bucket.get_snapshot().washing and is_equal_approx(bucket.get_snapshot().progress, partial), "Retained bucket reentry keeps paused progress")
	check(third.begin_interaction_drag(third.get_global_transform_with_canvas().origin), "A dirty cup can be tested after bucket reentry")
	controller.update_drag(bucket.get_global_transform_with_canvas().origin)
	check(controller.hovered_drop_zone == bucket.get_drop_targets()[0], "Reentered bucket re-registers its full drop target")
	controller.cancel_drag()
	check(bucket.begin_wash(), "Wash starts before focus loss")
	bucket.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not bucket.get_snapshot().washing and not bucket.begin_wash(), "Focus loss pauses and prevents background restart")
	bucket.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(not bucket.get_snapshot().washing and bucket.begin_wash(), "Focus return requires explicit new hold")
	var interrupt_clean := func(_old: Cup.CupState, next: Cup.CupState):
		if next == Cup.CupState.CLEAN:
			bucket.cancel_action()
			reentrant_pickup = bucket.begin_clean_pickup(bucket.clean_pickup.get_global_transform_with_canvas().origin)
	first.state_changed.connect(interrupt_clean)
	bucket.advance_washing(8.0)
	first.state_changed.disconnect(interrupt_clean)
	check(first.state == Cup.CupState.CLEAN and second.state == Cup.CupState.DIRTY, "Reentrant release at clean transition stops excess delta from washing the next cup")
	check(not reentrant_pickup and cleaned_ids == [first_id], "Completion resolves once and refuses nested pickup")
	check(is_equal_approx(bucket.get_snapshot().batch_elapsed, bucket.config.wash_seconds * bucket.config.first_output_fraction),
		"Reentrant release stops the shared clock at the first completed threshold")
	check(first.volume_ml == 0.0 and not first.has_contents() and first.assigned_order_id.is_empty(), "Washing clears old contents/history for reusable clean cup")
	check(bucket.get_snapshot().total == 2 and bucket.get_snapshot().clean == 1, "Blocked clean output still consumes capacity")
	check(not bucket.clean_pickup.visible and not bucket.clean_pickup.input_pickable, "Automatic output replaces the old player-facing pickup control")
	deliver(third, bucket, controller)
	check(not bucket.has_cup(third), "Clean output cannot silently make capacity available")
	var pickup: Vector2 = bucket.clean_pickup.get_global_transform_with_canvas().origin
	check(bucket.begin_clean_pickup(pickup) and controller.current_drag_node == first, "Manual clean pickup extracts same cup")
	controller.cancel_drag()
	check(bucket.has_cup(first) and first.get_parent() == bucket.holder and not first.visible, "Canceled clean pickup returns to bucket custody")
	var retained_origin: Transform2D = first.transform
	check(bucket.begin_clean_pickup(pickup), "Clean pickup starts before its bucket alone is detached")
	bucket_parent.remove_child(bucket)
	controller.cancel_drag()
	check(first.get_parent() == bucket.holder and first.transform == retained_origin and not first.visible,
		"Cancellation restores a live detached bucket parent instead of inventing a table return")
	await process_frame
	bucket_parent.add_child(bucket)
	await process_frame
	check(bucket.has_cup(first) and bucket.get_snapshot().total == 2 and bucket.get_snapshot().clean == 1,
		"Reattached source retains exactly its clean cup and capacity")
	check(not first.get_node("PlacementHandle").surface.is_registered(first) and not controller.is_dragging(),
		"Canceled detached-source pickup never creates a table reservation or orphan gesture")
	check(bucket.begin_clean_pickup(pickup), "Clean pickup may be retried")
	controller.release_drop(Vector2(-1000, -1000))
	check(bucket.has_cup(first) and first.get_parent() == bucket.holder and not first.visible, "Invalid destination returns clean cup with no capacity loss")
	check(bucket.begin_clean_pickup(pickup), "Clean pickup starts for free table placement")
	table_block.free()
	var desired: Vector2 = screen.get_node("WorldRoot").get_global_transform_with_canvas() * Vector2(860, 900)
	var placement_pointer: Vector2 = pickup + desired - first.get_global_transform_with_canvas().origin
	controller.update_drag(placement_pointer)
	controller.release_drop(placement_pointer)
	check(not bucket.has_cup(first) and first.is_visible_in_tree() and first.input_pickable, "Clean pickup commits to clear table only on valid release")
	check(first.get_node("PlacementHandle").surface.is_registered(first) and first.state == Cup.CupState.CLEAN, "Placed clean cup has one live free-placement reservation")
	check(bucket.get_snapshot().total == 1, "Successful clean retrieval frees exactly one bucket place")
	table_block = block_surface(table)
	deliver(third, bucket, controller)
	check(bucket.has_cup(third) and bucket.get_snapshot().dirty == 2, "Freed capacity accepts next dirty cup")
	check(bucket.begin_wash(), "Paused captured batch resumes without including the later arrival")
	bucket.advance_washing(bucket.config.wash_seconds * 2.0)
	check(second.state == Cup.CupState.CLEAN and third.state == Cup.CupState.DIRTY and not bucket.get_snapshot().washing,
		"Captured batch completes within its one duration and ignores excess delta for later arrivals")
	check(bucket.get_snapshot().batch_total == 2 and bucket.get_snapshot().batch_remaining == 0,
		"Later dirty arrivals do not rewrite the completed batch membership")
	check(bucket.begin_wash() and bucket.get_snapshot().batch_total == 1, "New hold captures the later dirty cup as a single-cup batch")
	bucket.advance_washing(bucket.config.wash_seconds - 0.001)
	check(third.state == Cup.CupState.DIRTY, "A single-cup batch waits for 100 percent of its shared duration")
	bucket.advance_washing(0.001)
	check(bucket.get_snapshot().clean == 2 and bucket.get_snapshot().dirty == 0 and not bucket.get_snapshot().washing,
		"Single-cup completion leaves blocked clean outputs queued without another wash")
	check(cleaned_ids.size() == 3 and cleaned_ids.count(second.get_instance_id()) == 1 and cleaned_ids.count(third.get_instance_id()) == 1, "Every physical cup is cleaned exactly once")
	check(root.get_node("GameState").water_supply.remaining_ml == water_before and root.get_node("GameState").inventory.quantities == stock_before, "All washes and pickups leave brewing water and ingredient stock unchanged")
	var stale: WeakRef = weakref(third)
	third.queue_free()
	await process_frame
	bucket._process(0.0)
	check(stale.get_ref() == null and bucket.get_snapshot().total == 1, "Removed owned cup cannot retain stale capacity")
	second.reparent(screen.get_node("WorldRoot"), true)
	bucket._process(0.0)
	check(not bucket.has_cup(second) and bucket.get_snapshot().total == 0,
		"A cup moved out of custody without an active transfer cannot retain stale bucket capacity")
	table_block.free()
	tray_block.free()
	bucket.hide()
	check(not bucket.begin_clean_pickup(pickup) and not bucket.begin_wash(), "Hidden bucket cannot offer washing or clean pickup")
	bucket.show()
	screen.queue_free()
	await process_frame
	print("BUCKET_FOCUSED: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
