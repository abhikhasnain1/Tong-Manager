extends SceneTree

var checks := 0
var failures: Array[String] = []
var preview: Node
var screen: Node2D
var controller: InteractionController
var captures := PackedStringArray()
var phase := ""


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func point(rig: HangingSourceBody) -> Vector2:
	return rig.sprite.get_global_transform_with_canvas() * rig.sprite.get_rect().get_center()


func move_pointer(to: Vector2, held := false, relative := Vector2.ZERO) -> void:
	root.warp_mouse(to)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = relative
	event.velocity = relative * 60.0
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await frames(2)


func mouse(to: Vector2, pressed: bool) -> void:
	await move_pointer(to, pressed)
	var event := InputEventMouseButton.new()
	event.position = to
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await frames(2)


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)


func source(rig: HangingSourceBody) -> IngredientPortionSource:
	return rig.get_node("ReadyItemSource") as IngredientPortionSource


func begin(rig: HangingSourceBody) -> bool:
	await mouse(point(rig), true)
	var active := controller.is_dragging() and controller.current_payload != null
	check(active, "%s moving source is picked through real viewport input (%s)" % [rig.name, phase])
	if not active:
		print("PICK_DIAGNOSTIC phase=%s source=%s point=%s gui=%s hit=%s available=%s mode=%s angle=%s" % [
			phase, rig.name, point(rig), root.gui_get_hovered_control(), rig.contains_pointer(point(rig)),
			source(rig)._can_extract(), controller.current_mode, rig.body.rotation])
		await mouse(point(rig), false)
		return false
	check(controller.current_payload.metadata.get("category") == &"ready_item"
		and controller.current_payload.item_id == source(rig).item_id
		and controller.current_payload.quantity == 1,
		"Extraction creates exactly one ready_item/piece payload")
	check(controller.current_drag_node != rig and rig.body.get_parent() == rig,
		"Extracted item is separate and source stays attached")
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Held piece replaces the hardware cursor")
	return true


func snapshot(index: int) -> void:
	if captures.size() > index:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[index]) == OK, "Review screenshot saved")


func check_modes() -> void:
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_USE]:
		controller.set_mode(mode)
		for rig: HangingSourceBody in screen.hanging_sources:
			rig.reset_sway()
			await frames(2)
			await move_pointer(point(rig), false, Vector2(25, 0))
			check(absf(rig.body.angular_velocity) > 0.005 or absf(rig.body.rotation) > 0.005,
				"%s brushes in %s" % [rig.name, mode])
			if mode != InteractionController.MODE_USE:
				await mouse(point(rig), true)
				await mouse(point(rig), false)
				check(not controller.is_dragging(), "%s click cannot extract in %s" % [rig.name, mode])
			check(rig.body is RigidBody2D and rig.pin_joint is PinJoint2D,
				"Hanging art uses the real pinned physics body")
	controller.set_mode(InteractionController.MODE_USE)


func check_handoffs() -> void:
	for rig: HangingSourceBody in screen.hanging_sources:
		var item := source(rig).item_id
		var before := preview.portion_stock.remaining(item) as int
		var handed := preview.ready_item_zone.handed_off[item] as int
		if await begin(rig):
			check(preview.portion_stock.available(item) == before - 1,
				"Pickup reserves one piece from the common provider")
			await move_pointer(preview.ready_item_zone.get_global_transform_with_canvas().origin, true)
			check(controller.hovered_drop_zone == preview.ready_item_zone,
				"Held piece highlights the labelled preview handoff")
			if item == &"banana":
				await snapshot(1)
			await mouse(preview.ready_item_zone.get_global_transform_with_canvas().origin, false)
			check(preview.portion_stock.remaining(item) == before - 1
				and preview.ready_item_zone.handed_off[item] == handed + 1,
				"Valid handoff applies and consumes exactly once")
			check(not controller.is_dragging() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
				"Handoff clears its piece and restores the cursor")
	check(source(screen.hanging_sources[0]).provider == source(screen.hanging_sources[1]).provider
		and source(screen.hanging_sources[0]).item_id == source(screen.hanging_sources[1]).item_id,
		"Both banana bunches use one shared stock identity")
	await snapshot(2)


func check_cancellations() -> void:
	var rig: HangingSourceBody = screen.hanging_sources[0]
	for action in ["invalid", "escape", "right_click", "mode", "modal", "provider_reset", "target_removed"]:
		controller.set_mode(InteractionController.MODE_USE)
		var before := preview.portion_stock.remaining(&"banana") as int
		if not await begin(rig):
			continue
		match action:
			"invalid":
				await mouse(screen.world_root.get_global_transform_with_canvas() * Vector2(1000, 680), false)
			"escape":
				await tap(KEY_ESCAPE)
			"right_click":
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_RIGHT
				event.pressed = true
				root.push_input(event, true)
				await frames(2)
				event = event.duplicate()
				event.pressed = false
				root.push_input(event, true)
			"mode":
				await tap(KEY_G)
			"modal":
				var modal := Control.new()
				screen.get_node("HUDLayer/RootUI/ModalStack").add_child(modal)
				await frames(2)
				modal.queue_free()
				await frames(2)
			"provider_reset":
				preview.portion_stock.reset_fixture()
				before = preview.portion_stock.remaining(&"banana")
				await frames(2)
			"target_removed":
				var target: Node2D = preview.ready_item_zone
				var target_parent := target.get_parent()
				var target_point := target.get_global_transform_with_canvas().origin
				target_parent.remove_child(target)
				await mouse(target_point, false)
				target_parent.add_child(target)
				controller.register_drop_zone(target)
		check(not controller.is_dragging() and preview.portion_stock.available(&"banana") == before
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"%s cancels and returns the reserved piece" % action)
		await mouse(point(rig), false)
	controller.set_mode(InteractionController.MODE_USE)


func check_covered_source() -> void:
	var rig: HangingSourceBody = screen.hanging_sources[2]
	await move_pointer(screen.world_root.get_global_transform_with_canvas() * Vector2(1000, 680))
	var overlay := ColorRect.new()
	overlay.position = point(rig) - Vector2(100, 130)
	overlay.size = Vector2(200, 260)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.get_node("HUDLayer/RootUI").add_child(overlay)
	# GUI hover from the previous event is still outside this new panel. The
	# very first entry must be blocked, not just subsequent covered motions.
	var before_impulses := rig.impulse_count
	var entering := InputEventMouseMotion.new()
	entering.position = point(rig)
	entering.relative = Vector2(40, 0)
	root.push_input(entering, true)
	await frames(2)
	check(rig.impulse_count == before_impulses, "First motion into new UI cannot brush the covered source")
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_USE]:
		controller.set_mode(mode)
		rig.reset_sway()
		await frames(3)
		before_impulses = rig.impulse_count
		await move_pointer(point(rig), false, Vector2(40, 0))
		await mouse(point(rig), true)
		await mouse(point(rig), false)
		check(not controller.is_dragging() and rig.impulse_count == before_impulses,
			"UI covering the source blocks brushing and extraction in %s" % mode)
	# A single motion exits the panel, sweeping across the covered food first.
	# Its unhandled endpoint must not make the hidden part of the path actionable.
	before_impulses = rig.impulse_count
	var covered := point(rig)
	var outside := covered + Vector2(260, 0)
	await move_pointer(outside, false, outside - covered)
	check(rig.impulse_count == before_impulses, "Sweeping out of UI cannot nudge covered source pixels")
	overlay.queue_free()
	await frames(3)


func check_scene_reentry_and_resize() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	var rig: HangingSourceBody = screen.hanging_sources[0]
	var before := preview.portion_stock.available(&"banana") as int
	if await begin(rig):
		root.remove_child(preview)
		await frames(2)
		check(not controller.is_dragging() and preview.portion_stock.available(&"banana") == before,
			"Detaching the complete scene returns its held piece")
		root.add_child(preview)
		await frames(3)
		check(screen.hanging_sources.size() == 3 and screen.portion_sources.size() == 7,
			"Re-entering the same scene creates no duplicate hanging or ingredient sources")
		if await begin(rig):
			await tap(KEY_ESCAPE)
			check(preview.portion_stock.available(&"banana") == before,
				"Retained scene can extract and cancel after re-entry")
	var original_size := root.size
	if await begin(rig):
		root.size = original_size + Vector2i(80, 40)
		await frames(5)
		check(not controller.is_dragging() and preview.portion_stock.available(&"banana") == before,
			"Window resize cancels pickup and returns stock")
		if await begin(rig):
			await tap(KEY_ESCAPE)
			check(rig.contains_pointer(point(rig)), "Resized moving hit target follows the visible artwork")
	root.size = original_size
	await frames(5)


func check_removed_nodes() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	var removed_rig: HangingSourceBody = screen.hanging_sources[1]
	var before := preview.portion_stock.available(&"banana") as int
	if await begin(removed_rig):
		removed_rig.queue_free()
		await frames(3)
		check(not controller.is_dragging() and preview.portion_stock.available(&"banana") == before,
			"Deleting a hanging source clears its held item and reservation")
	var rig: HangingSourceBody = screen.hanging_sources[0]
	if await begin(rig):
		var target_point: Vector2 = preview.ready_item_zone.get_global_transform_with_canvas().origin
		preview.ready_item_zone.queue_free()
		await frames(2)
		await mouse(target_point, false)
		check(not controller.is_dragging() and preview.portion_stock.available(&"banana") == before,
			"Releasing at a deleted handoff returns the item")
	preview.reset_fixture()
	await frames(3)
	check(controller.current_mode == InteractionController.MODE_NEUTRAL
		and preview.portion_stock.available(&"banana") == DevelopmentPortionStock.INITIAL_STOCK[&"banana"],
		"Reset remains usable after a source and preview target have been deleted")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Hanging input checks require a rendered window.")
		quit(2)
		return
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await frames(4)
	screen = preview.screen
	controller = preview.controller
	captures = OS.get_cmdline_user_args()
	check(screen.hanging_sources.size() == 3, "Preview has two banana sources and one biscuit bag")
	check(preview.stock_label.text.contains("Bananas") and preview.stock_label.text.contains("Biscuits"),
		"Finite ready-item stock is visibly labelled")
	await snapshot(0)
	phase = "modes"
	await check_modes()
	phase = "handoffs"
	await check_handoffs()
	phase = "cancel"
	await check_cancellations()
	phase = "covered"
	await check_covered_source()
	phase = "reentry/resize"
	await check_scene_reentry_and_resize()
	phase = "removed"
	await check_removed_nodes()
	preview.queue_free()
	await frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Leaving the scene restores the normal cursor")
	print("HANGING_SOURCE_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
