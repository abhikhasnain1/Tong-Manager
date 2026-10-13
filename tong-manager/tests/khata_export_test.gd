extends SceneTree

class ContractTarget extends DropZone:
	var controller: InteractionController
	var applied := 0
	var callback: Callable
	func _init() -> void:
		var marker := Sprite2D.new()
		marker.name = "DebugPreview"
		marker.visible = false
		add_child(marker)
		snap_radius = 30.0
	func accepts(payload: HeldItemPayload) -> DropValidation:
		if not controller.can_address_drop_zone(payload, self):
			return DropValidation.invalid("Unauthorized export")
		var portion := payload.metadata.get("portion") as IngredientPortion
		return DropValidation.valid() if portion != null and portion.is_available() else DropValidation.invalid("Expired portion")
	func try_apply_drop(payload: HeldItemPayload) -> bool:
		if not accepts(payload).is_valid:
			return false
		return (payload.metadata.portion as IngredientPortion).commit(_apply)
	func _apply() -> bool:
		applied += 1
		if callback.is_valid():
			callback.call()
		return true

var checks := 0
var failures: Array[String] = []
var host := Node2D.new()
var controller := InteractionController.new()
var inventory := InventoryState.new()
var modal_root := Control.new()
var owner := Control.new()
var dimmer := Control.new()
var page_control := Control.new()
var other_panel := Control.new()
var export_layer := Node2D.new()
var source := Node2D.new()
var target := ContractTarget.new()
var forbidden := ContractTarget.new()
var canceled := 0
var dropped := 0
var actions := 0
var callback_attempted := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames() -> void:
	await process_frame
	await process_frame

func new_portion() -> Dictionary:
	var portion := IngredientPortion.new(&"sugar", &"spoonful", source, inventory)
	portion.token = inventory.reserve(portion.item_id, portion.unit, 1, portion.source_id)
	var visual := Node2D.new()
	var payload := portion.create_payload(visual)
	payload.source = &"khata"
	return {"portion": portion, "visual": visual, "payload": payload}

func begin(record: Dictionary, ignored: Array[Control] = [owner, dimmer]) -> bool:
	var allowed: Array[DropZone] = [target]
	return controller.begin_modal_export(owner, record.payload, record.visual, Vector2(400, 400), export_layer, allowed, ignored)

func dispose_unstarted(record: Dictionary) -> void:
	record.portion.cancel()
	if is_instance_valid(record.visual) and not record.visual.is_queued_for_deletion():
		record.visual.free()

func check_returned(label: String) -> void:
	check(not controller.is_dragging() and not controller.is_modal_export_active(), "%s clears its exact session" % label)
	check(inventory.remaining(&"sugar") == 3 and inventory.available(&"sugar") == 3, "%s returns its unused reservation" % label)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s restores the mouse mode" % label)
	check(not target.debug_preview.visible, "%s clears target highlight" % label)

func _on_canceled(_payload: HeldItemPayload) -> void:
	canceled += 1

func _on_dropped(_payload: HeldItemPayload, _zone: DropZone) -> void:
	dropped += 1

func _on_action(_action: StringName) -> void:
	actions += 1

func reenter_commit() -> void:
	controller.end_modal_export(owner)
	controller.cancel_drag()
	var record := new_portion()
	callback_attempted = begin(record)
	dispose_unstarted(record)
	controller.set_mode(InteractionController.MODE_ORGANIZE)

func run() -> void:
	root.size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var normal_layer := Node2D.new()
	normal_layer.name = "DragLayer"
	host.add_child(normal_layer)
	var zones := Node2D.new()
	zones.name = "Zones"
	host.add_child(zones)
	controller.drag_layer_path = NodePath("../DragLayer")
	controller.drop_zone_root_path = NodePath("../Zones")
	host.add_child(controller)
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	host.add_child(canvas)
	modal_root.size = Vector2(1920, 1080)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(modal_root)
	owner.size = modal_root.size
	modal_root.add_child(owner)
	dimmer.size = owner.size
	owner.add_child(dimmer)
	page_control.position = Vector2(100, 100)
	page_control.size = Vector2(100, 100)
	owner.add_child(page_control)
	export_layer.position = Vector2(35, 42)
	export_layer.scale = Vector2(1.5, 0.8)
	owner.add_child(export_layer)
	owner.add_child(source)
	other_panel.position = Vector2(900, 400)
	other_panel.size = Vector2(100, 100)
	canvas.add_child(other_panel)
	target.position = Vector2(650, 500)
	target.controller = controller
	zones.add_child(target)
	forbidden.position = Vector2(800, 500)
	forbidden.controller = controller
	zones.add_child(forbidden)
	root.add_child(host)
	controller.modal_root = modal_root
	controller.drag_canceled.connect(_on_canceled)
	controller.drag_dropped.connect(_on_dropped)
	controller.action_requested.connect(_on_action)
	check(inventory.reset({&"sugar": 3}, {&"sugar": &"spoonful"}), "Fixture uses the production inventory authority")
	await frames()
	var record := new_portion()
	check(not begin(record), "A visible panel without an explicit owner lock cannot export")
	dispose_unstarted(record)
	controller.set_world_input_blocked(owner, true)
	record = new_portion()
	record.payload.metadata.cleanup_callback = Callable()
	check(not begin(record), "A payload cannot replace its reservation cleanup with an invalid callback")
	dispose_unstarted(record)
	record = new_portion()
	var bad_ignored: Array[Control] = [owner, dimmer, other_panel]
	check(not begin(record, bad_ignored), "An owner cannot exempt unrelated UI from target coverage")
	dispose_unstarted(record)
	var sibling := Control.new()
	modal_root.add_child(sibling)
	record = new_portion()
	check(not begin(record), "Another visible modal prevents export even without its own blocker")
	dispose_unstarted(record)
	sibling.hide()
	controller.set_world_input_blocked(sibling, true)
	record = new_portion()
	check(not begin(record), "Another explicit blocker prevents export even when its panel is hidden")
	dispose_unstarted(record)
	controller.set_world_input_blocked(sibling, false)
	sibling.queue_free()
	await frames()
	for mode in [InteractionController.MODE_NEUTRAL, InteractionController.MODE_ORGANIZE, InteractionController.MODE_INTERACT]:
		controller.set_mode(mode)
		record = new_portion()
		check(begin(record), "Owned export begins from %s without changing intent" % mode)
		check(controller.current_mode == mode and controller.is_world_input_blocked(), "Export preserves prior mode and ordinary world block")
		check(not controller.can_start_world_action() and not controller.lock_action(source), "Export never enables another source or held action")
		check(record.visual.get_parent() == export_layer, "Export visual uses the modal-owned layer")
		controller.update_drag(target.global_position)
		check(record.visual.get_global_transform_with_canvas().origin.is_equal_approx(target.global_position), "Transformed export layer keeps the visual at the viewport pointer")
		check(controller.can_address_drop_zone(record.payload, target) and not controller.can_address_drop_zone(record.payload, forbidden), "Only the exact allowlisted target is authorized")
		check(not controller.can_address_drop_zone(HeldItemPayload.new(), target), "Another payload cannot borrow the active session")
		var space := InputEventAction.new()
		space.action = InteractionController.INPUT_POUR
		space.pressed = true
		controller._input(space)
		check(actions == 0, "Space cannot forward a pouring action during export")
		var before := inventory.remaining(&"sugar")
		controller.release_drop(target.global_position)
		check(inventory.remaining(&"sugar") == before - 1 and inventory.available(&"sugar") == before - 1, "Authorized contract target commits one shared portion")
		check(not controller.is_modal_export_active() and controller.is_world_input_blocked() and controller.current_mode == mode, "Successful export returns to reading with lock and prior intent preserved")
		check(not target.try_apply_drop(record.payload), "Repeated delivered export cannot apply or debit again")
	check(target.applied == 3 and canceled == 0 and dropped == 3, "Three successful exports emit exactly three committed gestures")
	inventory.reset({&"sugar": 3}, {&"sugar": &"spoonful"})
	for reason in ["forbidden target", "page child", "unrelated panel", "explicit end", "hidden owner", "removed owner", "source removal", "reset", "mode", "focus", "resize"]:
		record = new_portion()
		check(begin(record), "%s cancellation starts an export" % reason)
		controller.update_drag(target.global_position)
		match reason:
			"forbidden target": controller.release_drop(forbidden.global_position)
			"page child": controller.release_drop(page_control.position + Vector2(30, 30))
			"unrelated panel": controller.release_drop(other_panel.position + Vector2(30, 30))
			"explicit end": controller.end_modal_export(owner)
			"hidden owner": owner.hide()
			"removed owner": modal_root.remove_child(owner)
			"source removal": owner.remove_child(source)
			"reset": inventory.reset({&"sugar": 3}, {&"sugar": &"spoonful"})
			"mode": controller.set_mode(InteractionController.MODE_NEUTRAL if controller.current_mode != InteractionController.MODE_NEUTRAL else InteractionController.MODE_INTERACT)
			"focus": controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"resize": root.size_changed.emit()
		await frames()
		check_returned(reason)
		if owner.get_parent() == null:
			modal_root.add_child(owner)
		if source.get_parent() == null:
			owner.add_child(source)
		owner.show()
		controller.set_world_input_blocked(owner, true)
	# Ignoring the dimmer never ignores page controls underneath it.
	record = new_portion()
	check(begin(record), "UI-covered allowed target starts an export")
	var original_target := target.position
	target.position = page_control.position + Vector2(30, 30)
	controller.release_drop(target.position)
	check_returned("Allowed target behind a page child")
	target.position = original_target
	var temporary_target := ContractTarget.new()
	temporary_target.controller = controller
	temporary_target.position = Vector2(1000, 650)
	host.add_child(temporary_target)
	record = new_portion()
	var temporary_allowed: Array[DropZone] = [temporary_target]
	var ignored: Array[Control] = [owner, dimmer]
	check(controller.begin_modal_export(owner, record.payload, record.visual, Vector2(400, 400), export_layer, temporary_allowed, ignored), "An explicitly allowed temporary target does not require ordinary registration")
	controller.update_drag(temporary_target.position)
	check(controller.hovered_drop_zone == temporary_target, "Explicit temporary target participates in export selection")
	temporary_target.queue_free()
	await frames()
	controller.release_drop(Vector2(1000, 650))
	check_returned("Destroyed allowlisted target")
	record = new_portion()
	controller.drag_started.connect(func(_payload: HeldItemPayload, _visual: Node2D) -> void: owner.hide(), CONNECT_ONE_SHOT)
	check(not begin(record), "A startup callback that hides its owner invalidates the export immediately")
	check_returned("Owner hidden during export startup")
	owner.show()
	controller.set_mode(InteractionController.MODE_INTERACT)
	target.callback = reenter_commit
	canceled = 0
	dropped = 0
	record = new_portion()
	check(begin(record), "Reentrant target test begins an export")
	controller.release_drop(target.position)
	check(not callback_attempted and canceled == 0 and dropped == 1, "Commit callbacks cannot replace or cancel the resolving export")
	check(inventory.remaining(&"sugar") == 2 and inventory.available(&"sugar") == 2 and controller.current_mode == InteractionController.MODE_ORGANIZE, "Commit deducts once and applies queued mode only after cleanup")
	target.callback = Callable()
	inventory.reset({&"sugar": 3}, {&"sugar": &"spoonful"})
	record = new_portion()
	check(begin(record), "Owner unblock test begins an export")
	controller.set_world_input_blocked(owner, false)
	check_returned("Explicit owner unblock")
	controller.set_world_input_blocked(owner, true)
	record = new_portion()
	check(begin(record), "Scene exit test begins an export")
	host.queue_free()
	await frames()
	check(inventory.remaining(&"sugar") == 3 and inventory.available(&"sugar") == 3, "Scene teardown releases the exported reservation")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Scene teardown restores pointer visibility")
	print("Khata export checks: %d; failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
