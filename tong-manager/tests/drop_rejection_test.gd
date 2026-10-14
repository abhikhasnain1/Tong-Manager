extends SceneTree
## Invalid release feedback is distinct from passive hover and ordinary cancel.

class TestController extends InteractionController:
	var pointer_blocked := false
	func _drag_pointer_over_ui(_point: Vector2) -> bool:
		return pointer_blocked

class TestTarget extends DropZone:
	var controller: InteractionController
	var relevant := true
	var valid := false
	var rejections := 0
	var applications := 0
	var callback: Callable
	var last_payload: HeldItemPayload
	var last_reason := ""
	func _init() -> void:
		var preview := Sprite2D.new()
		preview.name = "DebugPreview"
		preview.hide()
		add_child(preview)
		snap_radius = 30.0
	func is_relevant_to(_payload: HeldItemPayload) -> bool:
		return relevant
	func accepts(_payload: HeldItemPayload) -> DropValidation:
		return DropValidation.valid() if valid else DropValidation.invalid("Target unavailable in this test")
	func on_rejected_release(payload: HeldItemPayload, validation: DropValidation) -> void:
		rejections += 1
		last_payload = payload
		last_reason = validation.reason_key
		if callback.is_valid(): callback.call()
	func try_apply_drop(_payload: HeldItemPayload) -> bool:
		applications += 1
		controller.restore_drag_origin()
		return true

var checks := 0
var failures: Array[String] = []
var host: Node2D
var controller: TestController
var zone_root: Node2D
var origin: Node2D
var item: Node2D
var target: TestTarget
var stock := InventoryState.new()
var source: Node2D
var canceled := 0
var dropped := 0


func _init() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func frames() -> void:
	await process_frame
	await process_frame


func setup() -> void:
	host = Node2D.new()
	origin = Node2D.new()
	origin.name = "Origin"
	origin.transform = Transform2D(0.12, Vector2(1.3, 0.8), 0.0, Vector2(80, 30))
	host.add_child(origin)
	item = Node2D.new()
	item.transform = Transform2D(-0.2, Vector2(0.7, 1.4), 0.0, Vector2(12, 24))
	origin.add_child(item)
	var layer := Node2D.new()
	layer.name = "DragLayer"
	host.add_child(layer)
	zone_root = Node2D.new()
	zone_root.name = "DropZones"
	host.add_child(zone_root)
	controller = TestController.new()
	controller.drag_layer_path = NodePath("../DragLayer")
	controller.drop_zone_root_path = NodePath("../DropZones")
	host.add_child(controller)
	target = TestTarget.new()
	target.position = Vector2(500, 400)
	target.controller = controller
	zone_root.add_child(target)
	source = Node2D.new()
	host.add_child(source)
	root.add_child(host)
	controller.set_mode(InteractionController.MODE_USE)
	controller.drag_canceled.connect(func(_payload: HeldItemPayload) -> void: canceled += 1)
	controller.drag_dropped.connect(func(_payload: HeldItemPayload, _target: DropZone) -> void: dropped += 1)
	check(stock.reset({&"banana": 3}, {&"banana": &"piece"}), "Shared inventory fixture initializes")


func begin_item() -> HeldItemPayload:
	var payload := HeldItemPayload.new(&"cup", &"test_cup", 1, item, {"category": &"cup"})
	check(controller.start_drag(payload, item, Vector2(120, 100)), "A nontransient vessel gesture starts")
	return payload


func begin_portion() -> Dictionary:
	var portion := IngredientPortion.new(&"banana", &"piece", source, stock)
	portion.token = stock.reserve(portion.item_id, portion.unit, 1, portion.source_id)
	var visual := Node2D.new()
	var payload := portion.create_payload(visual)
	check(controller.start_drag(payload, visual, Vector2(120, 100)), "A reserved ready-item gesture starts")
	return {"portion": portion, "payload": payload, "visual": weakref(visual)}


func check_rejection_and_guard() -> void:
	var original := item.transform
	var payload := begin_item()
	for _index in 4: controller.update_drag(target.position)
	check(target.rejections == 0 and target.applications == 0, "Repeated invalid hover performs no release feedback or command")
	var reentry := {"started": true, "world": true, "locked": true, "mode_inside": &""}
	target.callback = func() -> void:
		controller.cancel_drag()
		controller.release_drop(target.position)
		var intruder := Node2D.new()
		reentry.started = controller.start_drag(HeldItemPayload.new(&"cup", &"other", 1, intruder), intruder, Vector2.ZERO)
		intruder.free()
		reentry.world = controller.can_start_world_action()
		reentry.locked = controller.lock_action(source)
		controller.set_mode(InteractionController.MODE_ORGANIZE)
		reentry.mode_inside = controller.current_mode
	controller.release_drop(target.position)
	target.callback = Callable()
	check(target.rejections == 1 and target.last_payload == payload and target.last_reason == "Target unavailable in this test",
		"One actual invalid release receives its original payload and validation")
	check(canceled == 1 and dropped == 0 and not controller.is_dragging(), "Rejected release finishes as exactly one canceled gesture")
	check(item.get_parent() == origin and item.transform == original, "Rejected cup restores the exact authored parent and transform")
	check(not reentry.started and not reentry.world and not reentry.locked and reentry.mode_inside == InteractionController.MODE_USE,
		"Rejection observers cannot replace/cancel/release the resolving gesture or start another action")
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Requested mode change occurs after rejection rollback")
	controller.release_drop(target.position)
	check(target.rejections == 1 and canceled == 1, "A repeated mouse release cannot report the same rejection twice")
	controller.set_mode(InteractionController.MODE_USE)
	var record := begin_portion()
	controller.release_drop(target.position)
	await frames()
	check(target.rejections == 2 and record.portion.finished, "Ready-item rejection closes the original reservation")
	check(stock.remaining(&"banana") == 3 and stock.available(&"banana") == 3 and record.visual.get_ref() == null,
		"Unavailable ready-item target loses no stock and leaves no transient visual")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not target.debug_preview.visible,
		"Rejection clears cursor and target highlighting")


func check_nonattempts() -> void:
	for reason in ["explicit cancel", "empty space", "irrelevant", "UI covered", "removed target", "mode change"]:
		var before := target.rejections
		var before_cancel := canceled
		begin_item()
		controller.update_drag(target.position)
		match reason:
			"explicit cancel": controller.cancel_drag()
			"empty space": controller.release_drop(Vector2(900, 600))
			"irrelevant":
				target.relevant = false
				controller.release_drop(target.position)
			"UI covered":
				controller.pointer_blocked = true
				controller.release_drop(target.position)
			"removed target":
				zone_root.remove_child(target)
				controller.release_drop(Vector2(500, 400))
			"mode change": controller.set_mode(InteractionController.MODE_NEUTRAL)
		check(target.rejections == before and canceled == before_cancel + 1,
			reason + " is ordinary cancellation, not a target-rejection attempt")
		target.relevant = true
		controller.pointer_blocked = false
		if target.get_parent() == null: zone_root.add_child(target)
		controller.set_mode(InteractionController.MODE_USE)
	var before := target.rejections
	target.valid = true
	begin_item()
	controller.release_drop(target.position)
	check(target.rejections == before and target.applications == 1 and dropped == 1,
		"Successful release preserves the existing apply path and never reports rejection")
	target.valid = false


func check_callback_removal() -> void:
	var before := canceled
	var record := begin_portion()
	target.callback = func() -> void: target.queue_free()
	controller.release_drop(target.position)
	await frames()
	check(canceled == before + 1 and stock.available(&"banana") == 3 and record.visual.get_ref() == null,
		"Target destruction from its rejection callback still completes one rollback")
	target = TestTarget.new()
	target.position = Vector2(500, 400)
	target.controller = controller
	zone_root.add_child(target)
	record = begin_portion()
	target.callback = func() -> void: host.remove_child(controller)
	controller.release_drop(target.position)
	await frames()
	check(not controller.is_dragging() and stock.available(&"banana") == 3 and record.visual.get_ref() == null,
		"Controller removal during feedback lets teardown clean up without reparenting into an exiting scene")
	controller.queue_free()


func run() -> void:
	await frames()
	setup()
	await frames()
	await check_rejection_and_guard()
	check_nonattempts()
	await check_callback_removal()
	host.queue_free()
	await frames()
	print("DROP_REJECTION: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
