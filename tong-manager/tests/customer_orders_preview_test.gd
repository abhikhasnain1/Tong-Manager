extends SceneTree
## Rendered preview verification. Public selection methods set the data fixture;
## actual mouse events exercise the scenario buttons and their signal wiring.

const PREVIEW := preload("res://scenes/development/CustomerOrdersPreview.tscn")
var view: Control
var catalog: Node
var state: Node
var checks := 0
var failures: Array[String] = []
var capture_dir := ""


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


func click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "Scenario button is reachable: " + button.text)
	var point: Vector2 = button.get_global_rect().get_center()
	root.warp_mouse(point)
	await frames()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await frames()


func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered data preview contains pixels: " + name)
	if image != null and not image.is_empty():
		check(image.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved data preview: " + name)


func check_visible_controls(label: String) -> void:
	var controls: Array[Control] = [view.customer_picker, view.request_picker, view.portrait,
		view.accept_button, view.cold_button, view.reject_button, view.replay_button,
		view.new_order_button, view.validate_button, view.details_label, view.status_label, view.validation_label]
	for control: Control in controls:
		if not control.is_visible_in_tree(): continue
		check(root.get_visible_rect().encloses(control.get_global_rect()), label + ": control remains in viewport: " + control.name)
	check(view.details_label.text.length() > 0 and view.status_label.text.length() > 0, label + ": selected data and outcome are readable")


func request_index(profile: CustomerDef, kind: StringName) -> int:
	for index in profile.order_requests.size():
		if StringName(profile.order_requests[index].kind) == kind: return index
	return -1


func check_invalid_startup(profiles: Array[CustomerDef]) -> void:
	# Change only in-memory scalar values, preserving the canonical pool resources.
	var patience: Array[float] = [profiles[0].patience_seconds, profiles[1].patience_seconds]
	profiles[0].patience_seconds = 0.0
	view = PREVIEW.instantiate() as Control
	root.add_child(view)
	await frames(4)
	check(view.customer_picker.item_count == 1 and view.order != null and view.order.customer_id == profiles[1].id,
		"A partially invalid Catalog still displays the remaining valid profile")
	check(view.validation_label.text.contains(String(profiles[0].id)) and view.validation_label.text.to_lower().contains("patience"),
		"Partial-invalid startup exposes the excluded profile's concrete diagnostic")
	check_visible_controls("Partial-invalid Catalog")
	await capture("partial-invalid-profile")
	view.queue_free()
	await frames()
	profiles[1].patience_seconds = 0.0
	view = PREVIEW.instantiate() as Control
	root.add_child(view)
	await frames(4)
	check(view.order == null and view.customer_picker.item_count == 0,
		"An all-invalid Catalog creates no fake order or empty request")
	check(view.status_label.text.contains("No valid") and not view.validation_label.text.is_empty(),
		"All-invalid startup gives a useful nonblank error state")
	check(view.customer_picker.disabled and view.request_picker.disabled and view.new_order_button.disabled
		and view.accept_button.disabled and view.cold_button.disabled and view.reject_button.disabled,
		"All-invalid startup disables actions that need a real order")
	check(root.get_visible_rect().encloses(view.status_label.get_global_rect()),
		"The all-invalid status remains visible inside the viewport")
	await capture("all-invalid-profiles")
	view.queue_free()
	await frames()
	for index in profiles.size():
		profiles[index].patience_seconds = patience[index]
	check(catalog.validate_customer_orders().is_empty() and catalog.get_available_customers().size() == 2,
		"Invalid-startup fixtures restore both original profiles")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("customer_orders_preview_test.gd requires a rendered window; customer_order_data_test.gd is the headless suite.")
		quit(2)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	catalog = root.get_node("Catalog")
	state = root.get_node("GameState")
	check(state.ensure_inventory(), "Preview isolation fixture initializes stock")
	state.ensure_water_day()
	var stock: Dictionary = state.inventory.quantities
	var water: float = state.water_supply.remaining_ml
	var inventory_identity: InventoryState = state.inventory
	var water_identity: DailyWaterSupply = state.water_supply
	view = PREVIEW.instantiate() as Control
	root.add_child(view)
	await frames(4)
	check(view.order != null and not view.order.fulfilled and view.order.get_results().is_empty(), "Preview starts with an isolated pending order")
	check(view.customer_picker.item_count == 2 and view.request_picker.item_count == 6, "Preview exposes both profiles and all six request definitions")
	check_visible_controls("Initial preview")
	await capture("initial-data-preview")
	var profiles: Array[CustomerDef] = catalog.get_available_customers()
	for customer_index in profiles.size():
		view.select_customer(customer_index)
		await frames()
		var profile: CustomerDef = profiles[customer_index]
		check(view.portrait.texture == profile.sprite_texture and view.order.customer_id == profile.id, "Customer selection binds the actual resource identity and artwork")
		for index in profile.order_requests.size():
			view.select_request(index)
			await frames()
			var option: OrderRequestDef = profile.order_requests[index]
			var data: Dictionary = view.order.get_request()
			check(view.order.request_id == option.id and data == option.snapshot(catalog), "Request selection displays the selected Catalog snapshot")
			check(view.request_icon.texture == data.icon, "Request artwork is shared with its catalog definition")
			check(view.cold_button.visible == (option.kind == "tea"), "Only tea offers a cold-service data example")
			check_visible_controls("Selected " + String(option.id))
	view.select_customer(0)
	view.select_request(request_index(profiles[0], &"tea"))
	await frames()
	var initial_order_id: StringName = view.order.order_id
	await click(view.cold_button)
	var accepted: Dictionary = view.order.get_accepted_result()
	check(view.order.fulfilled and accepted.accepted and accepted.cold_at_handoff and accepted.unhappy and accepted.bad_review,
		"Actual cold-example click records fulfilled tea with the approved dissatisfied outcome")
	check(view.status_label.text.contains("SERVED") and view.status_label.text.contains("unhappy"), "The preview displays fulfillment separately from satisfaction")
	check(view.history_label.text.contains(String(accepted.handoff_id)), "Visible history identifies the recorded handoff")
	await capture("accepted-cold-tea")
	await click(view.replay_button)
	check(view.order.get_results().size() == 1 and view.order.get_accepted_result() == accepted, "Actual replay click cannot add or rewrite fulfillment")
	await click(view.accept_button)
	check(view.order.get_results().size() == 1 and view.order.get_accepted_result() == accepted,
		"A fresh attempted acceptance also cannot duplicate a fulfilled order")
	await click(view.new_order_button)
	check(view.order.order_id != initial_order_id and not view.order.fulfilled and view.order.get_results().is_empty(), "New order creates a fresh fixture identity and empty history")
	await click(view.reject_button)
	check(not view.order.fulfilled and view.order.get_results().size() == 1, "Actual rejection click leaves the order pending")
	var rejected_identity: StringName = view.last_result.get_snapshot().handoff_id
	await click(view.replay_button)
	check(view.order.get_results().size() == 1 and not view.order.fulfilled, "Rejected replay also stays idempotent")
	await click(view.accept_button)
	check(view.order.fulfilled and view.order.get_results().size() == 2 and not view.order.get_accepted_result().bad_review,
		"A fresh correct warm attempt fulfills once after rejection")
	check(view.order.get_accepted_result().handoff_id != rejected_identity, "Corrected attempts receive a fresh handoff identity")
	await capture("rejected-then-warm")
	view.select_customer(1)
	view.select_request(request_index(profiles[1], &"ready_item"))
	await frames()
	check(view.order.request_kind == &"ready_item" and not view.cold_button.visible, "Ready-item selection has piece-specific presentation")
	await click(view.accept_button)
	check(view.order.fulfilled and view.order.get_accepted_result().reason == &"ready_item_served"
		and not view.order.get_accepted_result().bad_review, "Actual ready-item click records its nonthermal outcome")
	await capture("accepted-ready-piece")
	var before_invalid: Dictionary = view.order.get_snapshot()
	var selected_resource: OrderRequestDef = catalog.get_order_request(view.order.request_id)
	var before_definition: Dictionary = selected_resource.snapshot(catalog)
	await click(view.validate_button)
	check(view.validation_label.text.contains("missing_preview_reference"), "Actual validation click exposes a concrete missing-reference diagnostic")
	check(view.order.get_snapshot() == before_invalid and selected_resource.snapshot(catalog) == before_definition
		and catalog.validate_customer_orders().is_empty(), "Invalid-reference example mutates neither live definitions nor the current order")
	check_visible_controls("Invalid ready-item example")
	await capture("invalid-reference-copy")
	check(state.inventory == inventory_identity and state.water_supply == water_identity
		and state.inventory.quantities == stock and state.water_supply.remaining_ml == water,
		"All preview examples preserve shared provider identity, stock and daily water")
	view.queue_free()
	await frames()
	view = PREVIEW.instantiate() as Control
	root.add_child(view)
	await frames(4)
	check(not view.order.fulfilled and view.order.get_results().is_empty(), "Preview recreation has fresh local data rather than a production outcome ledger")
	check(state.inventory.quantities == stock and state.water_supply.remaining_ml == water, "Preview recreation never replenishes or consumes supplies")
	view.queue_free()
	await frames()
	await check_invalid_startup(profiles)
	check(state.inventory.quantities == stock and state.water_supply.remaining_ml == water,
		"Invalid-profile preview startup also leaves supplies unchanged")
	print("CUSTOMER_ORDERS_PREVIEW: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
