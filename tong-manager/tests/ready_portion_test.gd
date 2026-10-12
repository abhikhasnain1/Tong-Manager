extends SceneTree

class FixedSourceFixture extends Node2D:
	var input_area := Area2D.new()
	var source := IngredientPortionSource.new()
	var frontmost := true

	func _init() -> void:
		input_area.name = "MovingInput"
		input_area.position = Vector2(9,13)
		add_child(input_area)
		add_child(source)

	func contains_pointer(point: Vector2) -> bool:
		return Rect2(-20,-30,40,60).has_point(input_area.get_global_transform_with_canvas().affine_inverse() * point)

	func is_frontmost_at(_point: Vector2) -> bool:
		return frontmost

class ReadyTarget extends DropZone:
	var controller: InteractionController
	var accepted_item := &"banana"
	var accepted_count := 0

	func _init() -> void:
		var sprite := Sprite2D.new()
		sprite.name = "DebugPreview"
		sprite.visible = false
		add_child(sprite)
		snap_radius = 24

	func is_relevant_to(payload: HeldItemPayload) -> bool:
		return payload != null and payload.metadata.get("category") == &"ready_item"

	func accepts(payload: HeldItemPayload) -> DropValidation:
		if (not is_relevant_to(payload) or controller.current_payload != payload
			or controller.current_mode != InteractionController.MODE_INTERACT or not is_inside_tree()):
			return DropValidation.invalid("Inactive ready item")
		var portion := payload.metadata.get("portion") as IngredientPortion
		if portion == null or not portion.is_available() or payload.item_id != accepted_item:
			return DropValidation.invalid("This target wants another item")
		return DropValidation.valid()

	func try_apply_drop(payload: HeldItemPayload) -> bool:
		if not accepts(payload).is_valid:
			return false
		return (payload.metadata.portion as IngredientPortion).commit(_accept_piece)

	func _accept_piece() -> bool:
		accepted_count += 1
		return true

var checks := 0
var failures: Array[String] = []
var host := Node2D.new()
var controller := InteractionController.new()
var stock := DevelopmentPortionStock.new()
var first: FixedSourceFixture
var second: FixedSourceFixture
var biscuits: FixedSourceFixture
var target := ReadyTarget.new()
var reentered := false
var canceled_count := 0
var dropped_count := 0
var reserve_action := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func add_source(item_id: StringName, point: Vector2) -> FixedSourceFixture:
	var fixture := FixedSourceFixture.new()
	fixture.position = point
	host.add_child(fixture)
	fixture.source.configure_fixed(controller,item_id,&"piece",fixture,fixture.input_area,fixture.contains_pointer,fixture.is_frontmost_at)
	fixture.source.set_provider(stock)
	return fixture

func at(fixture: FixedSourceFixture) -> Vector2:
	return fixture.input_area.get_global_transform_with_canvas().origin

func take(fixture: FixedSourceFixture) -> HeldItemPayload:
	var before := fixture.transform
	var parent := fixture.get_parent()
	check(fixture.source.begin_portion(at(fixture)),"A fixed %s source begins one ready piece" % fixture.source.item_id)
	check(fixture.transform == before and fixture.get_parent() == parent,"Extracting a piece leaves the fixed source attached and unchanged")
	return controller.current_payload

func assert_returned(item_id: StringName, before: int, reason: String) -> void:
	check(controller.current_payload == null and not controller.is_dragging(),"%s clears the held ready item" % reason)
	check(stock.remaining(item_id) == before and stock.available(item_id) == before,"%s returns exactly the reserved item" % reason)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and controller._portion_mouse_mode == -1,"%s restores and releases ownership of the regular pointer" % reason)

func on_commit_changed() -> void:
	controller.cancel_drag()
	reentered = second.source.begin_portion(at(second))
	controller.set_mode(InteractionController.MODE_ORGANIZE)

func on_reserve_changed() -> void:
	match reserve_action:
		"reset": stock.reset_fixture()
		"replace": first.source.set_provider(DevelopmentPortionStock.new())
		"reconfigure": first.source.configure_fixed(controller,&"biscuits",&"piece",first,first.input_area,first.contains_pointer,first.is_frontmost_at)
		"detach_area": first.remove_child(first.input_area)

func run() -> void:
	root.size = Vector2i(1920,1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var drag_layer := Node2D.new()
	drag_layer.name = "DragLayer"
	host.add_child(drag_layer)
	var zones := Node2D.new()
	zones.name = "Zones"
	host.add_child(zones)
	controller.drag_layer_path = NodePath("../DragLayer")
	controller.drop_zone_root_path = NodePath("../Zones")
	host.add_child(controller)
	root.add_child(host)
	first = add_source(&"banana",Vector2(100,200))
	second = add_source(&"banana",Vector2(230,200))
	biscuits = add_source(&"biscuits",Vector2(350,200))
	target.controller = controller
	target.position = Vector2(850,650)
	zones.add_child(target)
	await process_frame
	check(stock.remaining(&"banana") == 6 and stock.remaining(&"biscuits") == 8,"Ready-item fixture has finite explicit piece counts")
	for id in [&"banana",&"biscuits"]:
		var definition := load("res://data/items/%s.tres" % id) as Resource
		check(definition.id == id and definition.category == &"ready_item" and definition.unit == &"piece","Fixture %s preserves the existing catalog identity/category/unit" % id)
		check(stock.reserve(id,&"spoonful",1,first.get_instance_id()) == 0,"Ready pieces cannot be reserved as spoonfuls")
	for mode in [InteractionController.MODE_NEUTRAL,InteractionController.MODE_ORGANIZE]:
		controller.set_mode(mode)
		check(not first.source.begin_portion(at(first)),"%s never detaches a fixed source or extracts contents" % mode)
	controller.set_mode(InteractionController.MODE_INTERACT)
	first.source.set_provider(null)
	check(not first.source.begin_portion(at(first)) and controller.current_payload == null,"Normal fixed source remains unavailable without an injected provider")
	first.source.set_provider(stock)
	for action in ["reset","replace","reconfigure","detach_area"]:
		reserve_action = action
		stock.changed.connect(on_reserve_changed,CONNECT_ONE_SHOT)
		check(not first.source.begin_portion(at(first)),"Synchronous %s cannot create a stale fixed-source piece" % action)
		assert_returned(&"banana",6,"Reservation %s" % action)
		if first.input_area.get_parent() == null:
			first.add_child(first.input_area)
		first.source.configure_fixed(controller,&"banana",&"piece",first,first.input_area,first.contains_pointer,first.is_frontmost_at)
		first.source.set_provider(stock)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at(first)
	first.frontmost = false
	first.source._on_input(root,event,0)
	check(controller.current_payload == null,"Covered fixed source cannot extract through the frontmost callback")
	first.frontmost = true
	event.position += Vector2(80,0)
	first.source._on_input(root,event,0)
	check(controller.current_payload == null,"Fixed source respects its moving hit callback")
	first.input_area.position += Vector2(55,-9)
	first.rotation = 0.2
	event.position = at(first)
	first.source._on_input(root,event,0)
	check(controller.is_dragging(),"The changed moving-area pose remains usable")
	controller.cancel_drag()
	assert_returned(&"banana",6,"Moving-area pickup cancellation")
	var payload := take(first)
	if payload == null:
		host.queue_free()
		quit(1)
		return
	check(payload.item_id == &"banana" and payload.quantity == 1 and payload.metadata.category == &"ready_item"
		and payload.metadata.unit == &"piece" and payload.metadata.source_id == first.get_instance_id(),"Ready payload preserves exactly one item, unit and actual source identity")
	check(payload.metadata.portion is IngredientPortion and controller.is_portion_drag(),"Ready items use the common portion transaction rather than cup logic")
	check(payload.world_node != first and payload.metadata.transient and controller._portion_mouse_mode == Input.MOUSE_MODE_VISIBLE,"One separate piece follows the cursor with reversible pointer ownership")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN,"The held piece suppresses a duplicate hardware cursor")
	check(stock.available(&"banana") == 5 and second.source.provider.available(&"banana") == 5 and stock.remaining(&"banana") == 6,"Two bunches share one reservation balance without consuming on pickup")
	controller.update_drag(target.position)
	check(controller.hovered_drop_zone == target and controller.current_hint.contains("hand over"),"Ready target uses handoff feedback rather than a vessel hint")
	controller.update_drag(Vector2(1200,800))
	check(controller.hovered_drop_zone == null and controller.current_hint == "Move this portion over a valid target · Esc cancels","Leaving a ready target clears its stale acceptance hint")
	controller.release_drop(Vector2(1200,800))
	assert_returned(&"banana",6,"Invalid release")
	for reason in ["neutral","organize","focus","modal"]:
		controller.set_mode(InteractionController.MODE_INTERACT)
		take(first)
		match reason:
			"neutral": controller.set_mode(InteractionController.MODE_NEUTRAL)
			"organize": controller.set_mode(InteractionController.MODE_ORGANIZE)
			"focus": controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"modal": controller.set_world_input_blocked(host,true)
		assert_returned(&"banana",6,reason)
		controller.set_world_input_blocked(host,false)
	controller.set_mode(InteractionController.MODE_INTERACT)
	payload = take(first)
	controller.release_drop(target.position)
	check(target.accepted_count == 1 and stock.remaining(&"banana") == 5 and stock.available(&"banana") == 5,"Accepted ready item applies and deducts once")
	check(not target.try_apply_drop(payload) and target.accepted_count == 1 and stock.remaining(&"banana") == 5,"Repeating an accepted payload cannot apply or deduct again")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Accepted handoff restores the pointer")
	controller.drag_canceled.connect(func(_payload: HeldItemPayload): canceled_count += 1)
	controller.drag_dropped.connect(func(_payload: HeldItemPayload,_zone: DropZone): dropped_count += 1)
	take(second)
	stock.changed.connect(on_commit_changed,CONNECT_ONE_SHOT)
	controller.release_drop(target.position)
	check(not reentered and canceled_count == 0 and dropped_count == 1 and controller.current_payload == null,"Ready handoff is protected against cancel/new-pickup callback reentry")
	check(target.accepted_count == 2 and stock.remaining(&"banana") == 4 and controller.current_mode == InteractionController.MODE_ORGANIZE,"Ready commit applies once before a queued mode change")
	controller.set_mode(InteractionController.MODE_INTERACT)
	for index in 4:
		take(first if index % 2 == 0 else second)
		controller.release_drop(target.position)
	check(stock.available(&"banana") == 0 and not first.source.begin_portion(at(first)) and not second.source.begin_portion(at(second)),"Shared depleted banana balance cannot yield another piece from either bunch")
	check(first.is_inside_tree() and second.is_inside_tree(),"Depletion leaves both fixed sources attached")
	stock.reset_fixture()
	payload = take(biscuits)
	check(payload.item_id == &"biscuits" and payload.metadata.category == &"ready_item" and payload.metadata.unit == &"piece","Biscuit uses its catalog identity and one ready piece")
	controller.release_drop(target.position)
	assert_returned(&"biscuits",8,"Wrong ready target")
	target.accepted_item = &"biscuits"
	for index in 8:
		take(biscuits)
		controller.release_drop(target.position)
	check(stock.remaining(&"biscuits") == 0 and stock.available(&"biscuits") == 0 and not biscuits.source.begin_portion(at(biscuits)),"Biscuit pieces deplete finitely through accepted commits")
	stock.reset_fixture()
	take(biscuits)
	stock.reset_fixture()
	await process_frame
	assert_returned(&"biscuits",8,"Fixture reset")
	take(first)
	first.source.set_provider(null)
	assert_returned(&"banana",6,"Provider replacement")
	first.source.set_provider(stock)
	take(first)
	first.remove_child(first.input_area)
	await process_frame
	assert_returned(&"banana",6,"Moving input-area removal")
	first.add_child(first.input_area)
	take(first)
	first.remove_child(first.source)
	assert_returned(&"banana",6,"Source adapter removal")
	first.add_child(first.source)
	take(first)
	first.queue_free()
	await process_frame
	assert_returned(&"banana",6,"Fixed owner deletion")
	take(second)
	var visual := controller.current_drag_node
	visual.queue_free()
	await process_frame
	await process_frame
	assert_returned(&"banana",6,"Held visual deletion")
	take(biscuits)
	root.remove_child(host)
	assert_returned(&"biscuits",8,"Scene exit")
	root.add_child(host)
	await process_frame
	check(biscuits.source.begin_portion(at(biscuits)),"Retained scene re-entry clears the controller teardown latch")
	controller.cancel_drag()
	assert_returned(&"biscuits",8,"Cancellation after scene re-entry")
	host.queue_free()
	await process_frame
	print("READY_PORTIONS: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
