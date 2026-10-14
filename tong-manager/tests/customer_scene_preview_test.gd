extends SceneTree
## Real Tong scene with isolated sample outcomes. Rendered runs also use mouse input.

const PREVIEW := preload("res://scenes/development/CustomerScenePreview.tscn")
var checks := 0
var failures: Array[String] = []
var view: Node
var controller: InteractionController
var state: Node
var stock_before: Dictionary
var water_before := 0.0
var capture_dir := ""
var rendered := false


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


func move_pointer(point: Vector2, held := false) -> void:
	if rendered: root.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await frames()


func mouse(point: Vector2, pressed: bool) -> void:
	await move_pointer(point, pressed)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await frames()


func capture(label: String) -> void:
	if not rendered or capture_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Captured " + label)


func reset_samples() -> void:
	controller.cancel_drag()
	controller.set_mode(InteractionController.MODE_INTERACT)
	for entry: Variant in view.customers:
		if is_instance_valid(entry): (entry as Customer).reduced_motion = true
	view.reset_customers()
	await frames()


func body_point(index: int, band := Rect2(0.0, 0.0, 1.0, 1.0), require_visible := true) -> Vector2:
	var actor: Customer = view.customers[index]
	var image: Image = actor.get_front_texture().get_image()
	if image.is_compressed(): image.decompress()
	var used := Rect2(image.get_used_rect())
	var bounds := Rect2i(Vector2i(used.position + used.size * band.position), Vector2i(used.size * band.size))
	var rect := actor.get_front_rect()
	var bob := actor.get_node("VisualRoot/BobRoot") as Node2D
	for y in range(bounds.position.y, bounds.end.y, 4):
		for x in range(bounds.position.x, bounds.end.x, 4):
			if image.get_pixel(x, y).a <= 0.95: continue
			var local_point := rect.position + (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(image.get_size()) * rect.size
			var point := bob.get_global_transform_with_canvas() * local_point
			if root.get_visible_rect().has_point(point) and (not require_visible or view.pick_customer_at(point) == index) and not controller.is_pointer_over_ui_at(point):
				return point
	return Vector2(INF, INF)


func begin_sample(kind: StringName) -> bool:
	var button: Button = view.sample_buttons[kind]
	check(button.is_visible_in_tree() and not button.disabled, "Sample control is available: " + String(kind))
	if rendered:
		await mouse(button.get_global_rect().get_center(), true)
	else:
		view.start_sample_drag(kind, button.get_global_rect().get_center())
	check(controller.is_dragging(), "Sample begins a transient controller gesture")
	if not controller.is_dragging(): return false
	check(controller.current_payload.source == &"customer_scene_fixture"
		and bool(controller.current_payload.metadata.get("transient")), "Sample gesture is explicitly isolated from production stock")
	return true


func drop_sample(kind: StringName, index: int, point: Vector2, valid := true) -> void:
	check(point.is_finite(), "Fixture found a visible body point")
	if not point.is_finite() or not await begin_sample(kind): return
	var visual: WeakRef = weakref(controller.current_drag_node)
	await move_pointer(point, true)
	controller.update_drag(point)
	check(controller.hovered_drop_zone == (view.zones[index] if valid else null), "Only the intended visible recipient owns the sample point")
	if rendered: await mouse(point, false)
	else: controller.release_drop(point)
	await frames()
	check(not controller.is_dragging() and visual.get_ref() == null, "Sample release removes its transient visual and gesture")


func check_sample_outcomes() -> void:
	await reset_samples()
	var a: Customer = view.customers[0]
	var b: Customer = view.customers[1]
	var untouched := b.order.get_snapshot()
	await drop_sample(&"cold", 0, body_point(0, Rect2(0.25, 0.02, 0.5, 0.24)))
	check(a.order.fulfilled and a.order.get_accepted_result().bad_review and int(a.get_presentation_snapshot().review_count) == 1,
		"Dropping cold tea on the visible head fulfills with one dissatisfied review")
	check(b.order.get_snapshot() == untouched and not view.replay_last_result(0), "One recipient changes; replay cannot duplicate the result")
	await capture("cold-accepted")
	await reset_samples()
	await drop_sample(&"tea", 0, body_point(0, Rect2(0.02, 0.4, 0.25, 0.4)))
	check(a.order.fulfilled and not a.order.get_accepted_result().bad_review, "A visible arm is also a full customer target")
	await drop_sample(&"wrong", 1, body_point(1, Rect2(0.25, 0.02, 0.5, 0.24)))
	check(not b.order.fulfilled and b.is_serve_enabled() and b.order.get_results().size() == 1, "Wrong sample remains a rejection with the same waiting recipient")
	check(not view.replay_last_result(1) and b.order.get_results().size() == 1, "Rejected replay also stays idempotent")
	await capture("warm-and-wrong")
	await drop_sample(&"banana", 1, body_point(1, Rect2(0.75, 0.4, 0.23, 0.4)))
	check(b.order.fulfilled and b.order.get_results().size() == 2 and b.order.get_accepted_result().reason == &"ready_item_served",
		"A corrected ready piece reaches the visible arm and fulfills once")
	check(state.inventory.quantities == stock_before and state.water_supply.remaining_ml == water_before, "All synthetic outcomes preserve live stock and daily water")


func check_occlusion_and_overlap() -> void:
	await reset_samples()
	var a: Customer = view.customers[0]
	var b: Customer = view.customers[1]
	var frame := view.screen.get_node("WorldRoot/FrameFront") as Sprite2D
	var image: Image = frame.texture.get_image()
	if image.is_compressed(): image.decompress()
	var covered := Vector2(INF, INF)
	var bounds := a.get_serve_bounds()
	for y in range(int(bounds.position.y), int(bounds.end.y), 3):
		for x in range(int(bounds.position.x), int(bounds.end.x), 3):
			var world := Vector2(x, y)
			if not a.contains_serve_point(world): continue
			var screen_point := a.get_canvas_transform() * world
			var pixel := frame.get_global_transform_with_canvas().affine_inverse() * screen_point
			if Rect2(Vector2.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(Vector2i(pixel)).a > 0.2:
				covered = screen_point
				break
		if covered.is_finite(): break
	check(covered.is_finite(), "Fixture locates an opaque customer pixel behind foreground frame art")
	if covered.is_finite():
		check(view.pick_customer_at(covered) == -1, "Counter/roof occlusion prevents invisible customer capture")
		await drop_sample(&"tea", 0, covered, false)
		check(a.order.get_results().is_empty(), "Dropping through foreground artwork cannot serve a customer")
	var old_position := b.position
	b.position = a.position
	var shared := Vector2(INF, INF)
	for y in range(int(bounds.position.y), int(bounds.end.y), 4):
		for x in range(int(bounds.position.x), int(bounds.end.x), 4):
			var world := Vector2(x, y)
			var point := a.get_canvas_transform() * world
			if a.contains_serve_point(world) and b.contains_serve_point(world) and view.pick_customer_at(point) == 1 and not controller.is_pointer_over_ui_at(point):
				shared = point
				break
		if shared.is_finite(): break
	check(shared.is_finite(), "Overlap fixture has a genuinely shared visible silhouette")
	if shared.is_finite():
		await drop_sample(&"banana", 1, shared)
		check(b.order.fulfilled and not a.order.fulfilled, "Overlapping bodies choose the visually front customer only")
		check(view.pick_customer_at(shared) == -1, "A served but still visible front customer blocks click-through to the customer behind")
		await drop_sample(&"tea", 0, shared, false)
		check(a.order.get_results().is_empty(), "Repeated overlap drop cannot silently change recipient")
		await reset_samples()
		b.position = a.position
		var parent := a.get_parent()
		parent.remove_child(a)
		parent.add_child(a)
		a.arrive()
		await frames()
		check(view.pick_customer_at(shared) == 0, "Overlap selection follows the new visual sibling order after re-entry")
		await drop_sample(&"tea", 0, shared)
		check(a.order.fulfilled and not b.order.fulfilled, "Reordered overlap delivers to the newly front actor only")
	b.position = old_position
	await reset_samples()


func check_gates_and_lifecycle() -> void:
	var a: Customer = view.customers[0]
	for mode: StringName in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE]:
		controller.set_mode(mode)
		check(not view.start_sample_drag(&"tea", Vector2(500, 500)), "Synthetic serving gesture requires Use mode")
	controller.set_mode(InteractionController.MODE_INTERACT)
	await frames()
	check(not view.start_sample_drag(&"unknown", Vector2.ZERO), "Unknown synthetic payload is rejected")
	var blocker := Control.new()
	controller.modal_root.add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()
	check(controller.is_world_input_blocked() and not view.start_sample_drag(&"tea", Vector2(500, 500))
		and not view.simulate_result(0, &"tea"), "Visible modal blocks sample gestures and direct fixture actions")
	blocker.queue_free()
	await frames()
	var prior_order: OrderState = a.order
	if await begin_sample(&"tea"):
		view.reset_customers()
		view.set_customer_count(1)
		check(a.order == prior_order and view.selected_count == 2, "Reset/count controls cannot replace a live sample gesture")
		controller.set_mode(InteractionController.MODE_NEUTRAL)
		await frames()
		check(not controller.is_dragging() and prior_order.get_results().is_empty(), "Changing intent cancels the sample without an outcome")
	controller.set_mode(InteractionController.MODE_INTERACT)
	await frames()
	var original_parent := a.get_parent()
	var point := body_point(0)
	if await begin_sample(&"tea"):
		original_parent.remove_child(a)
		controller.release_drop(point)
		await frames()
		check(not controller.is_dragging() and prior_order.get_results().is_empty(), "Detached target cannot consume or record a pending sample")
		original_parent.add_child(a)
		a.arrive()
		await frames()
		await drop_sample(&"tea", 0, body_point(0))
		check(a.order.fulfilled, "Retained customer re-entry restores its sample target registration")
	await reset_samples()
	view.set_customer_count(1)
	await frames()
	check(not (view.customers[1] as Customer).is_visible_in_tree() and not view.simulate_result(1, &"banana"), "One-customer preview disables the absent sample identity")
	view.set_customer_count(2)
	await frames()
	check((view.customers[1] as Customer).is_serve_enabled(), "Two-customer preview restores the second sample without selecting a production capacity")
	if rendered:
		var target := body_point(0)
		var overlay := ColorRect.new()
		overlay.position = target - Vector2(30, 30)
		overlay.size = Vector2(60, 60)
		view.get_node("PreviewUI/Root").add_child(overlay)
		if await begin_sample(&"tea"):
			await move_pointer(target, true)
			check(controller.hovered_drop_zone == null, "Actual pointer over a panel cannot highlight the customer underneath")
			await mouse(target, false)
			check(not a.order.fulfilled, "A covered customer does not receive a real release")
		overlay.queue_free()
		await frames()


func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	state = root.get_node("GameState")
	check(state.ensure_inventory(), "Shared inventory initializes before the isolated preview")
	state.ensure_water_day()
	var inventory_identity: InventoryState = state.inventory
	var water_identity: DailyWaterSupply = state.water_supply
	stock_before = state.inventory.quantities
	water_before = state.water_supply.remaining_ml
	view = PREVIEW.instantiate()
	root.add_child(view)
	await frames(5)
	controller = view.controller
	await reset_samples()
	check(view.customers.size() == 2 and view.zones.size() == 2, "The full Tong review has two explicitly isolated sample customers")
	check((view.customers[0] as Customer).customer_def.id != (view.customers[1] as Customer).customer_def.id, "Sample customers retain distinct data identities")
	for button: Button in view.sample_buttons.values():
		check(root.get_visible_rect().encloses(button.get_global_rect()), "Sample button fits the current viewport")
	var cup_states: Array[Dictionary] = []
	for cup: Cup in view.screen.get_cups():
		cup_states.append({"id": cup.get_instance_id(), "state": cup.state, "volume": cup.volume_ml, "order": cup.assigned_order_id, "ingredients": cup.get_ingredient_amounts()})
	await capture("initial-customers")
	await check_sample_outcomes()
	await check_occlusion_and_overlap()
	await check_gates_and_lifecycle()
	for cup: Cup in view.screen.get_cups():
		var index: int = view.screen.get_cups().find(cup)
		check(cup_states[index] == {"id": cup.get_instance_id(), "state": cup.state, "volume": cup.volume_ml, "order": cup.assigned_order_id, "ingredients": cup.get_ingredient_amounts()},
			"Synthetic handoffs never serve, empty, or mutate a live gameplay cup")
	check(state.inventory == inventory_identity and state.water_supply == water_identity and state.inventory.quantities == stock_before
		and state.water_supply.remaining_ml == water_before, "Preview actions never consume, refund, replenish or replace shared supplies")
	var survivor: Customer = view.customers[0]
	var removed: Customer = view.customers[1]
	removed.queue_free()
	await frames()
	check(not view.simulate_result(1, &"banana") and not view.replay_last_result(1), "A freed target rejects late fixture actions safely")
	await reset_samples()
	var survivor_point := body_point(0)
	check(survivor_point.is_finite() and view.pick_customer_at(survivor_point) == 0, "A freed peer does not disable the surviving customer")
	await drop_sample(&"tea", 0, survivor_point)
	check(survivor.order.fulfilled, "The surviving customer still receives a sample after its peer is freed")
	await reset_samples()
	if await begin_sample(&"tea"):
		var held: WeakRef = weakref(controller.current_drag_node)
		view.queue_free()
		await frames(4)
		check(held.get_ref() == null, "Preview teardown disposes its held synthetic visual")
	else:
		view.queue_free()
		await frames()
	check(state.inventory.quantities == stock_before and state.water_supply.remaining_ml == water_before, "Preview teardown leaves live stock and water untouched")
	print("CUSTOMER_SCENE_PREVIEW: %d checks; %d failures; rendered=%s" % [checks, failures.size(), rendered])
	quit(0 if failures.is_empty() else 1)
