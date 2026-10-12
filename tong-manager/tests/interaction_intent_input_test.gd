extends SceneTree

# Rendered pointer/keyboard integration. Model seeding sets up vessel states;
# the interaction under test always goes through real viewport input.
var checks := 0
var failures: Array[String] = []
var preview: Node
var screen: Node2D
var world: Node2D
var controller: InteractionController
var hud: TongHud
var tray: TrayStation
var tea: IngredientPortionSource
var milk: IngredientPortionSource
var sugar: IngredientPortionSource
var captures := PackedStringArray()


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func at(authored: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas() * authored


func move_pointer(point: Vector2, held := false) -> void:
	# Keep native pointer queries and subsequent keyboard-triggered hover refresh
	# aligned with the event position. push_input alone does not move the OS mouse.
	root.warp_mouse(point)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await physics_frame
	await process_frame


func mouse(point: Vector2, pressed: bool) -> void:
	await move_pointer(point, pressed)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await physics_frame
	await process_frame


func click(point: Vector2) -> void:
	await mouse(point, true)
	await mouse(point, false)


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
		await process_frame


func select_mode(mode: StringName) -> void:
	if controller.current_mode != mode:
		await tap(KEY_G if mode == InteractionController.MODE_ORGANIZE else KEY_U)
	check(controller.current_mode == mode and hud.current_mode == mode,
		"Keyboard selects requested mode and updates the visible HUD")


func source_for(item_id: StringName) -> IngredientPortionSource:
	for source in screen.portion_sources:
		if source.item_id == item_id:
			return source
	return null


func stock(source: IngredientPortionSource) -> int:
	return preview.portion_stock.available(source.item_id)


func source_point(source: IngredientPortionSource) -> Vector2:
	return source.source_owner.get_global_transform_with_canvas().origin


func target_point(target: Node2D) -> Vector2:
	return (target.get_node("IngredientTarget") as Node2D).get_global_transform_with_canvas().origin


func begin(source: IngredientPortionSource, label: String) -> bool:
	await mouse(source_point(source), true)
	var active := controller.is_dragging() and controller.current_payload != null
	check(active, "%s real source press begins a portion" % label)
	if not active:
		await mouse(source_point(source), false)
		return false
	check(controller.current_payload.metadata.get("category") == &"ingredient_portion"
		and controller.current_payload.metadata.get("item_id") == source.item_id
		and controller.current_payload.metadata.get("quantity") == 1,
		"%s real source press creates exactly the named ingredient portion" % label)
	check(controller.current_drag_node != source.source_owner,
		"%s extracts a separate payload without dragging its container" % label)
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN,
		"%s uses one drawn portion cursor without a duplicate hardware cursor" % label)
	return true


func snapshot(index: int, label: String) -> void:
	if captures.size() > index:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[index]) == OK, label)


func seed_kettle() -> void:
	preview.kettle.discard_contents()
	check(preview.kettle.add_water(300) == 300, "Fixture prepares real kettle water")
	preview.kettle.temperature = preview.kettle.config.boiling_temperature + 10


func seed_cup(cup: Cup) -> void:
	cup.reset_clean()
	check(cup.receive_liquid(&"black_tea", 150, cup.config.ambient_temperature) == 150,
		"Fixture prepares an eligible tea-filled cup")


func check_neutral_and_controls(cups: Array[Cup]) -> void:
	check(controller.current_mode == InteractionController.MODE_NEUTRAL
		and hud.current_mode == InteractionController.MODE_NEUTRAL,
		"Preview and visible controls start neutral")
	check(not hud.organize_mode_button.button_pressed and not hud.use_mode_button.button_pressed,
		"Neutral does not leave either mode selected")
	var controls := [hud.organize_mode_button, hud.use_mode_button]
	for button in controls:
		var rect := button.get_global_rect() as Rect2
		check(rect.position.y < 100 and root.get_visible_rect().encloses(rect),
			"Selected top control fits inside the actual viewport")
	var tea_before := stock(tea)
	var tea_pose := tea.source_owner.transform
	await click(source_point(tea))
	check(not controller.is_dragging() and stock(tea) == tea_before
		and tea.source_owner.transform.is_equal_approx(tea_pose),
		"Neutral source clicks neither extract nor arrange")
	var burner: Burner = preview.stove.burners[0]
	var dial := preview.stove.get_node("DialA") as Area2D
	var heat := burner.heat_level
	await click(dial.get_global_transform_with_canvas().origin)
	check(burner.heat_level == heat, "Neutral clicks do not change heat")
	await click(preview.kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin)
	check(not controller.is_dragging() and not preview.kettle.is_held,
		"Neutral does not pick up the kettle")
	await click(cups[0].get_global_transform_with_canvas().origin)
	check(not controller.is_dragging(), "Neutral does not pick up a cup")
	var drum := world.get_node("ToolLayer/WaterDrum") as WaterDrum
	var water_before := drum.supply.remaining_ml
	await click(drum.get_global_transform_with_canvas().origin)
	check(not controller.is_dragging() and drum.supply.remaining_ml == water_before,
		"Neutral does not start a water transfer")
	await click(hud.organize_mode_button.get_global_rect().get_center())
	check(controller.current_mode == InteractionController.MODE_ORGANIZE
		and hud.organize_mode_button.button_pressed and not hud.use_mode_button.button_pressed,
		"Real top Organize button selects only Organize")
	await click(hud.organize_mode_button.get_global_rect().get_center())
	check(controller.current_mode == InteractionController.MODE_NEUTRAL,
		"Clicking active Organize returns to neutral")
	await click(hud.use_mode_button.get_global_rect().get_center())
	check(controller.current_mode == InteractionController.MODE_USE
		and hud.use_mode_button.button_pressed and not hud.organize_mode_button.button_pressed,
		"Real top Use button selects only Use")
	await click(hud.use_mode_button.get_global_rect().get_center())
	check(controller.current_mode == InteractionController.MODE_NEUTRAL,
		"Clicking active Use returns to neutral")
	await tap(KEY_G)
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "G selects Organize")
	await tap(KEY_U)
	check(controller.current_mode == InteractionController.MODE_USE, "U switches Organize to Use")
	await tap(KEY_U)
	check(controller.current_mode == InteractionController.MODE_NEUTRAL, "Active U returns to neutral")
	# No new mouse_entered event follows this keyboard switch: hover feedback must
	# refresh for the object already under the stationary pointer.
	await move_pointer(at(Vector2(850, 520)))
	await move_pointer(preview.kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin)
	check(preview.kettle._hovered, "Stationary-hover fixture enters the real kettle handle")
	await tap(KEY_U)
	if controller.cursor_service.current_state != &"hover_actionable":
		print("HOVER_DIAGNOSTIC mode=%s hovered=%s cursor=%s blocked=%s ui=%s pointer=%s" % [
			controller.current_mode, preview.kettle._hovered, controller.cursor_service.current_state,
			controller.is_world_input_blocked(), root.gui_get_hovered_control(), root.get_mouse_position()])
	check(controller.cursor_service.current_state == &"hover_actionable",
		"Stationary kettle hover refreshes its actionable cursor when Use is selected")
	await tap(KEY_U)
	check(controller.cursor_service.current_state == &"default",
		"Stationary kettle hover loses the action cursor when neutral is selected")


func check_portions(cup: Cup) -> void:
	await select_mode(InteractionController.MODE_USE)
	for source in [tea, milk, sugar]:
		await move_pointer(at(Vector2(850, 520)))
		await move_pointer(source_point(source))
		if controller.cursor_service.current_state != (&"teabag" if source == tea else &"spoon"):
			print("SOURCE_HOVER_DIAGNOSTIC item=%s state=%s point=%s actual=%s front=%s ui=%s" % [
				source.item_id, controller.cursor_service.current_state, source_point(source), root.get_mouse_position(),
				source.placement_handle._is_frontmost_at(source_point(source)), root.gui_get_hovered_control()])
		check(controller.cursor_service.current_state == (&"teabag" if source == tea else &"spoon"),
			"%s source hover shows the appropriate teabag or spoon cursor" % source.item_id)
	seed_kettle()
	var tea_before := stock(tea)
	var tea_pose := tea.source_owner.transform
	if await begin(tea, "Tea"):
		await move_pointer(at(Vector2(940, 650)), true)
		await snapshot(1, "Held teabag review capture saved")
		await mouse(target_point(preview.kettle), false)
		check(preview.kettle.contains_tea and stock(tea) == tea_before - 1
			and not controller.is_dragging(), "Real teabag release adds tea and debits one finite fixture portion")
		check(tea.source_owner.transform.is_equal_approx(tea_pose), "Successful tea extraction leaves source in place")
	seed_cup(cup)
	var milk_before := stock(milk)
	var milk_pose := milk.source_owner.transform
	if await begin(milk, "Milk"):
		await move_pointer(target_point(cup), true)
		check(controller.current_hint == "Release to add this portion · Esc cancels",
			"A valid vessel shows the release-to-add hint")
		await move_pointer(at(Vector2(940, 650)), true)
		check(controller.hovered_drop_zone == null
			and controller.current_hint == "Move this portion over a valid vessel · Esc cancels",
			"Moving from a valid vessel to empty space clears the stale release-to-add hint")
		await mouse(target_point(cup), false)
		check(cup.relish_item_ids == [&"condensed_milk"] and stock(milk) == milk_before - 1,
			"Real milk-spoon release applies one garnish and debits once")
		check(cup.volume_ml == 150 and cup.temperature == cup.config.ambient_temperature,
			"Milk review fixture does not invent volume or thermal effects")
		check(milk.source_owner.transform.is_equal_approx(milk_pose) and not controller.is_dragging(),
			"Milk extraction retains its whole source and clears the held action")
	var tea_cancel_before := stock(tea)
	if await begin(tea, "Invalid tea destination"):
		await mouse(target_point(cup), false)
		check(stock(tea) == tea_cancel_before and not controller.is_dragging()
			and cup.relish_item_ids == [&"condensed_milk"],
			"Teabag released over a cup cancels without stock or contents mutation")


func check_cancellation(cup: Cup) -> void:
	for kind in ["escape", "mode", "focus", "modal", "blocker"]:
		await select_mode(InteractionController.MODE_USE)
		var before := stock(milk)
		var pose := milk.source_owner.transform
		if not await begin(milk, "%s cancellation" % kind):
			continue
		var transient := controller.current_drag_node
		var panel: Control
		match kind:
			"escape": await tap(KEY_ESCAPE)
			"mode": await tap(KEY_G)
			"focus":
				# Deliver the operating-system focus notification without stealing
				# focus from other applications while running this test.
				controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"modal":
				panel = Panel.new()
				panel.size = Vector2(100, 80)
				controller.modal_root.add_child(panel)
			"blocker":
				panel = Control.new()
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				screen.get_node("HUDLayer/RootUI").add_child(panel)
				controller.set_world_input_blocked(panel, true)
		await process_frame
		await process_frame
		check(not controller.is_dragging() and stock(milk) == before
			and (not is_instance_valid(transient) or transient.is_queued_for_deletion()),
			"%s cancels the held portion, frees its visual and restores stock" % kind)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s restores the regular cursor" % kind)
		check(milk.source_owner.transform.is_equal_approx(pose), "%s leaves whole source untouched" % kind)
		if panel != null:
			if kind == "blocker":
				controller.set_world_input_blocked(panel, false)
			panel.queue_free()
		await process_frame
		await mouse(target_point(cup), false)
		check(stock(milk) == before and cup.relish_item_ids == [&"condensed_milk"],
			"Release after %s cannot replay the cancelled portion" % kind)
	await select_mode(InteractionController.MODE_USE)


func check_ui_overlay(cup: Cup) -> void:
	# A non-modal STOP control must block its actual screen rectangle while a
	# drag moves through GUI processing. This catches stale hovered-control
	# values if world dragging accidentally consumes GUI motion again.
	var overlay := Panel.new()
	overlay.name = "InputRegressionOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.size = Vector2(90, 90)
	screen.get_node("HUDLayer/RootUI").add_child(overlay)
	overlay.global_position = target_point(cup) - overlay.size * 0.5
	await process_frame
	var before := stock(milk)
	var garnishes := cup.relish_item_ids.duplicate()
	if await begin(milk, "Non-modal UI overlay"):
		await move_pointer(target_point(cup), true)
		check(controller.is_dragging(), "UI-overlap regression retains the active drag until release")
		if not controller.is_pointer_over_ui():
			print("UI_DIAGNOSTIC dragging=%s gui=%s zone=%s pointer=%s overlay=%s target=%s" % [
				controller.is_dragging(), root.gui_get_hovered_control(), controller.hovered_drop_zone,
				root.get_mouse_position(), overlay.get_global_rect(), target_point(cup)])
		check(controller.is_pointer_over_ui(), "Dragging into a STOP control detects its real pointer coverage")
		check(controller.hovered_drop_zone == null, "Covered vessel does not retain a valid drop highlight")
		check(controller.current_hint == "Move off the panel to a valid vessel · Esc cancels",
			"UI coverage explains why a portion cannot be released here")
		await mouse(target_point(cup), false)
		check(not controller.is_dragging() and stock(milk) == before and cup.relish_item_ids == garnishes,
			"Release over a valid vessel hidden by STOP UI cancels without debit")
	overlay.queue_free()
	await process_frame


func handle_for(item: Node2D) -> TablePlaceable:
	return item.get_node("PlacementHandle") as TablePlaceable


func base_center(item: Node2D) -> Vector2:
	var handle := handle_for(item)
	var polygons := handle.surface.get_candidate_polygons(item)
	var bounds := Rect2(polygons[0][0], Vector2.ZERO)
	for polygon in polygons:
		for point in polygon:
			bounds = bounds.expand(point)
	return world.to_local(handle.surface.to_global(bounds.get_center()))


func transfer(item: Node2D, target: Vector2, destination: PlacementSurface, label: String, grip := Vector2.ZERO) -> void:
	var origin := world.to_local(item.global_position)
	var drop_at := origin + target - base_center(item)
	await mouse(at(origin + grip), true)
	check(controller.current_drag_node == item, "%s real Organize click picks the intended whole object" % label)
	await mouse(at(drop_at + grip), false)
	check(not controller.is_dragging() and handle_for(item).surface == destination
		and base_center(item).distance_to(target) < .003, "%s real drop commits the free placement" % label)


func check_nearest_invalid(cups: Array[Cup]) -> void:
	await select_mode(InteractionController.MODE_ORGANIZE)
	var valid := cups[4]
	var dirty := cups[5]
	await transfer(valid, Vector2(1580, 870), screen.table_surface, "Nearby valid cup")
	await transfer(dirty, Vector2(1580, 885), screen.table_surface, "Nearest dirty cup")
	seed_cup(valid)
	seed_cup(dirty)
	check(dirty.mark_served() and dirty.mark_dirty(), "Fixture gives nearest cup a real dirty lifecycle")
	await select_mode(InteractionController.MODE_USE)
	var before := stock(sugar)
	if await begin(sugar, "Nearest invalid vessel"):
		var dirty_zone := dirty.get_node("IngredientTarget") as IngredientPortionTarget
		var valid_zone := valid.get_node("IngredientTarget") as IngredientPortionTarget
		var separation := target_point(dirty).distance_to(target_point(valid))
		var scale := valid_zone.get_global_transform_with_canvas().get_scale().abs()
		check(separation < valid_zone.snap_radius * maxf(scale.x, scale.y)
			and valid_zone.accepts(controller.current_payload).is_valid
			and not dirty_zone.accepts(controller.current_payload).is_valid,
			"Regression pointer is inside both valid and invalid target radii")
		await move_pointer(target_point(dirty), true)
		check(controller.hovered_drop_zone == dirty_zone,
			"Closest dirty cup wins feedback instead of jumping to a valid neighbour")
		await mouse(target_point(dirty), false)
		check(stock(sugar) == before and valid.relish_item_ids.is_empty() and dirty.relish_item_ids.is_empty(),
			"Invalid nearest-cup release cannot garnish its eligible neighbour")


func check_moved_source(cups: Array[Cup]) -> void:
	await select_mode(InteractionController.MODE_ORGANIZE)
	# Make physical tray room through the actual placement path, not reparenting
	# test doubles. The two right-hand cups were already moved above.
	for index in 4:
		await transfer(cups[index], Vector2(840 + 55 * (index % 2), 825 + 105 * (index / 2)),
			screen.table_surface, "Cup clearing tray %d" % index)
	var tea_before := stock(tea)
	await transfer(tea.source_owner, Vector2(1259, 889), tray.interior_surface, "Whole tea box onto tray")
	var local_pose := tea.source_owner.transform
	var tray_before := base_center(tray)
	await transfer(tray, tray_before + Vector2(-8, 29), screen.table_surface, "Populated tray", Vector2(0, 65))
	check(tea.source_owner.get_parent() == tray.get_contents() and tea.source_owner.transform.is_equal_approx(local_pose)
		and stock(tea) == tea_before, "Tray movement carries the source without consuming stock")
	await select_mode(InteractionController.MODE_USE)
	seed_kettle()
	var moved_pose := tea.source_owner.global_transform
	if await begin(tea, "Tea source after tray movement"):
		await mouse(target_point(preview.kettle), false)
		check(preview.kettle.contains_tea and stock(tea) == tea_before - 1
			and tea.source_owner.global_transform.is_equal_approx(moved_pose)
			and tea.source_owner.get_parent() == tray.get_contents(),
			"Moved source still extracts and commits a teabag while retaining tray ownership")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a rendered window for interaction_intent_input_test.gd; portion provider/transaction tests run headlessly.")
		quit(2)
		return
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	screen = preview.screen
	world = screen.get_node("WorldRoot")
	controller = preview.controller
	hud = screen.get_node("HUDLayer/RootUI")
	tray = world.get_node("ToolLayer/TrayStation")
	tea = source_for(&"black_tea")
	milk = source_for(&"condensed_milk")
	sugar = source_for(&"sugar")
	captures = OS.get_cmdline_user_args()
	var cups: Array[Cup] = screen.get_cups()
	check(tea != null and milk != null and sugar != null and cups.size() == 6,
		"Real preview supplies named source nodes and original cup supply")
	if tea == null or milk == null or sugar == null or cups.size() != 6:
		preview.queue_free()
		await process_frame
		quit(1)
		return
	check(preview.stock_label.text.contains("Test stock"), "Finite preview stock is explicitly labelled")
	await snapshot(0, "Initial neutral interaction review capture saved")
	await check_neutral_and_controls(cups)
	await check_portions(cups[0])
	await check_cancellation(cups[0])
	await check_ui_overlay(cups[0])
	await check_nearest_invalid(cups)
	await check_moved_source(cups)
	await snapshot(2, "Final moved-source interaction review capture saved")
	preview.queue_free()
	await process_frame
	await process_frame
	print("INTERACTION_INTENT_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
