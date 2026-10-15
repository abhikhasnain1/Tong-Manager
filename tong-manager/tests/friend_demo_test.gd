extends "res://tests/cup_reuse_integration_test.gd"
## The demo scene with real viewport events, plus the existing cup-reuse contract.

const DEMO := preload("res://scenes/development/FriendDemo.tscn")
var held_mask := 0


func setup() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		await frames()
	root.get_node("GameState").reset_demo_state()
	screen = DEMO.instantiate()
	screen.customer_queue_auto_start = false
	root.add_child(screen)
	await frames(3)
	controller = screen.get_node("InteractionController")
	queue = screen.customer_queue
	service = screen.customer_service
	stock = root.get_node("GameState").inventory
	queue.set_process(false)
	queue.reduced_motion = true
	received.clear()
	service.service_accepted.connect(func(record: Dictionary): received.append(record))
	check(controller.direct_mouse_gestures and controller.current_mode == InteractionController.MODE_INTERACT,
		"Demo starts ready for direct left use and right move")


func move_pointer(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless": root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_screen_transform() * point
	motion.button_mask = held_mask
	Input.parse_input_event(motion)
	await frames()


func mouse_button(point: Vector2, pressed: bool, index: MouseButton) -> void:
	await move_pointer(point)
	var mask := MOUSE_BUTTON_MASK_RIGHT if index == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	held_mask = held_mask | mask if pressed else held_mask & ~mask
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform() * point
	event.button_index = index
	event.pressed = pressed
	event.button_mask = held_mask
	Input.parse_input_event(event)
	await frames()


func mouse(point: Vector2, pressed: bool) -> void:
	await mouse_button(point, pressed, MOUSE_BUTTON_LEFT)


func sprite_point(owner_node: Node2D, sprite: Sprite2D) -> Vector2:
	var rect := sprite.get_rect()
	var samples := [10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16]
	for y in samples:
		for x in samples:
			var local := rect.position + rect.size * Vector2(x / 20.0, y / 20.0)
			if not sprite.is_pixel_opaque(local): continue
			var point := sprite.get_global_transform_with_canvas() * local
			if not root.get_visible_rect().has_point(point): continue
			screen.hover_feedback.update_feedback(0.0, point)
			if screen.hover_feedback.get_hovered_owner() == owner_node: return point
	return Vector2.INF


func presentation_check() -> void:
	await setup()
	var main_scene: PackedScene = load("res://scenes/app/Main.tscn")
	var main := main_scene.instantiate()
	check(main.initial_screen.resource_path == DEMO.resource_path, "F5 launches the friend demo")
	main.free()
	check(not screen.get_node("HUDLayer/RootUI/IntentControls").is_visible_in_tree(), "Mode and instructional panels are hidden")
	check(not screen.get_node("HUDLayer/RootUI/EndDayButton").is_visible_in_tree(), "Unimplemented end-day button is hidden")
	for path in ["WorldRoot/ToolLayer", "WorldRoot/DropZoneRoot"]:
		for label in screen.get_node(path).find_children("*", "Label", true, false):
			check(not label.is_visible_in_tree(), "Station copy is hidden: " + String(label.name))
	var schedule: CustomerSchedule = screen.day_config.customer_schedule
	var drink_count := 0
	for arrival in schedule.arrivals:
		if arrival.request.id == &"tea_cha_no_sugar": drink_count += 1
	check(schedule.arrivals.size() == 10 and drink_count == 8, "Existing reusable-cup day has eight drinks and two snack visits")
	check(screen.start_customer_queue(), "Actual demo schedule starts")
	queue.advance(9.0)
	await frames(4)
	await move_pointer(Vector2(700, 650) * root.get_visible_rect().size / Vector2(1920, 1080))
	await capture("00-demo-overview")
	var paths := [
		["WorldRoot/ToolLayer/WaterDrum", "Icon", "water"],
		["WorldRoot/DropZoneRoot/DiscardArea", "Basket", "wastebasket"],
		["WorldRoot/ToolLayer/BucketStation", "Sprite", "bucket"],
		["WorldRoot/ToolLayer/KhataStation/KhataHotspot", "Sprite", "khata"],
		["WorldRoot/ToolLayer/KettleStation", "Body", "kettle"],
	]
	for entry in paths:
		var owner_node := screen.get_node(entry[0]) as Node2D
		var sprite := owner_node.get_node_or_null(entry[1]) as Sprite2D
		if sprite == null and owner_node is Kettle: sprite = owner_node.get_node("Sprite") as Sprite2D
		check(sprite != null, "Presentation sprite exists: " + entry[2])
		if sprite == null: continue
		var point := sprite_point(owner_node, sprite)
		check(point.is_finite(), "Visible hover silhouette exists: " + entry[2])
		if not point.is_finite(): continue
		await move_pointer(point)
		if DisplayServer.get_name() == "headless": screen.hover_feedback.update_feedback(0.0, point)
		check(screen.hover_feedback.get_hovered_owner() == owner_node and sprite.material is ShaderMaterial,
			"Viewport hover outlines and enlarges " + entry[2])
		await capture("01-hover-" + entry[2])
	var stove: Stove = screen.get_node("WorldRoot/ToolLayer/StoveStation")
	for burner in stove.burners: burner.set_heat(3)
	await move_pointer(Vector2(700, 650) * root.get_visible_rect().size / Vector2(1920, 1080))
	await capture("02-flames-and-roof")
	for burner in stove.burners: burner.set_heat(0)


func native_direct_gestures() -> void:
	if DisplayServer.get_name() == "headless": return
	await setup()
	var cup: Cup = screen.get_cups()[0]
	var origin := cup.get_global_transform_with_canvas().origin
	await mouse_button(origin, true, MOUSE_BUTTON_RIGHT)
	check(controller.current_drag_node == cup and controller.is_move_drag(), "Native right press picks the real cup for movement")
	var destination: Vector2 = screen.world_root.get_global_transform_with_canvas() * Vector2(860, 900)
	await mouse_button(destination, false, MOUSE_BUTTON_RIGHT)
	check(cup.get_node("PlacementHandle").surface == screen.table_surface, "Native right release commits cup outside tray")
	var waste: DiscardDropZone = screen.get_node("WorldRoot/DropZoneRoot/DiscardArea")
	fill(cup)
	await mouse(cup.get_global_transform_with_canvas().origin, true)
	check(controller.current_drag_node == cup and not controller.is_move_drag(), "Native left press uses a cup")
	await mouse_button(waste.get_global_transform_with_canvas().origin, true, MOUSE_BUTTON_RIGHT)
	await mouse_button(waste.get_global_transform_with_canvas().origin, false, MOUSE_BUTTON_RIGHT)
	check(controller.current_drag_node == cup and cup.volume_ml > 0.0, "Crossed right press/release cannot empty or move a left-held cup")
	await mouse(waste.get_global_transform_with_canvas().origin, false)
	check(not cup.has_contents() and not controller.is_dragging(), "Left release over drawn wastebasket empties contents")
	var sugar := source(&"sugar")
	var source_point := sugar.source_owner.get_global_transform_with_canvas().origin
	var available := stock.available(&"sugar")
	await mouse_button(source_point, true, MOUSE_BUTTON_RIGHT)
	check(controller.current_drag_node == sugar.source_owner and stock.available(&"sugar") == available,
		"Native right press moves a container without taking ingredients")
	await mouse_button(Vector2(-50, -50), false, MOUSE_BUTTON_RIGHT)
	await mouse(source_point, true)
	check(controller.is_portion_drag() and stock.available(&"sugar") == available - 1, "Native left press takes one sugar spoonful")
	await mouse(Vector2(-50, -50), false)
	check(stock.available(&"sugar") == available, "Unused spoonful reservation returns")
	var water: WaterDrum = screen.get_node("WorldRoot/ToolLayer/WaterDrum")
	var kettle: Kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	await mouse(water.get_global_transform_with_canvas().origin, true)
	check(controller.current_drag_node == water, "Native left press picks the redrawn water supply")
	await mouse(kettle.get_node("WaterFillTarget").get_global_transform_with_canvas().origin, false)
	check(kettle.volume_ml > 0.0 and not controller.is_dragging(), "Water supply fills kettle and returns to its grouped home")
	var modal: KhataModal = screen.khata_modal
	var khata: Area2D = screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot")
	await mouse(khata.get_global_transform_with_canvas().origin, true)
	await mouse(khata.get_global_transform_with_canvas().origin, false)
	var deadline := Time.get_ticks_msec() + 5000
	while modal.is_traveling() and Time.get_ticks_msec() < deadline: await frames()
	check(modal.is_peeking(), "Grouped notebook opens by clicking its visible cover")
	await capture("03-khata-peek")
	modal.close_peek()
	deadline = Time.get_ticks_msec() + 5000
	while modal.is_traveling() and Time.get_ticks_msec() < deadline: await frames()
	check(modal.cover.is_visible_in_tree(), "Notebook returns to its actual grouped cover position")


func run() -> void:
	if DisplayServer.get_name() == "headless": root.size = Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	await frames()
	await presentation_check()
	await native_direct_gestures()
	await three_cup_batch()
	await seven_reuse_cycles()
	if is_instance_valid(screen): screen.queue_free()
	await frames()
	# Accelerated handoffs can leave the final MP3 stop queued on the audio
	# mixer after all scene nodes are freed. Drain it before this test exits.
	await create_timer(0.35).timeout
	print("FRIEND_DEMO: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
