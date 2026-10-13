extends SceneTree

const PREVIEW := preload("res://scenes/development/InventoryPreview.tscn")
const CONFIG := preload("res://data/balance/demo_day_1.tres")

var checks := 0
var failures: Array[String] = []
var preview: Node
var screen: Node2D
var controller: InteractionController
var stock: InventoryState
var supply: DailyWaterSupply
var game_state: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for index in count:
		await process_frame
		await physics_frame


func bind_view() -> void:
	screen = preview.screen
	controller = preview.controller
	check(preview.portion_stock == stock, "Review scene uses the run's real InventoryState")
	check(screen.portion_sources.size() == 7, "All four containers and three hanging pictures have source adapters")
	for source: IngredientPortionSource in screen.portion_sources:
		check(source.provider == stock, "%s reads the shared production provider" % source.source_owner.name)
	check(drum().supply == supply, "Drum retains the authoritative measured water supply")
	check(preview.stock_label.text.begins_with("Available / remaining"), "The stock panel distinguishes reservations from remaining stock")
	check(preview.get_node("PreviewUI/Root/Panel/Margin/Rows/FixtureNote").text.contains("targets remain test fixtures"),
		"Scene labels its remaining production target integration boundary")


func source_named(node_name: String) -> IngredientPortionSource:
	return screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/%s/IngredientSource" % node_name) as IngredientPortionSource


func ready_source(index: int) -> IngredientPortionSource:
	return screen.hanging_sources[index].get_node("ReadyItemSource") as IngredientPortionSource


func drum() -> WaterDrum:
	return screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func take(source: IngredientPortionSource) -> HeldItemPayload:
	var before := stock.remaining(source.item_id)
	var transform := source.source_owner.global_transform
	check(source.begin_portion(point(source.source_owner)), "%s starts a physical-source portion" % source.item_id)
	check(stock.remaining(source.item_id) == before and stock.available(source.item_id) == before - 1,
		"Physical pickup reserves one unit without consuming it")
	check(source.source_owner.global_transform.is_equal_approx(transform), "Portion pickup leaves its whole source in place")
	return controller.current_payload


func returned(item_id: StringName, before: int, reason: String) -> void:
	check(controller.current_payload == null and not controller.is_dragging(), "%s clears held state" % reason)
	check(stock.remaining(item_id) == before and stock.available(item_id) == before, "%s releases stock without consuming it" % reason)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s restores the cursor" % reason)


func check_physical_commands() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	var kettle := preview.kettle as Kettle
	var water_before := supply.remaining_ml
	check(drum().begin_drag(point(drum())), "Real drum starts a measured water transfer")
	controller.release_drop(point(kettle.get_node("WaterFillTarget")))
	check(kettle.volume_ml > 0 and is_equal_approx(supply.remaining_ml + kettle.volume_ml, water_before),
		"Real drum-to-kettle drop conserves the one daily water balance")
	check(not controller.is_dragging(), "Water fill finishes its gesture")
	var tea := source_named("TeaBox")
	var tea_before := stock.remaining(&"black_tea")
	take(tea)
	controller.release_drop(point(kettle.get_node("IngredientTarget")))
	returned(&"black_tea", tea_before, "Unboiled kettle rejects tea")
	check(not kettle.contains_tea, "Rejected tea leaves the kettle unchanged")
	kettle.temperature = kettle.config.boiling_temperature
	var tea_payload := take(tea)
	controller.release_drop(point(kettle.get_node("IngredientTarget")))
	check(kettle.contains_tea and stock.remaining(&"black_tea") == tea_before - 1,
		"Boiled-water target commits one teabag through the actual source/target contract")
	check(not kettle.get_node("IngredientTarget").try_apply_drop(tea_payload), "Replayed teabag cannot apply or debit twice")
	check(stock.available(&"black_tea") == tea_before - 1, "Successful tea use leaves no reservation")
	var cup := screen.get_cups()[0] as Cup
	cup.reset_clean()
	cup.receive_liquid(&"black_tea", 150, 65)
	for name_and_id in [["SugarCan", &"sugar"], ["CondensedMilkCan", &"condensed_milk"]]:
		var item_id: StringName = name_and_id[1]
		var before := stock.remaining(item_id)
		var payload := take(source_named(name_and_id[0]))
		controller.release_drop(point(cup.get_node("IngredientTarget")))
		check(cup.relish_item_ids.has(item_id) and stock.remaining(item_id) == before - 1,
			"Actual cup accepts one %s spoon and consumes once" % item_id)
		check(not cup.get_node("IngredientTarget").try_apply_drop(payload), "Replayed spoon cannot debit twice")
	check(source_named("SugarCanEnglish").provider == stock
		and source_named("SugarCanEnglish").provider.available(&"sugar") == stock.remaining(&"sugar"),
		"The second sugar picture immediately observes the same depleted stock")
	var milk_before := stock.remaining(&"condensed_milk")
	cup.reset_clean()
	cup.receive_liquid(&"water", 100, 60)
	take(source_named("CondensedMilkCan"))
	controller.release_drop(point(cup.get_node("IngredientTarget")))
	returned(&"condensed_milk", milk_before, "Incompatible water cup rejects a spoon")
	check(cup.relish_item_ids.is_empty(), "Rejected spoon has no target effect")
	for index in [0, 1, 2]:
		var source := ready_source(index)
		var before := stock.remaining(source.item_id)
		var handed: int = preview.ready_item_zone.handed_off[source.item_id]
		var payload := take(source)
		controller.release_drop(point(preview.ready_item_zone))
		check(stock.remaining(source.item_id) == before - 1 and preview.ready_item_zone.handed_off[source.item_id] == handed + 1,
			"Fixed %s source consumes shared inventory through the labelled handoff fixture" % source.source_owner.name)
		check(not preview.ready_item_zone.try_apply_drop(payload), "Repeated ready-item command cannot consume again")
	check(preview.stock_label.text.contains("Bananas  %d / %d" % [stock.available(&"banana"), stock.remaining(&"banana")]),
		"Visible panel immediately reflects shared banana consumption")


func check_interruptions() -> void:
	var sugar := source_named("SugarCan")
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE]:
		controller.set_mode(mode)
		check(not sugar.begin_portion(point(sugar.source_owner)), "Stock cannot be extracted outside Use")
	for reason in ["invalid", "mode", "focus", "modal", "explicit_block"]:
		controller.set_mode(InteractionController.MODE_USE)
		var before := stock.remaining(&"sugar")
		take(sugar)
		match reason:
			"invalid": controller.release_drop(Vector2(-200, -200))
			"mode": controller.set_mode(InteractionController.MODE_ORGANIZE)
			"focus": controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"modal":
				var modal := Control.new()
				controller.modal_root.add_child(modal)
				await frames()
				check(controller.is_world_input_blocked() and not sugar.begin_portion(point(sugar.source_owner)),
					"Actual ModalStack blocks new extraction")
				modal.queue_free()
			"explicit_block": controller.set_world_input_blocked(preview, true)
		await frames()
		returned(&"sugar", before, reason)
		controller.set_world_input_blocked(preview, false)
	controller.set_mode(InteractionController.MODE_USE)
	var before := stock.remaining(&"sugar")
	var payload := take(sugar)
	var original_day := supply.day_id
	preview.reset_fixture()
	preview._reload_scene()
	check(controller.current_payload == payload and current_scene == preview and supply.day_id == original_day,
		"Reset/reload review controls cannot interrupt an active gesture")
	controller.cancel_drag()
	returned(&"sugar", before, "Blocked review controls")
	var milk := source_named("CondensedMilkCan")
	before = stock.remaining(&"condensed_milk")
	payload = take(milk)
	var ghost := payload.world_node
	milk.queue_free()
	await frames()
	returned(&"condensed_milk", before, "Removed source adapter")
	check(not is_instance_valid(ghost), "Removed source disposes the held visual")
	before = stock.remaining(&"banana")
	payload = take(ready_source(0))
	var zone := preview.ready_item_zone as DropZone
	var target_point := point(zone)
	zone.queue_free()
	check(not zone.try_apply_drop(payload), "A queued target refuses a stale command immediately")
	await frames()
	controller.release_drop(target_point)
	returned(&"banana", before, "Removed handoff target")


func check_scene_lifecycle() -> void:
	var quantities := stock.quantities
	var water := supply.remaining_ml
	var day := supply.day_id
	var old: WeakRef = weakref(preview)
	preview._reload_scene()
	await frames(4)
	preview = current_scene
	check(old.get_ref() == null, "Reload button replaces and frees the previous scene")
	bind_view()
	check(stock.quantities == quantities and supply.remaining_ml == water and supply.day_id == day,
		"Actual scene reload preserves every stock count and same-day measured water")
	controller.set_mode(InteractionController.MODE_USE)
	var before := stock.remaining(&"sugar")
	var payload := take(source_named("SugarCan"))
	var portion := payload.metadata.portion as IngredientPortion
	var ghost := payload.world_node
	preview.queue_free()
	await frames(3)
	check(stock.quantities == quantities and stock.available(&"sugar") == before,
		"Scene destruction releases the held reservation without refunding prior consumption")
	check(not portion.is_available() and not is_instance_valid(ghost) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"Scene destruction retires its payload/visual/cursor")
	preview = PREVIEW.instantiate()
	root.add_child(preview)
	current_scene = preview
	await frames()
	bind_view()
	check(stock.quantities == quantities and supply.remaining_ml == water and supply.day_id == day,
		"New scene instance reuses existing supplies rather than reseeding them")
	controller.set_mode(InteractionController.MODE_USE)
	payload = take(source_named("SugarCan"))
	controller.cancel_drag()
	returned(&"sugar", before, "Fresh source after scene replacement")
	var custom := CONFIG.duplicate(true)
	custom.starting_inventory[&"banana"] = 7
	custom.starting_inventory[&"condensed_milk"] = 3
	custom.daily_water_ml = 1700.0
	screen.day_config = custom
	preview.reset_fixture()
	check(game_state.inventory == stock and game_state.water_supply == supply,
		"Explicit reset preserves shared authority identities and observer bindings")
	check(stock.quantities == custom.starting_inventory and stock.available(&"banana") == 7
		and stock.available(&"condensed_milk") == 3, "Explicit reset uses the active scene's configured starting counts")
	check(supply.day_id == day + 1 and supply.remaining_ml == 1700.0,
		"Only explicit new-day reset restores the configured measured water allocation")
	check(preview.stock_label.text.contains("Bananas  7 / 7") and drum().remaining_label.text.contains("1700"),
		"Stock and water views immediately reflect the configured reset")
	check(controller.current_mode == InteractionController.MODE_NEUTRAL and not portion.is_available(),
		"Reset returns Neutral without revalidating old payloads")


func settle_inventory(modal: Control) -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while (modal.book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not modal.book.busy and not modal.is_traveling(), "Pantry view settles before fixture export")
	await frames()


func take_from_pantry(modal: Control, item_id: StringName) -> HeldItemPayload:
	var before := stock.remaining(item_id)
	check(modal.begin_inventory_export(item_id, modal.inventory_item_screen_rect(item_id).get_center()),
		"Pantry begins %s for the actual review target" % item_id)
	var payload := controller.current_payload
	check(payload != null and payload.source == &"khata" and payload.item_id == item_id,
		"Actual review target receives the shared Khata portion payload")
	check(stock.remaining(item_id) == before and stock.available(item_id) == before - 1,
		"Pantry pickup reserves without consuming review-scene stock")
	return payload


func check_pantry_fixture_view(modal: Control, peeking: bool) -> void:
	check(not modal.exporting and not controller.is_dragging() and not controller.is_modal_export_active(),
		"Actual review target finishes the owned pantry export")
	check(modal.is_peeking() == peeking and modal.is_open() != peeking and modal.page_index == 0,
		"Actual review drop restores its originating pantry view and spread")
	check(controller.current_mode == InteractionController.MODE_NEUTRAL and controller.is_world_input_blocked() != peeking,
		"Review target permission preserves Neutral and the correct reading lock")


func check_pantry_review_targets() -> void:
	# These are the review scene's existing provisional #59/#66 adapters. This
	# integration check does not select final recipe doses or customer rules.
	var modal := screen.khata_modal as Control
	modal.book.sound_enabled = false
	var kettle := preview.kettle as Kettle
	var cup := screen.get_cups()[0] as Cup
	var kettle_target := kettle.get_node("IngredientTarget") as DropZone
	var cup_target := cup.get_node("IngredientTarget") as DropZone
	var ready_target := preview.ready_item_zone as DropZone
	for peeking in [true, false]:
		controller.set_mode(InteractionController.MODE_NEUTRAL)
		# Only vessel conditions are set up; the real shared provider is retained.
		kettle.discard_contents()
		kettle.add_water(300)
		kettle.temperature = kettle.config.ambient_temperature
		cup.reset_clean()
		var quantities := stock.quantities
		var water_before := supply.remaining_ml
		check(modal.open_peek() if peeking else modal.open(), "Review scene opens the requested populated pantry")
		await settle_inventory(modal)
		modal.select_page(0)
		await settle_inventory(modal)
		var before := stock.remaining(&"black_tea")
		take_from_pantry(modal, &"black_tea")
		controller.release_drop(point(kettle_target))
		returned(&"black_tea", before, "Pantry teabag rejected by the actual cold-water fixture")
		check(not kettle.contains_tea, "Invalid pantry tea has no kettle effect")
		check_pantry_fixture_view(modal, peeking)
		var payload := take_from_pantry(modal, &"black_tea")
		kettle.temperature = kettle.config.boiling_temperature
		controller.release_drop(point(kettle_target))
		check(kettle.contains_tea and stock.remaining(&"black_tea") == before - 1,
			"Actual boiling-kettle adapter accepts one Khata teabag")
		check(not kettle_target.try_apply_drop(payload) and stock.available(&"black_tea") == before - 1,
			"Replayed Khata teabag cannot apply or debit twice")
		check_pantry_fixture_view(modal, peeking)
		before = stock.remaining(&"sugar")
		cup.receive_liquid(&"water", 100, 60)
		take_from_pantry(modal, &"sugar")
		controller.release_drop(point(cup_target))
		returned(&"sugar", before, "Pantry spoon rejected by incompatible water in the actual cup")
		check(cup.relish_item_ids.is_empty(), "Invalid pantry spoon has no cup effect")
		check_pantry_fixture_view(modal, peeking)
		cup.reset_clean()
		cup.receive_liquid(&"black_tea", 150, 65)
		for item_id: StringName in [&"sugar", &"condensed_milk"]:
			before = stock.remaining(item_id)
			var relishes := cup.relish_item_ids.size()
			payload = take_from_pantry(modal, item_id)
			controller.release_drop(point(cup_target))
			check(cup.relish_item_ids.has(item_id) and cup.relish_item_ids.size() == relishes + 1
				and stock.remaining(item_id) == before - 1 and stock.available(item_id) == before - 1,
				"Actual tea-cup adapter accepts one Khata %s spoon" % item_id)
			check(not cup_target.try_apply_drop(payload) and cup.relish_item_ids.size() == relishes + 1,
				"Replayed Khata spoon cannot change the target or consume again")
			check_pantry_fixture_view(modal, peeking)
		before = stock.remaining(&"banana")
		var handed_before: int = ready_target.handed_off[&"banana"]
		take_from_pantry(modal, &"banana")
		controller.release_drop(point(kettle_target))
		returned(&"banana", before, "Pantry piece rejected by an incompatible actual vessel target")
		check(ready_target.handed_off[&"banana"] == handed_before, "Invalid ready-item release records no sample handoff")
		check_pantry_fixture_view(modal, peeking)
		for item_id: StringName in [&"banana", &"biscuits"]:
			before = stock.remaining(item_id)
			var handed: int = ready_target.handed_off[item_id]
			payload = take_from_pantry(modal, item_id)
			controller.release_drop(point(ready_target))
			check(ready_target.handed_off[item_id] == handed + 1 and stock.remaining(item_id) == before - 1
				and stock.available(item_id) == before - 1,
				"Actual labelled handoff adapter accepts one Khata %s piece" % item_id)
			check(not ready_target.try_apply_drop(payload) and ready_target.handed_off[item_id] == handed + 1,
				"Replayed Khata ready-item delivery cannot hand off or debit again")
			check_pantry_fixture_view(modal, peeking)
		for item_id: StringName in [&"black_tea", &"sugar", &"condensed_milk", &"banana", &"biscuits"]:
			check(stock.remaining(item_id) == quantities[item_id] - 1
				and modal.inventory_page.item_display(item_id).remaining == stock.remaining(item_id),
				"All valid/invalid review gestures debit exactly one %s and refresh its pantry count" % item_id)
		check(supply.remaining_ml == water_before, "Ingredient and ready-item exports never debit the separate measured-water supply")
		modal.close()
		await settle_inventory(modal)


func check_sample_serving_volume() -> void:
	# The customer remains a plain-black-tea fixture; only its serving minimum
	# now follows the approved recipe metadata, without production order logic.
	var recipe: Resource = root.get_node("Catalog").get_recipe(&"cha_no_sugar")
	var minimum: float = recipe.minimum_serving_volume_ml
	check(minimum == 225.0, "Sample service reads the approved 225ml minimum metadata")
	var cup := screen.get_cups()[0] as Cup
	cup.reset_clean()
	cup.receive_liquid(&"black_tea", minimum - 1, 70)
	controller.set_mode(InteractionController.MODE_USE)
	var quantities := stock.quantities
	var water_before := supply.remaining_ml
	check(cup.begin_interaction_drag(point(cup)), "Underfilled sample cup starts a real serving gesture")
	var target := preview.service_zone as DropZone
	check(not target.accepts(controller.current_payload).is_valid, "Sample service rejects volume just below its recipe minimum")
	controller.release_drop(point(target))
	check(not controller.is_dragging() and cup.state == Cup.CupState.FILLED and cup.assigned_order_id.is_empty(),
		"Rejected underfilled sample keeps the cup and records no service")
	cup.receive_liquid(&"black_tea", 1, 70)
	check(cup.begin_interaction_drag(point(cup)), "Minimum-volume sample starts a real serving gesture")
	check(target.accepts(controller.current_payload).is_valid, "Sample service accepts exactly the approved minimum")
	controller.release_drop(point(target))
	check(not controller.is_dragging() and cup.state == Cup.CupState.SERVED and not cup.assigned_order_id.is_empty(),
		"Accepted sample records its normal served lifecycle")
	check(stock.quantities == quantities and supply.remaining_ml == water_before, "Service never charges ingredients or water again")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_state = root.get_node("GameState")
	check(game_state.reset_demo_state(CONFIG), "Test begins with the authored demo allocation")
	stock = game_state.inventory
	supply = game_state.water_supply
	preview = PREVIEW.instantiate()
	root.add_child(preview)
	current_scene = preview
	await frames(3)
	bind_view()
	check(stock.quantities == CONFIG.starting_inventory and supply.remaining_ml == CONFIG.daily_water_ml,
		"Opening InventoryPreview preserves configured run supplies")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[0]) == OK, "Initial inventory review capture saved")
	await check_physical_commands()
	await check_interruptions()
	await check_scene_lifecycle()
	await check_pantry_review_targets()
	check_sample_serving_volume()
	preview.queue_free()
	await frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Final scene teardown restores the cursor")
	print("INVENTORY_PREVIEW: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
