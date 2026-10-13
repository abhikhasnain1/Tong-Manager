extends SceneTree
## Production modal ownership and live-world checks; clock/patience are explicit contract fixtures.

class ProgressFixture extends Node:
	var elapsed := 0.0
	var patience := 100.0
	func _process(delta: float) -> void:
		elapsed += delta
		patience -= delta

class ExportTarget extends DropZone:
	var controller: InteractionController
	var applied := 0
	func _init() -> void:
		var preview := Sprite2D.new()
		preview.name = "DebugPreview"
		preview.hide()
		add_child(preview)
		snap_radius = 35
	func is_relevant_to(payload: HeldItemPayload) -> bool:
		return payload != null and payload.metadata.get("category") == &"ingredient_portion"
	func accepts(payload: HeldItemPayload) -> DropValidation:
		if not is_inside_tree() or is_queued_for_deletion() or not controller.can_address_drop_zone(payload, self):
			return DropValidation.invalid("Inactive contract target")
		var portion := payload.metadata.get("portion") as IngredientPortion
		return DropValidation.valid() if portion != null and portion.is_available() else DropValidation.invalid("Expired portion")
	func try_apply_drop(payload: HeldItemPayload) -> bool:
		return accepts(payload).is_valid and (payload.metadata.portion as IngredientPortion).commit(_apply)
	func _apply() -> bool:
		applied += 1
		return true

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var controller: InteractionController
var modal: Control
var book: Node2D
var kettle: Kettle
var stove: Stove
var stock: InventoryState
var water: DailyWaterSupply


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 3) -> void:
	for index in count:
		await process_frame
		await physics_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while (book.busy or modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not book.busy and not modal.is_traveling(), "Notebook animation and cover journey settle")
	await frames()


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func close_modal() -> void:
	modal.close()
	await settle()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Closing relinquishes modal input ownership")


func sugar() -> IngredientPortionSource:
	return screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/SugarCan/IngredientSource") as IngredientPortionSource


func check_modes_and_pages() -> void:
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_USE]:
		controller.set_mode(mode)
		check(modal.open(), "%s can open the notebook" % mode)
		check(modal.is_open() and controller.is_world_input_blocked(), "Opening animation already owns modal input")
		await settle()
		check(controller.current_mode == mode, "Opening preserves the selected interaction mode")
		check(not sugar().begin_portion(point(sugar().source_owner)), "Modal prevents ordinary source extraction")
		check(not kettle.begin_drag(point(kettle.get_node("GripAnchor"))), "Modal prevents ordinary kettle pickup")
		await close_modal()
		check(controller.current_mode == mode, "Close restores the prior %s selection" % mode)
	check(modal.open(), "Notebook opens for shell page selection")
	await settle()
	for index in range(4):
		modal.select_page(index)
		await settle()
		check(modal.page_index == index and book.spread == index, "Shell page %d follows the shared notebook spread" % index)
		var pages := modal.get_node("Pages")
		for child_index in pages.get_child_count():
			var child := pages.get_child(child_index) as Control
			check(child.visible == (child_index == index), "Only the selected shell page is active")
	await close_modal()


func settle_peek() -> void:
	await settle()
	await create_timer(0.4).timeout
	await frames()


func check_peek_world_and_handoff() -> void:
	var peek := modal.peek as Control
	# Put the source beside the page; covered sources are intentionally unavailable.
	var source_transform := sugar().source_owner.global_transform
	sugar().source_owner.global_position = Vector2(960, 700)
	check(peek.get_parent() == controller.modal_root.get_parent()
		and not controller.modal_root.is_ancestor_of(peek), "Peek is a paper-sized sibling outside the blocking ModalStack")
	var quantities := stock.quantities
	var supply := water.remaining_ml
	var day := water.day_id
	var identity := [screen.get_instance_id(), kettle.get_instance_id()]
	check(modal.open_peek(), "Closed notebook can open its nonmodal Peek")
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(),
		"Peek does not acquire full-notebook or world-input ownership")
	check(book.opened and not book.busy and is_equal_approx(book.fold_amount, 1.0),
		"Peek retains the opened shared notebook with its left half folded underneath")
	check(modal.visible and not modal.is_modal_input_active(),
		"Visible shared-book host explicitly relinquishes full-modal input ownership in Peek")
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_USE]:
		controller.set_mode(mode)
		await frames()
		check(modal.is_peeking() and controller.current_mode == mode and not controller.is_world_input_blocked(),
			"Peek survives a deliberate %s mode change without blocking the stall" % mode)
	check(sugar().begin_portion(point(sugar().source_owner)), "Use can reserve a physical-source portion while Peek remains open")
	check(modal.is_peeking() and controller.is_dragging(), "A world gesture does not dismiss Peek")
	modal.close_peek()
	check(controller.is_dragging() and stock.available(&"sugar") == stock.remaining(&"sugar") - 1,
		"Closing nonmodal Peek does not cancel an unrelated world reservation")
	await settle()
	check(controller.is_dragging() and not controller.is_world_input_blocked(),
		"Nonmodal return journey preserves the independent gesture without borrowing a world lock")
	check(modal.open_peek(), "Peek can reopen without interrupting a held world portion")
	await settle_peek()
	check(controller.is_dragging(), "Peek arrival leaves the held world portion intact")
	controller.cancel_drag()
	await frames()
	check(stock.quantities == quantities and stock.available(&"sugar") == stock.remaining(&"sugar"),
		"Canceling a world portion in Peek preserves stock and releases its reservation")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	var owner_node := sugar().placement_handle.item
	var original := owner_node.transform
	var original_parent := owner_node.get_parent()
	check(sugar().placement_handle.begin_drag(point(owner_node)), "Organize can move a whole source while Peek remains open")
	controller.update_drag(point(owner_node) + Vector2(-90, -35))
	check(modal.is_peeking(), "Moving a whole source leaves Peek open")
	check(modal.open(), "Peek expands into the full notebook during a world gesture")
	check(not controller.is_dragging() and owner_node.get_parent() == original_parent
		and owner_node.transform.is_equal_approx(original), "Expanding cancels and restores the preexisting world drag")
	await settle()
	check(modal.is_open() and not modal.is_peeking() and controller.is_world_input_blocked(),
		"Expansion transfers ownership to only the full notebook")
	check(not sugar().placement_handle.begin_drag(point(owner_node)), "Expanded notebook blocks ordinary placement")
	check(modal.open_peek(), "Full notebook can collapse into Peek")
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(),
		"Collapse relinquishes full modal ownership before Peek becomes interactive")
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Full-to-Peek transition preserves the selected mode")
	controller.set_mode(InteractionController.MODE_USE)
	kettle.discard_contents()
	kettle.add_water(300)
	kettle.temperature = 50
	stove.burners[0].set_heat(1)
	var progress := ProgressFixture.new()
	screen.add_child(progress)
	var temperature := kettle.temperature
	var elapsed := progress.elapsed
	var patience := progress.patience
	await create_timer(0.15).timeout
	check(kettle.temperature > temperature and progress.elapsed > elapsed and progress.patience < patience and not paused,
		"Peek leaves real heat and explicit clock/patience contract fixtures advancing")
	check(identity == [screen.get_instance_id(), kettle.get_instance_id()] and stock.quantities == quantities
		and water.remaining_ml == supply and water.day_id == day, "Peek transitions preserve live identity, stock and same-day water")
	stove.burners[0].set_heat(0)
	progress.queue_free()
	modal.close_peek()
	await settle()
	check(not modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(),
		"Closing Peek leaves neither notebook view nor a world lock")
	sugar().source_owner.global_transform = source_transform


func check_peek_lifecycle() -> void:
	check(modal.open_peek(), "Peek opens for external visibility cleanup")
	await settle_peek()
	(modal.peek as Control).hide()
	await frames()
	check(not modal.is_peeking() and not controller.is_world_input_blocked() and not book.opened and not book.busy,
		"Externally hiding Peek retires the shared renderer as well as its input state")
	check(modal.open_peek(), "Externally hidden Peek can open afresh")
	await settle_peek()
	var ui_root := modal.peek.get_parent() as Control
	ui_root.hide()
	await frames()
	check(not modal.is_peeking() and not modal.peek.visible, "Hiding the UI ancestor clears Peek rather than retaining an invisible session")
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	modal._input(key)
	check(not modal.is_peeking() and not modal.is_open() and not modal.open_peek() and not modal.open(),
		"Hidden HUD rejects K and direct open requests without acquiring ownership")
	ui_root.show()
	await frames()
	check(not modal.is_peeking() and not controller.is_world_input_blocked(), "Showing the scene UI again does not resurrect stale Peek")
	check(modal.open_peek(), "Peek can start afresh after its ancestor was hidden")
	await settle_peek()
	controller.set_mode(InteractionController.MODE_USE)
	var fixture := replacement_controller(InteractionController.MODE_ORGANIZE)
	var replacement := fixture.controller as InteractionController
	modal.configure(replacement)
	await frames()
	check(not modal.is_peeking() and not modal.is_open() and not replacement.is_world_input_blocked()
		and not modal.visible and not book.is_visible_in_tree() and modal.cover.visible,
		"Controller replacement retires the Peek renderer and restores its world cover without transferring a lock")
	check(controller.current_mode == InteractionController.MODE_USE and replacement.current_mode == InteractionController.MODE_ORGANIZE,
		"Peek controller replacement preserves both selections")
	check(modal.open_peek(), "Replacement controller can start a new Peek session")
	await settle_peek()
	(fixture.host as Node).remove_child(replacement)
	await frames()
	check(not modal.is_peeking() and not modal.open_peek(), "Removed controller retires Peek and cannot reopen it")
	modal.configure(controller)
	replacement.queue_free()
	(fixture.host as Node).queue_free()
	check(modal.open_peek(), "Original controller can reopen Peek after replacement removal")
	await settle_peek()
	root.remove_child(screen)
	await frames()
	root.add_child(screen)
	await frames()
	check(not modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked(),
		"Scene exit/reentry clears Peek as well as full modal ownership")
	check(modal.open_peek(), "Reentered live scene can start Peek again")
	await settle_peek()
	modal.close_peek()
	await settle()
	check(modal.open(), "Ancestor visibility test starts a full notebook")
	await settle()
	ui_root.hide()
	await frames()
	check(not modal.is_open() and not modal.visible and not book.busy and not book.opened,
		"Hiding the full notebook's ancestor clears its local visibility and active motion")
	ui_root.show()
	await frames()
	check(not controller.is_world_input_blocked() and not modal.is_open() and not modal.is_peeking(),
		"Restoring the HUD after full-modal hide leaves no invisible modal blocker")
	check(modal.open(), "Pending-collapse visibility test opens full notebook")
	await settle()
	check(modal.open_peek(), "Full notebook requests a delayed Peek before ancestor hide")
	ui_root.hide()
	await frames()
	ui_root.show()
	await settle_peek()
	check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked(),
		"Hidden pending collapse cannot resurrect Peek after the HUD returns")


func check_peek_reentrant_handoff() -> void:
	check(modal.open(), "Reentrant close test begins a full notebook")
	await settle()
	modal.closed.connect(modal.close, CONNECT_ONE_SHOT)
	check(modal.open_peek(), "Full-to-Peek starts before a close observer")
	await settle_peek()
	check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked()
		and not modal.visible and modal.cover.visible,
		"A synchronous close observer cancels pending Peek and restores the world cover instead of resurrecting it")
	check(modal.open(), "Reentrant open test begins a full notebook")
	await settle()
	modal.closed.connect(modal.open, CONNECT_ONE_SHOT)
	check(modal.open_peek(), "Full-to-Peek starts before an open observer")
	await settle_peek()
	check(modal.is_open() and not modal.is_peeking() and controller.is_world_input_blocked() and book.opened,
		"A synchronous open observer retains full ownership without a later automatic collapse")
	await close_modal()
	check(modal.open(), "Reentrant Peek observer begins a full notebook")
	await settle()
	var observation := {"accepted": false, "traveled": true, "page": -1}
	modal.closed.connect(func():
		observation.accepted = modal.open_peek()
		observation.traveled = modal.is_traveling()
		observation.page = book.spread, CONNECT_ONE_SHOT)
	var spread: int = book.spread
	check(modal.open_peek(), "Full-to-Peek starts before a Peek observer")
	await settle_peek()
	check(observation.accepted and not observation.traveled and observation.page == spread
		and modal.is_peeking() and not modal.is_open() and book.spread == spread,
		"A synchronous Peek observer keeps the folded page in place without replaying a world departure")
	modal.close_peek()
	await settle()


func page_ids() -> Array[int]:
	var ids: Array[int] = []
	for page in book._pages:
		ids.append(page.get_instance_id())
	return ids


func check_shared_folded_pages() -> void:
	var renderer_id := book.get_instance_id()
	var cached_pages := page_ids()
	check(modal.open(), "Shared-page test opens the full book")
	await settle()
	modal.select_page(1)
	await settle()
	var right_page_id: int = book._pages[3].get_instance_id()
	var full_rect: Rect2 = book.get_visible_book_rect()
	check(modal.open_peek(), "Recipes spread starts its fold into Peek")
	check(book.opened and book.busy and book.folding and is_equal_approx(book.opening_amount, 1.0),
		"Folding keeps the opened book alive rather than closing its cover")
	await create_timer(0.12).timeout
	check(book.fold_amount > 0.0 and book.fold_amount < 1.0 and book.opened,
		"Full-to-Peek passes through a continuous partial-fold state")
	check(book.spread == 1 and book.get_visible_page_index() == 3 and book._pages[3].get_instance_id() == right_page_id,
		"The Recipes right-hand page stays the same object throughout folding")
	await settle_peek()
	check(book.get_instance_id() == renderer_id and page_ids() == cached_pages,
		"Peek reuses the exact book and cached pages instead of creating a second rendering")
	check(book.get_visible_book_rect().size.x < full_rect.size.x and is_equal_approx(book.fold_amount, 1.0),
		"Settled Peek displays a narrower folded book")
	for index in range(4):
		modal.select_page(index)
		await settle()
		check(modal.is_peeking() and modal.page_index == index and book.get_visible_page_index() == index * 2 + 1,
			"Peek navigation selects the current right-hand page of spread %d" % index)
		var right_id: int = book._pages[index * 2 + 1].get_instance_id()
		check(modal.open(), "Spread %d unfolds into full reading view" % index)
		check(book.opened and is_equal_approx(book.opening_amount, 1.0),
			"Unfold begins from the same open notebook without a closed-cover intermediate")
		await settle()
		check(modal.page_index == index and book.get_visible_page_index() == index * 2 + 1
			and book._pages[index * 2 + 1].get_instance_id() == right_id and is_zero_approx(book.fold_amount),
			"Unfold retains spread %d and its exact matching right page" % index)
		check(modal.open_peek(), "Spread %d folds back into Peek" % index)
		await settle_peek()
		check(modal.is_peeking() and book.spread == index and page_ids() == cached_pages,
			"Returning to Peek retains spread %d and all cached page identities" % index)
	book.request_turn(1)
	await frames()
	check(book.spread == 3 and not book.busy, "Folded navigation cannot advance beyond the last spread")
	book.select_page(0)
	await settle()
	book.request_turn(-1)
	await frames()
	check(book.spread == 0 and not book.busy, "Folded navigation cannot precede the first spread")
	modal.close_peek()
	await settle()
	check(not modal.is_peeking() and not modal.is_open() and page_ids() == cached_pages,
		"Closing the folded notebook preserves the reusable page cache")


func wait_for_return(value: KhataModal) -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while value.book.busy and not value.is_traveling() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(value.is_traveling(), "Closed cover begins its return journey")


func check_cover_journey() -> void:
	var cover := modal.cover as Sprite2D
	check(is_instance_valid(cover) and cover.is_visible_in_tree(), "Normal scene binds its authored world notebook cover")
	if not is_instance_valid(cover):
		return
	var home := cover.get_global_transform_with_canvas()
	var authored := cover.transform
	var quantities := stock.quantities
	var supply := water.remaining_ml
	var selected_mode := controller.current_mode
	check(modal.open(), "Full reading begins with a cover departure")
	check(modal.is_traveling() and not cover.visible and modal.is_open() and controller.is_world_input_blocked(),
		"Full departure leases the world cover and owns input from the beginning")
	var flying := modal._travel_cover as Sprite2D
	check(is_instance_valid(flying) and flying.texture == cover.texture
		and flying.get_global_transform_with_canvas().is_equal_approx(home),
		"Departure uses the exact authored cover art and canvas transform")
	check(not modal.open() and not modal.open_peek(), "Repeated open requests cannot start a second departure")
	await settle()
	check(book.opened and not cover.visible and cover.transform.is_equal_approx(authored),
		"Reading retains one leased cover without changing its world placement")
	modal.close()
	check(book.busy and not modal.is_traveling() and modal.is_open(),
		"Full close first animates the cover in the reading position")
	await wait_for_return(modal)
	check(not book.opened and not book.busy and is_zero_approx(book.opening_amount),
		"The full notebook is closed before its return flight starts")
	check(modal.is_open() and controller.is_world_input_blocked() and not cover.visible,
		"The full return retains exclusive input until its world handoff")
	flying = modal._travel_cover as Sprite2D
	var departure := flying.get_global_transform_with_canvas() if is_instance_valid(flying) else home
	check(not departure.is_equal_approx(home), "Return begins at the reading cover rather than teleporting home")
	await create_timer(0.18).timeout
	check(modal.is_traveling() and is_instance_valid(flying)
		and not flying.get_global_transform_with_canvas().is_equal_approx(departure),
		"The closed cover visibly moves between reading and world positions")
	modal.close()
	check(not modal.open_peek() and modal.is_open(), "Repeated close and reopen requests cannot release the return lock early")
	await settle()
	check(cover.visible and cover.transform.is_equal_approx(authored)
		and cover.get_global_transform_with_canvas().is_equal_approx(home),
		"Arrival restores the authored cover visibility and exact world transform")
	check(not modal.is_open() and not modal.is_peeking() and not controller.is_world_input_blocked()
		and (not is_instance_valid(modal._travel_cover) or not modal._travel_cover.visible),
		"Arrival leaves one world cover and no flying copy or modal lock")
	check(stock.quantities == quantities and water.remaining_ml == supply and controller.current_mode == selected_mode,
		"Round-trip motion preserves stock, water and interaction mode")


func check_travel_lifecycle() -> void:
	var quantities := stock.quantities
	var supply := water.remaining_ml
	for action in ["hide_return", "ancestor_full_return", "ancestor_peek_return", "rebind_peek_return", "detach_controller", "detach_cover", "free_cover", "exit_departure", "resize_focus"]:
		var fixture := load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate() as Node2D
		root.add_child(fixture)
		await frames()
		var fixture_modal: KhataModal = fixture.khata_modal
		var fixture_controller := fixture.get_node("InteractionController") as InteractionController
		var cover := fixture_modal.cover as Sprite2D
		var cover_parent := cover.get_parent()
		var controller_parent := fixture_controller.get_parent()
		fixture_modal.book.sound_enabled = false
		check(fixture_modal.open_peek() if action in ["ancestor_peek_return", "rebind_peek_return"] else fixture_modal.open(),
			"%s fixture begins cover departure" % action)
		if action == "exit_departure":
			root.remove_child(fixture)
			await frames()
			root.add_child(fixture)
		else:
			await settle_fixture(fixture_modal)
			fixture_modal.close()
			await wait_for_return(fixture_modal)
			match action:
				"hide_return": fixture_modal.hide()
				"ancestor_full_return", "ancestor_peek_return": (fixture_modal.peek.get_parent() as Control).hide()
				"rebind_peek_return": fixture_modal.configure(null)
				"detach_controller": controller_parent.remove_child(fixture_controller)
				"detach_cover": cover_parent.remove_child(cover)
				"free_cover": cover.queue_free()
				"resize_focus":
					fixture_modal._on_resize()
					fixture_modal.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		await settle_fixture(fixture_modal)
		check(not fixture_modal.is_open() and not fixture_modal.is_peeking() and not fixture_modal.is_traveling()
			and not fixture_controller.is_world_input_blocked(), "%s finishes without an orphaned flight or lock" % action)
		check(not fixture_modal.book.opened and not fixture_modal.book.busy
			and not fixture_modal.visible
			and (not is_instance_valid(fixture_modal._travel_cover) or not fixture_modal._travel_cover.visible),
			"%s retires the book and temporary cover" % action)
		if is_instance_valid(cover):
			check(cover.visible, "%s releases the authored cover visibility lease" % action)
			if not cover.is_inside_tree(): cover_parent.add_child(cover)
		if not fixture_controller.is_inside_tree(): controller_parent.add_child(fixture_controller)
		if action == "rebind_peek_return":
			fixture_modal.configure(fixture_controller)
			check(fixture_modal.open_peek(), "Controller rebind after Peek return cancellation can open a fresh session")
			await settle_fixture(fixture_modal)
			check(fixture_modal.is_peeking() and not fixture_controller.is_world_input_blocked(),
				"Rebound Peek has neither a stale closing flag nor modal ownership")
			fixture_modal.close_peek()
			await settle_fixture(fixture_modal)
		fixture.queue_free()
		await frames()
	check(stock.quantities == quantities and water.remaining_ml == supply,
		"Interrupted cover journeys never reset shared supplies")


func check_peek_travel_coverage() -> void:
	check(modal.open_peek(), "Moving-input fixture opens Peek")
	await settle_peek()
	var peek := modal.peek as Control
	var old_paper := (peek.get_node("Page") as Control).get_global_rect()
	modal.close_peek()
	await create_timer(0.28).timeout
	check(modal.is_traveling() and not modal.is_open() and not controller.is_world_input_blocked(),
		"Peek return keeps bounded pointer coverage without acquiring full modal ownership")
	var book_transform := book.get_global_transform_with_canvas()
	var moving_bounds: Rect2 = book.get_visible_book_rect()
	var moving_point := book_transform * moving_bounds.get_center()
	check(controller.is_pointer_over_ui_at(moving_point), "The visible travelling notebook blocks input through its moving footprint")
	var old_point := Vector2.INF
	for ratio in [Vector2(0.1, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.9, 0.1)]:
		var candidate: Vector2 = old_paper.position + old_paper.size * ratio
		if not moving_bounds.has_point(book_transform.affine_inverse() * candidate):
			old_point = candidate
			break
	check(old_point.is_finite(), "Return movement exposes part of the old Peek position")
	if old_point.is_finite():
		check(not peek._has_point(peek.get_global_transform_with_canvas().affine_inverse() * old_point)
			and not controller.is_pointer_over_ui_at(old_point),
			"The old Peek rectangle stops blocking once the paper has moved away")
	await settle()
	check(not modal.is_peeking() and modal.cover.visible, "Peek return ends at the restored world cover")


func settle_fixture(fixture_modal: KhataModal) -> void:
	var fixture_book := fixture_modal.book
	var deadline := Time.get_ticks_msec() + 9000
	while (fixture_book.busy or fixture_modal.is_traveling()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not fixture_book.busy and not fixture_modal.is_traveling(), "Isolated notebook fixture settles")
	await frames()


func check_fold_destination_lifecycle() -> void:
	var quantities := stock.quantities
	var supply := water.remaining_ml
	for action in ["detach_during", "free_during", "queue_during", "detach_closed", "queue_closed"]:
		var fixture := load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate() as Node2D
		root.add_child(fixture)
		await frames()
		var fixture_modal: KhataModal = fixture.khata_modal
		var fixture_book: KhataBook = fixture_modal.book
		var fixture_controller := fixture.get_node("InteractionController") as InteractionController
		var destination := fixture_modal.peek
		var destination_parent := destination.get_parent()
		fixture_book.sound_enabled = false
		check(fixture_modal.open(), "%s fixture opens the full book" % action)
		await settle_fixture(fixture_modal)
		if action == "detach_closed":
			fixture_modal.closed.connect(func(): destination_parent.remove_child(destination), CONNECT_ONE_SHOT)
		elif action == "queue_closed":
			fixture_modal.closed.connect(destination.queue_free, CONNECT_ONE_SHOT)
		check(fixture_modal.open_peek(), "%s fixture starts folding toward Peek" % action)
		if action == "detach_during":
			destination_parent.remove_child(destination)
		elif action == "free_during":
			destination.free()
		elif action == "queue_during":
			destination.queue_free()
		await settle_fixture(fixture_modal)
		check(not fixture_modal.is_open() and not fixture_modal.is_peeking() and not fixture_modal.visible
			and not fixture_controller.is_world_input_blocked(), "%s leaves no modal lock or orphaned visible book" % action)
		check(not fixture_book.opened and not fixture_book.busy and not fixture_book.folding,
			"%s retires the renderer instead of reopening a removed destination" % action)
		check(fixture_modal.cover.visible, "%s restores the authored world cover after the failed handoff" % action)
		if is_instance_valid(destination) and not destination.is_inside_tree():
			destination_parent.add_child(destination)
		fixture.queue_free()
		await frames()
	check(stock.quantities == quantities and water.remaining_ml == supply,
		"Failed fold destinations never reset or replenish shared supplies")


func check_peek_other_input_owners() -> void:
	for kind in ["explicit owner", "ordinary ModalStack child"]:
		check(modal.open_peek(), "%s case starts nonmodal Peek" % kind)
		await settle_peek()
		var blocker: Node
		if kind == "explicit owner":
			blocker = Node.new()
			screen.add_child(blocker)
			controller.set_world_input_blocked(blocker, true)
		else:
			blocker = Control.new()
			controller.modal_root.add_child(blocker)
		check(controller.is_world_input_blocked(), "%s still blocks despite visible Peek's explicit exemption" % kind)
		await frames()
		await settle()
		check(not modal.is_peeking() and not book.opened and controller.is_world_input_blocked(),
			"%s retires Peek while retaining its own world-input ownership" % kind)
		if kind == "explicit owner":
			controller.set_world_input_blocked(blocker, false)
		blocker.queue_free()
		await frames()
		check(not controller.is_world_input_blocked(), "%s releases cleanly without a stale Peek blocker" % kind)


func check_live_world() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	kettle.discard_contents()
	kettle.add_water(600)
	kettle.temperature = 45
	stove.burners[0].set_heat(1)
	var cup := screen.get_cups()[0] as Cup
	cup.receive_liquid(&"black_tea", 120, 80)
	cup.add_relish(&"sugar")
	var progress := ProgressFixture.new()
	screen.add_child(progress)
	var rig: HangingSourceBody = screen.hanging_sources[0]
	rig.body.angular_velocity = 0.7
	rig.body.sleeping = false
	var ids := [screen.get_instance_id(), kettle.get_instance_id(), cup.get_instance_id()]
	var kettle_transform := kettle.global_transform
	var cup_transform := cup.global_transform
	var quantities := stock.quantities
	var supply_before := water.remaining_ml
	var day := water.day_id
	check(modal.open(), "Live simulation opens its notebook")
	await settle()
	var heat := kettle.temperature
	var cooling := cup.temperature
	var angle := rig.body.rotation
	var clock_before := progress.elapsed
	var patience_before := progress.patience
	rig.body.angular_velocity = 0.7
	rig.body.sleeping = false
	await create_timer(0.18).timeout
	check(kettle.temperature > heat and cup.temperature < cooling, "Applied heat and cup cooling continue under the modal")
	check(not is_equal_approx(rig.body.rotation, angle), "Existing pinned-body motion continues under the modal")
	check(not rig.can_brush(), "Modal blocks new hanging impulses while existing motion advances")
	check(progress.elapsed > clock_before and progress.patience < patience_before and not paused,
		"Clock/patience contract fixtures continue; the scene tree is not paused")
	kettle.temperature = kettle.config.boiling_temperature
	check(kettle.add_tea_leaves(), "Test establishes a brewing transition while the notebook is open")
	var steep := kettle.steep_progress
	await create_timer(0.12).timeout
	check(kettle.steep_progress > steep, "Steep progression continues independently while Khata owns input")
	await close_modal()
	check(ids == [screen.get_instance_id(), kettle.get_instance_id(), cup.get_instance_id()], "Opening and closing retain the exact live scene and vessels")
	check(kettle.global_transform.is_equal_approx(kettle_transform) and cup.global_transform.is_equal_approx(cup_transform), "Notebook ownership preserves committed placements")
	check(kettle.volume_ml == 600 and cup.volume_ml == 120 and cup.relish_item_ids == [&"sugar"], "Notebook does not reset liquid or ingredient contents")
	check(stock.quantities == quantities and water.remaining_ml == supply_before and water.day_id == day, "Notebook never replenishes stock/water or begins a new day")
	stove.burners[0].set_heat(0)
	progress.queue_free()


func check_gesture_cancellation() -> void:
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	var handle := sugar().placement_handle
	var owner_node := handle.item
	var parent := owner_node.get_parent()
	var original := owner_node.transform
	check(handle.begin_drag(point(owner_node)), "Organize test begins a whole-container drag")
	controller.update_drag(point(owner_node) + Vector2(-250, 50))
	check(modal.open(), "Opening cancels an Organize gesture")
	check(not controller.is_dragging() and owner_node.get_parent() == parent and owner_node.transform.is_equal_approx(original), "Container cancellation restores its owner and exact placement")
	await settle()
	await close_modal()
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Organize selection survives interruption")
	controller.set_mode(InteractionController.MODE_USE)
	var before := stock.remaining(&"sugar")
	check(sugar().begin_portion(point(sugar().source_owner)), "Use test reserves an ingredient portion")
	var held := controller.current_drag_node
	check(modal.open(), "Opening cancels a reserved physical-source portion")
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before, "Opening returns reserved stock without debiting or refunding prior use")
	await settle()
	check(not is_instance_valid(held) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Opening disposes the held visual and restores cursor ownership")
	await close_modal()
	kettle.advance_brewing(kettle.config.steep_seconds)
	var cup := screen.get_cups()[1] as Cup
	cup.reset_clean()
	var kettle_origin := kettle.global_transform
	check(kettle.begin_drag(point(kettle.get_node("GripAnchor"))), "Held-pour test picks up the kettle")
	var target := point(cup.get_node("PourTarget"))
	controller.update_drag(point(kettle.get_node("GripAnchor")) + target - kettle.get_pour_probe_viewport())
	kettle.update_held_pour(true)
	check(kettle.is_pouring, "Spout-targeted held pouring starts before modal interruption")
	kettle.update_pour(0.1)
	var kettle_volume := kettle.volume_ml
	var cup_volume := cup.volume_ml
	check(modal.open(), "Notebook interrupts held pouring")
	check(not kettle.is_pouring and not kettle.is_held and not controller.is_dragging() and not controller.has_active_action(), "Opening ends pour and drag ownership")
	await settle()
	check(kettle.volume_ml == kettle_volume and cup.volume_ml == cup_volume, "Already transferred liquid remains conserved and hidden pouring does not continue")
	check(kettle.global_transform.is_equal_approx(kettle_origin), "Kettle returns to its pre-drag placement")
	await close_modal()


func check_export_fixture() -> void:
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(modal.open(), "Neutral notebook opens for contract-only export")
	await settle()
	var owner_node := Node2D.new()
	screen.add_child(owner_node)
	var target := ExportTarget.new()
	target.controller = controller
	screen.get_node("WorldRoot/DropZoneRoot").add_child(target)
	target.position = Vector2(980, 660)
	controller.register_drop_zone(target)
	for action in ["success", "cancel", "close"]:
		var before := stock.remaining(&"sugar")
		var portion := IngredientPortion.new(&"sugar", &"spoonful", owner_node, stock)
		portion.token = stock.reserve(portion.item_id, portion.unit, 1, portion.source_id)
		var visual := IngredientPortionVisual.new(&"sugar", &"spoonful")
		var payload := portion.create_payload(visual)
		var allowed: Array[DropZone] = [target]
		check(modal.begin_export(payload, visual, point(target), allowed), "Modal begins a controlled %s export" % action)
		check(modal.exporting and controller.current_mode == InteractionController.MODE_NEUTRAL, "Export does not overwrite the prior selected mode")
		match action:
			"success": controller.release_drop(point(target))
			"cancel": modal.cancel_export()
			"close": modal.close()
		await frames()
		check(not modal.exporting and not controller.is_dragging(), "%s retires modal export ownership" % action)
		check(stock.remaining(&"sugar") == before - (1 if action == "success" else 0)
			and stock.available(&"sugar") == stock.remaining(&"sugar"), "%s resolves shared stock exactly once" % action)
		check(not target.try_apply_drop(payload), "Resolved export cannot be replayed")
		if action != "close": check(modal.is_open() and controller.is_world_input_blocked(), "Resolving export restores modal blocking")
	await settle()
	check(target.applied == 1 and not modal.is_open() and not controller.is_world_input_blocked(), "Only accepted contract export applies; close clears its lock")
	controller.unregister_drop_zone(target)
	target.queue_free()
	owner_node.queue_free()


func check_hidden_book() -> void:
	check(modal.open(), "Visibility test opens the notebook")
	await settle()
	modal.select_page(0)
	await settle()
	book.request_turn(1)
	check(book.busy, "Visibility test interrupts a live page animation")
	modal.hide()
	await frames()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "External hiding releases modal ownership")
	check(not book.busy and not book.opened and not book.dragging, "External hiding retires unfinished book motion")
	check(modal.open(), "Notebook can reopen after hidden animation cancellation")
	await settle()
	check(book.opened and controller.is_world_input_blocked(), "Reopened notebook restores visual and input ownership together")
	await close_modal()
	check(modal.open(), "Opening animation can be interrupted by external hiding")
	modal.hide()
	await frames()
	check(not modal.is_open() and not book.busy and not controller.is_world_input_blocked(), "Hiding during cover opening leaves no stale tween or lock")


func replacement_controller(mode: StringName) -> Dictionary:
	var host := Node2D.new()
	var drag_layer := Node2D.new()
	drag_layer.name = "DragLayer"
	host.add_child(drag_layer)
	var zones := Node2D.new()
	zones.name = "Zones"
	host.add_child(zones)
	var replacement := InteractionController.new()
	replacement.drag_layer_path = NodePath("../DragLayer")
	replacement.drop_zone_root_path = NodePath("../Zones")
	host.add_child(replacement)
	screen.add_child(host)
	replacement.modal_root = controller.modal_root
	replacement.set_mode(mode)
	return {"host": host, "controller": replacement, "zones": zones}


func export_record(interaction: InteractionController, host: Node, zones: Node) -> Dictionary:
	var owner_node := Node2D.new()
	host.add_child(owner_node)
	var target := ExportTarget.new()
	target.controller = interaction
	zones.add_child(target)
	target.position = Vector2(980, 660)
	interaction.register_drop_zone(target)
	var portion := IngredientPortion.new(&"sugar", &"spoonful", owner_node, stock)
	portion.token = stock.reserve(portion.item_id, portion.unit, 1, portion.source_id)
	var visual := IngredientPortionVisual.new(&"sugar", &"spoonful")
	return {"portion": portion, "visual": visual, "payload": portion.create_payload(visual), "target": target}


func begin_record(record: Dictionary) -> bool:
	var allowed: Array[DropZone] = [record.target]
	return modal.begin_export(record.payload, record.visual, point(record.target), allowed)


func check_export_to_peek() -> void:
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(modal.open(), "Export-to-Peek test starts a full notebook")
	await settle()
	var before := stock.remaining(&"sugar")
	var record := export_record(controller, screen, screen.get_node("WorldRoot/DropZoneRoot"))
	check(begin_record(record), "Full notebook holds a reserved export before folding")
	check(stock.available(&"sugar") == before - 1, "Controlled export owns one reservation before transition")
	check(modal.open_peek(), "Full notebook accepts a fold request while an export is held")
	check(not modal.exporting and not controller.is_dragging() and not controller.is_modal_export_active()
		and stock.remaining(&"sugar") == before and stock.available(&"sugar") == before,
		"Folding cancels the export and releases stock immediately before the animation")
	check(not record.portion.is_available() and not record.target.try_apply_drop(record.payload),
		"Canceled transition export cannot be replayed at its formerly allowed target")
	await settle_peek()
	check(modal.is_peeking() and not modal.is_open() and not controller.is_world_input_blocked()
		and not is_instance_valid(record.visual), "Fold completes in Peek without its old export visual or input exception")
	modal.close_peek()
	await settle()
	controller.unregister_drop_zone(record.target)
	(record.portion.source_ref.get_ref() as Node).queue_free()
	(record.target as Node).queue_free()
	await frames()


func check_controller_lifecycle() -> void:
	controller.set_mode(InteractionController.MODE_USE)
	check(modal.open(), "Controller replacement begins with an active notebook")
	await settle()
	var before := stock.remaining(&"sugar")
	var record := export_record(controller, screen, screen.get_node("WorldRoot/DropZoneRoot"))
	check(begin_record(record), "Old controller owns a reserved export before replacement")
	var fixture := replacement_controller(InteractionController.MODE_ORGANIZE)
	var replacement := fixture.controller as InteractionController
	modal.configure(replacement)
	await frames()
	check(not controller.is_dragging() and not controller.is_modal_export_active()
		and not controller.is_world_input_blocked(), "Rebinding releases the old controller's gesture and modal lock")
	check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before
		and not record.portion.is_available() and not is_instance_valid(record.visual), "Rebinding retires the old reservation and transient visual without consumption")
	check(not modal.is_open() and not modal.visible and not modal.exporting and not book.busy and not book.opened,
		"Rebinding closes and resets the previous notebook session")
	check(replacement.current_mode == InteractionController.MODE_ORGANIZE
		and controller.current_mode == InteractionController.MODE_USE, "Rebinding preserves each controller's distinct mode")
	check(modal.open(), "New controller opens a fresh notebook session")
	await settle()
	check(replacement.is_world_input_blocked() and replacement.current_mode == InteractionController.MODE_ORGANIZE,
		"Fresh session belongs to the new controller without forcing its mode")
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	check(modal.is_open(), "Disconnected old-controller signals cannot close the replacement session")
	modal.close()
	await settle()
	check(not replacement.is_world_input_blocked() and replacement.current_mode == InteractionController.MODE_ORGANIZE,
		"Closing the replacement session releases its own lock and preserves its mode")
	modal.configure(controller)
	controller.unregister_drop_zone(record.target)
	(record.portion.source_ref.get_ref() as Node).queue_free()
	(record.target as Node).queue_free()
	(fixture.host as Node).queue_free()
	await frames()
	for action in ["detach_active", "detach_export", "free_active", "free_export"]:
		fixture = replacement_controller(InteractionController.MODE_ORGANIZE)
		replacement = fixture.controller
		modal.configure(replacement)
		check(modal.open(), "%s begins a fresh active session" % action)
		await settle()
		before = stock.remaining(&"sugar")
		record = {}
		if action.ends_with("export"):
			record = export_record(replacement, fixture.host, fixture.zones)
			check(begin_record(record), "%s begins a reserved export" % action)
		if action.begins_with("detach"):
			(fixture.host as Node).remove_child(replacement)
		else:
			replacement.queue_free()
		# An input event can arrive before the modal's next process callback.
		var key := InputEventKey.new()
		key.keycode = KEY_K
		key.pressed = true
		modal._input(key)
		check(not modal.open(), "%s cannot reopen through stale controller input" % action)
		await frames()
		check(not modal.is_open() and not modal.visible and not modal.exporting
			and not book.busy and not book.opened, "%s leaves no stale book or export state" % action)
		check(stock.remaining(&"sugar") == before and stock.available(&"sugar") == before
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s preserves stock and releases pointer ownership" % action)
		if not record.is_empty():
			check(not record.portion.is_available() and not is_instance_valid(record.visual), "%s retires its payload and held visual" % action)
		check(not controller.is_world_input_blocked(), "%s leaves no orphaned visible modal blocking the live world" % action)
		if action.begins_with("detach"):
			check(not replacement.is_dragging() and not replacement.is_modal_export_active(), "Detached controller retains no gesture or export session")
			(fixture.host as Node).add_child(replacement)
			await frames()
			check(modal.open(), "Reentered controller can acquire a new modal session")
			await settle()
			modal.close()
			await settle()
		modal.configure(controller)
		(fixture.host as Node).queue_free()
		await frames()
	check(modal.controller == controller and not modal.is_open(), "Controller lifecycle fixtures restore the original normal-scene binding")


func run() -> void:
	root.size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var state := root.get_node("GameState")
	check(state.reset_demo_state(), "Test initializes authoritative supplies")
	stock = state.inventory
	water = state.water_supply
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await frames()
	controller = screen.get_node("InteractionController")
	modal = screen.khata_modal
	book = modal.book
	book.sound_enabled = false
	kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	stove = screen.get_node("WorldRoot/ToolLayer/StoveStation")
	# Source injection is a fixture here; it does not implement the later pantry UI.
	screen.set_portion_provider(stock)
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Normal Tong scene begins without a modal lock")
	check(modal.get_parent() == controller.modal_root, "Production notebook belongs to the existing ModalStack")
	await check_cover_journey()
	await check_travel_lifecycle()
	await check_peek_travel_coverage()
	await check_peek_world_and_handoff()
	await check_peek_lifecycle()
	await check_peek_reentrant_handoff()
	await check_shared_folded_pages()
	await check_fold_destination_lifecycle()
	await check_peek_other_input_owners()
	await check_modes_and_pages()
	await check_live_world()
	await check_gesture_cancellation()
	await check_export_fixture()
	await check_export_to_peek()
	await check_hidden_book()
	await check_controller_lifecycle()
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(modal.open(), "Teardown fixture opens the modal")
	await settle()
	root.remove_child(screen)
	await frames()
	root.add_child(screen)
	await frames()
	check(not modal.is_open() and not controller.is_world_input_blocked(), "Scene exit/reentry leaves no stale modal lock")
	check(modal.open(), "The reentered scene can open its notebook again")
	await settle()
	screen.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and stock.available(&"sugar") == stock.remaining(&"sugar"), "Final teardown clears cursor and reservations")
	print("KHATA_MODAL: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
