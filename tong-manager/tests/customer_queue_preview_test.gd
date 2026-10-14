extends SceneTree
## Integration review of live queue timing and the real notebook/input boundary.

const PREVIEW := preload("res://scenes/development/CustomerQueuePreview.tscn")
const TONG := preload("res://scenes/gameplay/tong/TongDayScreen.tscn")
const LEGACY_PREVIEW := preload("res://scenes/development/CustomerScenePreview.tscn")
const DAY_ONE := "res://data/examples/customer_days/authored_day_1.tres"
const DAY_TWO := "res://data/examples/customer_days/authored_day_2.tres"

var checks := 0
var failures: Array[String] = []
var rendered := false
var capture_dir := ""
var view: Node
var screen: Node2D
var controller: InteractionController
var queue: CustomerQueueManager
var game_state: Node
var stock: InventoryState
var water: DailyWaterSupply
var stock_before: Dictionary
var water_before := 0.0


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


func click(button: BaseButton) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "Review control is reachable: " + button.name)
	if not rendered:
		if button.toggle_mode: button.button_pressed = not button.button_pressed
		button.pressed.emit()
		await frames()
		return
	var point := button.get_global_rect().get_center()
	root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await frames()
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


func choose_day(index: int) -> void:
	if rendered:
		await click(view.day_picker as OptionButton)
		var popup := (view.day_picker as OptionButton).get_popup()
		check(popup.visible, "Native day picker opens its popup window")
		popup.set_focused_item(index)
		await tap(KEY_ENTER)
		check(not popup.visible, "Keyboard selection closes the day picker popup")
		if popup.visible: popup.hide()
	else:
		view.select_day(index)
	await frames()
	queue.set_process(false)
	check(view.selected_day == index, "Day selection uses the review control's schedule binding")


func capture(label: String) -> void:
	if not rendered or capture_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK,
		"Saved queue review: " + label)


func check_supplies(label: String) -> void:
	check(game_state.inventory == stock and game_state.water_supply == water,
		label + ": queue retains the shared supply authorities")
	check(stock.quantities == stock_before and is_equal_approx(water.remaining_ml, water_before),
		label + ": queue neither consumes nor replenishes stock/water")


func cup_snapshot(owner: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cup: Cup in owner.get_cups():
		result.append({"id": cup.get_instance_id(), "state": cup.state, "volume": cup.volume_ml,
			"order": cup.assigned_order_id, "ingredients": cup.get_ingredient_amounts()})
	return result


func entry_for(id: StringName) -> Dictionary:
	for entry: Dictionary in queue.get_active_entries():
		if entry.entry_id == id: return entry
	return {}


func advance_to_due(due: float) -> void:
	var snapshot := queue.get_snapshot()
	queue.advance(maxf(0.0, due - float(snapshot.elapsed)) + 0.01)
	await frames()


func check_scene_boundaries() -> void:
	var ordinary := TONG.instantiate() as Node2D
	root.add_child(ordinary)
	await frames(4)
	var manager: CustomerQueueManager = ordinary.customer_queue
	manager.set_process(false)
	var summary := manager.get_snapshot()
	check(summary.running and int(summary.total) >= 4 and int(summary.total) <= 5
		and int(summary.max_active) == 2, "Normal Tong starts the data-driven default queue")
	check(ordinary.get_node_or_null("WorldRoot/CustomerLayer/CustomerA") == null
		and ordinary.get_node_or_null("WorldRoot/CustomerLayer/CustomerB") == null,
		"Normal queue replaces the fixed visual-review actors")
	var config: Resource = ordinary.day_config
	manager.advance(float(config.customer_schedule.first_delay_seconds) + 0.02)
	await frames()
	check(manager.get_active_customers().size() == 1, "Normal scene's first due visit reaches the counter")
	var active := manager.get_active_customers()
	if not active.is_empty():
		var order := manager.get_order_for_customer(active[0])
		check(order != null and order.request_kind in [&"tea", &"ready_item"],
			"Normal queue binds the typed request authority without evaluating a handoff")
	var held_refs: Array[WeakRef] = []
	for actor in active: held_refs.append(weakref(actor))
	ordinary.queue_free()
	await frames(4)
	for actor_ref in held_refs:
		check(actor_ref.get_ref() == null, "Normal scene teardown disposes its arriving customer")
	var legacy := LEGACY_PREVIEW.instantiate()
	root.add_child(legacy)
	await frames(4)
	var legacy_screen: Node2D = legacy.screen
	var legacy_queue: CustomerQueueManager = legacy_screen.customer_queue
	check(not legacy_screen.customer_queue_enabled and not bool(legacy_queue.get_snapshot().running),
		"Accepted customer-presentation preview explicitly opts out of the production queue")
	check(legacy.customers.size() == 2
		and legacy_screen.get_node_or_null("WorldRoot/CustomerLayer/CustomerA") != null
		and legacy_screen.get_node_or_null("WorldRoot/CustomerLayer/CustomerB") != null,
		"Opt-out retains the existing two fixture actors and their known paths")
	legacy_queue.advance(100.0)
	check(legacy_queue.get_active_customers().is_empty(), "Opted-out preview cannot spawn an accidental second queue")
	legacy.queue_free()
	await frames(4)
	check_supplies("Normal/legacy scene lifecycle")


func check_preview_controls() -> void:
	var bounds := root.get_visible_rect()
	var controls: Array[Control] = [view.day_picker, view.restart_button, view.dialogue_toggle,
		view.motion_toggle, view.status_label, view.event_label]
	for button: Button in view.departure_buttons: controls.append(button)
	for control in controls:
		check(control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()),
			"Queue review control fits this viewport: " + control.name)
	var run_before: StringName = queue.get_snapshot().run_id
	await click(view.restart_button as Button)
	queue.set_process(false)
	check(queue.get_snapshot().run_id != run_before and int(queue.get_snapshot().total) == 4,
		"Restart starts a fresh four-entry authored run")
	await choose_day(1)
	check(int(queue.get_snapshot().total) == 5, "Second authored day supplies its own five-entry count")
	await choose_day(2)
	check(int(queue.get_snapshot().total) >= 4 and int(queue.get_snapshot().total) <= 5,
		"Generated preview still uses the configured daily count range")
	await choose_day(0)
	await click(view.dialogue_toggle as CheckButton)
	check(bool(view.dialogue_toggle.button_pressed), "Optional dialogue control toggles on")
	await capture("schedule-ready")


func check_arrivals_and_departure() -> void:
	var day := load(DAY_ONE) as Resource
	var schedule: CustomerSchedule = day.customer_schedule
	await advance_to_due(schedule.arrivals[0].due_seconds)
	var actors := queue.get_active_customers()
	check(actors.size() == 1, "Staggered first due time adds only one customer")
	if actors.is_empty(): return
	var first := actors[0]
	var first_entry: Dictionary = queue.get_active_entries()[0]
	var first_id: StringName = first_entry.entry_id
	check(first_entry.phase == &"arriving" and is_equal_approx(first_entry.patience_remaining, first_entry.patience_seconds),
		"Visible arrival has not spent any waiting patience")
	check(first.dialogue_enabled, "New arrivals inherit the preview dialogue setting")
	await capture("first-arriving")
	await wait_until(func(): return not entry_for(first_id).is_empty() and entry_for(first_id).phase == &"waiting",
		"Actual customer arrival finishes before the queue enters waiting")
	first_entry = entry_for(first_id)
	if first_entry.is_empty(): return
	check(is_equal_approx(first_entry.patience_remaining, first_entry.patience_seconds),
		"Actor animation completion alone does not spend a frozen queue's patience")
	await advance_to_due(schedule.arrivals[1].due_seconds)
	check(queue.get_active_customers().size() == 2, "Second staggered due time fills the second place")
	await wait_until(func():
		for entry: Dictionary in queue.get_active_entries():
			if entry.phase == &"arriving": return false
		return true, "Both customers finish their own arrival")
	var markers := screen.get_node("WorldRoot/CustomerLayer/CustomerQueueSlots").get_children()
	for entry: Dictionary in queue.get_active_entries():
		var slot := int(entry.slot_index)
		var found := false
		for actor in queue.get_active_customers():
			var order := queue.get_order_for_customer(actor)
			if order != null and order.order_id == entry.order_id:
				found = actor.global_position.distance_to((markers[slot] as Marker2D).global_position) < 0.1
		check(found, "Live visit is anchored to its assigned scaled counter marker")
	await capture("two-waiting")
	var first_order := queue.get_order_for_customer(first)
	var before_count := int(queue.get_snapshot().spawned)
	await click(view.departure_buttons[int(first_entry.slot_index)] as Button)
	check(first.state == Customer.State.LEAVING and queue.get_active_customers().has(first),
		"Review departure keeps the slot occupied throughout the turn/walk")
	check(first_order != null and not first_order.fulfilled and first_order.get_results().is_empty(),
		"Review departure does not create a synthetic service or payment result")
	check(int(queue.get_snapshot().spawned) == before_count, "Leaving cannot instantly replace the occupied actor")
	await wait_until(func(): return entry_for(first_id).is_empty(), "Completed departure releases its slot")
	check_supplies("Preview controls and manual departure")


func make_modal_day() -> Resource:
	var day := (load(DAY_ONE) as Resource).duplicate(false)
	var original: CustomerSchedule = day.customer_schedule
	var schedule := original.duplicate(false) as CustomerSchedule
	var arrivals: Array[CustomerArrivalDef] = []
	for index in 2:
		var arrival := original.arrivals[index].duplicate(false) as CustomerArrivalDef
		arrival.due_seconds = 0.0 if index == 0 else 0.6
		arrival.patience_override = 12.0
		arrivals.append(arrival)
	schedule.arrivals = arrivals
	day.customer_schedule = schedule
	return day


func check_khata_continuity() -> void:
	var day := make_modal_day()
	check(screen.start_customer_queue(day, 64), "Isolated short schedule starts through normal Tong integration")
	queue.set_process(false)
	queue.advance(0.01)
	await frames()
	if queue.get_active_customers().is_empty():
		check(false, "Modal continuity fixture has an active customer")
		return
	var first := queue.get_active_customers()[0]
	var order := queue.get_order_for_customer(first)
	var first_id: StringName = queue.get_active_entries()[0].entry_id
	await wait_until(func(): return entry_for(first_id).get("phase") == &"waiting", "Modal fixture finishes arrival")
	var modal: KhataModal = screen.khata_modal
	var before := queue.get_snapshot()
	queue.set_process(true)
	(view.day_picker as OptionButton).release_focus()
	await tap(KEY_K)
	check(modal.is_peeking() and not controller.is_world_input_blocked(), "K opens the live nonmodal pantry Peek")
	if not modal.is_peeking():
		queue.set_process(false)
		return
	await wait_until(func(): return not modal.book.busy and not modal.is_traveling(), "Peek presentation settles")
	await create_timer(0.25).timeout
	var after := queue.get_snapshot()
	check(float(after.elapsed) > float(before.elapsed) + 0.2 and int(after.spawned) == 2,
		"Queue clock and next due arrival continue while Peek is open")
	check(not entry_for(first_id).is_empty() and float(entry_for(first_id).patience_remaining) < 11.8,
		"Peek does not pause the waiting customer's patience")
	await capture("peek-live-queue")
	var open_button := screen.get_node("HUDLayer/RootUI/KhataPeek/OpenButton") as Button
	await click(open_button)
	check(modal.is_open() and controller.is_world_input_blocked(), "Full notebook acquires input ownership")
	if not modal.is_open():
		queue.set_process(false)
		return
	await wait_until(func(): return not modal.book.busy and not modal.is_traveling(), "Full notebook presentation settles")
	queue.set_process(false)
	var current := entry_for(first_id)
	check(not current.is_empty() and float(current.patience_remaining) < 11.5,
		"Patience continued during the full-notebook transition")
	var run_id: StringName = queue.get_snapshot().run_id
	view.restart_schedule()
	view.select_day(1)
	view.preview_departure(int(current.get("slot_index", 0)))
	check(queue.get_snapshot().run_id == run_id and first.state != Customer.State.LEAVING,
		"Full notebook blocks review commands without restarting or retiring the queue")
	if not current.is_empty(): queue.advance(maxf(0.0, float(current.patience_remaining) - 0.15))
	queue.set_process(true)
	var expired := await wait_until(func(): return entry_for(first_id).get("phase") == &"timeout_reaction", "Patience expires while Full is still open")
	queue.set_process(false)
	if not expired or not is_instance_valid(first):
		modal.close()
		return
	check(modal.is_open() and controller.is_world_input_blocked() and not paused,
		"Timeout leaves Full open and never pauses the SceneTree")
	check(not first.is_serve_enabled() and first.get_presentation_snapshot().emotion == &"unhappy",
		"Expired customer becomes disappointed and immediately stops accepting service")
	check(order != null and not order.fulfilled and order.get_results().is_empty()
		and int(first.get_presentation_snapshot().review_count) == 0,
		"Patience expiry records no fulfillment, accepted result or bad review")
	await capture("full-open-timeout")
	await tap(KEY_ESCAPE)
	await wait_until(func(): return not modal.is_open() and not modal.is_traveling() and not controller.is_world_input_blocked(),
		"Escape closes Full without disturbing the timed-out visit")
	await capture("disappointed-before-leaving")
	queue.advance(float((day.customer_schedule as CustomerSchedule).timeout_reaction_seconds) + 0.01)
	check(first.state == Customer.State.LEAVING, "Timeout reaction hands off to the accepted departure motion")
	await wait_until(func(): return entry_for(first_id).is_empty(), "Timed-out actor finishes departure and releases its place")
	check(order.get_results().is_empty() and not order.fulfilled, "Departure cannot convert timeout into service")
	check_supplies("Khata continuity and timeout")


func check_restart_and_teardown() -> void:
	await click(view.motion_toggle as CheckButton)
	await click(view.restart_button as Button)
	queue.set_process(false)
	check(queue.reduced_motion and view.motion_toggle.button_pressed, "Restart applies the explicit reduced-motion review setting")
	var day := load(DAY_ONE) as Resource
	await advance_to_due(float(day.customer_schedule.arrivals[0].due_seconds))
	check(queue.get_active_entries().size() == 1 and queue.get_active_entries()[0].phase == &"waiting",
		"Reduced-motion arrival still arms one waiting visit")
	controller.set_mode(InteractionController.MODE_INTERACT)
	var cup: Cup = screen.get_cups()[0]
	var prior_transform := cup.global_transform
	var cup_point := cup.get_global_transform_with_canvas().origin
	if rendered: root.warp_mouse(cup_point)
	var motion := InputEventMouseMotion.new()
	motion.position = cup_point
	root.push_input(motion, true)
	await frames()
	await wait_until(func(): return not controller.is_pointer_over_ui(),
		"Pointer leaves the review UI before starting the cup gesture", 1.0)
	var started := cup.begin_interaction_drag(cup_point)
	if not started:
		var handle := cup.get_node("PlacementHandle") as TablePlaceable
		print("QUEUE_GESTURE_DIAGNOSTIC ", {"point": cup_point, "mouse": root.get_mouse_position(),
			"hover": root.gui_get_hovered_control(), "mode": controller.current_mode,
			"blocked": controller.is_world_input_blocked(), "drag": controller.is_dragging(),
			"action": controller.has_active_action(), "bound": cup.controller == controller,
			"surface": handle.surface, "registered": handle.surface.is_registered(cup)})
	check(started, "Existing cup gesture can coexist with the queue")
	var run_id: StringName = queue.get_snapshot().run_id
	view.restart_schedule()
	view.select_day(1)
	check(queue.get_snapshot().run_id == run_id and view.selected_day == 0,
		"Review controls cannot restart a day during an owned world gesture")
	controller.cancel_drag()
	check(cup.global_transform.is_equal_approx(prior_transform), "Canceled cup gesture retains its exact original placement")
	var retired: Array[WeakRef] = []
	for actor in queue.get_active_customers(): retired.append(weakref(actor))
	await click(view.restart_button as Button)
	queue.set_process(false)
	check(queue.get_snapshot().run_id != run_id, "Allowed restart gives the replacement schedule a fresh run identity")
	await frames(4)
	for actor_ref in retired: check(actor_ref.get_ref() == null, "Restart removes the old run's actors")
	await advance_to_due(float(day.customer_schedule.arrivals[0].due_seconds))
	var live_refs: Array[WeakRef] = []
	for actor in queue.get_active_customers(): live_refs.append(weakref(actor))
	var slots := screen.get_node("WorldRoot/CustomerLayer/CustomerQueueSlots") as Node2D
	var grouping := Node2D.new()
	grouping.name = "NonMarkerAuthoringGroup"
	slots.add_child(grouping)
	slots.move_child(grouping, 0)
	await frames()
	check(view._actor_in_slot(0) == queue.get_active_customers()[0],
		"A non-marker authoring child does not remap the preview's left slot")
	check(not (view.departure_buttons[0] as Button).disabled,
		"Preview controls still address the real first marker after grouping changes")
	slots.get_parent().remove_child(slots)
	view.preview_departure(0)
	await frames()
	check(view._actor_in_slot(0) == null and view._actor_in_slot(1) == null,
		"A removed slot container makes preview lookup unavailable safely")
	check((view.departure_buttons[0] as Button).disabled and (view.departure_buttons[1] as Button).disabled,
		"Missing slot container disables both departure controls")
	queue.advance(0.0)
	await frames()
	check(not bool(queue.get_snapshot().running) and queue.get_active_customers().is_empty(),
		"Removing all slots retires the run without leaving an active customer")
	slots.free()
	var manager_ref: WeakRef = weakref(queue)
	view.queue_free()
	await frames(4)
	check(manager_ref.get_ref() == null, "Preview teardown releases its manager")
	for actor_ref in live_refs: check(actor_ref.get_ref() == null, "Preview teardown leaves no customer orphan")
	check_supplies("Restart and teardown")


func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	game_state = root.get_node("GameState")
	check(game_state.ensure_inventory(), "Shared inventory is initialized before queue review")
	game_state.ensure_water_day()
	stock = game_state.inventory
	water = game_state.water_supply
	stock_before = stock.quantities
	water_before = water.remaining_ml
	await check_scene_boundaries()
	view = PREVIEW.instantiate()
	root.add_child(view)
	await frames(5)
	screen = view.screen
	controller = view.controller
	queue = view.queue
	queue.set_process(false)
	var cups_before := cup_snapshot(screen)
	await check_preview_controls()
	await check_arrivals_and_departure()
	await check_khata_continuity()
	check(cup_snapshot(screen) == cups_before, "All review controls and timeouts preserve live cup contents/state/history")
	await check_restart_and_teardown()
	print("CUSTOMER_QUEUE_PREVIEW: %d checks; %d failures; rendered=%s" % [checks, failures.size(), rendered])
	quit(0 if failures.is_empty() else 1)
