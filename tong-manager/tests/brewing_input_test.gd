extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func move_pointer(at: Vector2, held: bool = true) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(motion, true)
	await physics_frame
	await process_frame

func mouse(at: Vector2, pressed: bool) -> void:
	await move_pointer(at, pressed)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.position = at
	click.pressed = pressed
	root.push_input(click, true)
	await physics_frame
	await process_frame

func pour_key(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = pressed
	Input.parse_input_event(key)
	await process_frame
	await process_frame

func aim_pointer(kettle: Kettle, target: Vector2) -> Vector2:
	var grip := kettle.get_node("GripAnchor") as Node2D
	return grip.get_global_transform_with_canvas().origin + target - kettle.get_pour_probe_viewport()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run brewing_input_test.gd with a window; physics mouse picking requires a display. Use brewing_contract_test.gd for headless checks.")
		quit(2)
		return
	var preview: Node = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	var stove: Stove = preview.stove
	var kettle: Kettle = preview.kettle
	var controller: InteractionController = preview.controller
	var dial: Area2D = stove.get_node("DialA")
	await mouse(dial.get_global_transform_with_canvas().origin, true)
	await mouse(dial.get_global_transform_with_canvas().origin, false)
	check(stove.burners[0].heat_level == 1, "Viewport click reaches left dial")
	check(stove.burners[1].heat_level == 0, "Viewport click leaves other dial off")
	kettle.apply_heat(10, 1)
	kettle.add_tea_leaves()
	kettle.apply_heat(3, 1)
	var original_transform := kettle.global_transform
	var pickup: Vector2 = kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin
	await mouse(pickup, true)
	check(controller.is_dragging(), "Viewport press picks up kettle")
	var grip := kettle.get_node("GripAnchor") as Node2D
	check(grip.get_global_transform_with_canvas().origin.is_equal_approx(pickup), "Viewport pickup keeps pointer on kettle grip")
	var cups: Node = preview.screen.get_node("WorldRoot/ToolLayer/TrayStation/Cups")
	var first_cup := cups.get_child(0) as Cup
	var target: Vector2 = first_cup.get_node("PourTarget").get_global_transform_with_canvas().origin
	await move_pointer(target)
	await pour_key(true)
	await create_timer(.05).timeout
	check(first_cup.volume_ml == 0 and not kettle.is_pouring, "Pointer covering cup cannot pour when spout misses")
	await pour_key(false)
	var pointer := Vector2.ZERO
	for child in cups.get_children():
		var cup := child as Cup
		target = cup.get_node("PourTarget").get_global_transform_with_canvas().origin
		pointer = aim_pointer(kettle, target) + Vector2(4, 0)
		await move_pointer(pointer)
		check(controller.hovered_drop_zone == cup.get_node("PourTarget"), "Spout selects %s" % cup.name)
		check(grip.get_global_transform_with_canvas().origin.is_equal_approx(pointer), "Cursor remains on grip for %s" % cup.name)
		check(pointer.distance_to(target) > 64, "Cursor clears %s" % cup.name)
		var held_transform := kettle.global_transform
		var before := cup.volume_ml
		await pour_key(true)
		await create_timer(.05).timeout
		check(cup.volume_ml > before, "Real Space key pours into %s" % cup.name)
		check(kettle.global_transform.is_equal_approx(held_transform), "Pour does not snap kettle at %s" % cup.name)
		await pour_key(false)
		var stopped := cup.volume_ml
		await create_timer(.03).timeout
		check(not kettle.is_pouring and cup.volume_ml == stopped, "Space release stops at %s" % cup.name)
		check(kettle.global_transform.is_equal_approx(held_transform), "Space release preserves grip at %s" % cup.name)
	await pour_key(true)
	await move_pointer(Vector2(950, 600))
	var remaining := kettle.volume_ml
	await create_timer(.05).timeout
	check(not kettle.is_pouring and kettle.volume_ml == remaining, "Moving spout away stops transfer while Space stays held")
	await pour_key(false)
	await mouse(Vector2(950, 600), false)
	check(not controller.is_dragging() and not kettle.is_held, "Viewport mouse release returns kettle")
	check(kettle.global_transform.is_equal_approx(original_transform), "Viewport mouse release restores exact kettle transform")
	await mouse(kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin, true)
	var burner_pointer := stove.burners[1].get_global_transform_with_canvas().origin
	await mouse(burner_pointer, false)
	check(kettle.current_burner == stove.burners[1], "Pointer-based right burner seating remains available")
	preview.queue_free()
	await process_frame
	print("BREWING_INPUT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
