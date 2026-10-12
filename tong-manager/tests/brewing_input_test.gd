extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func mouse(at: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await physics_frame
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = pressed
	root.push_input(click, true)
	await physics_frame
	await process_frame

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
	var dial: Area2D = stove.get_node("DialA")
	await mouse(dial.get_global_transform_with_canvas().origin, true)
	await mouse(dial.get_global_transform_with_canvas().origin, false)
	check(stove.burners[0].heat_level == 1, "Viewport click reaches left dial")
	check(stove.burners[1].heat_level == 0, "Viewport click leaves other dial off")
	kettle.apply_heat(10, 1)
	kettle.add_tea_leaves()
	kettle.apply_heat(3, 1)
	await mouse(kettle.get_node("InteractionAnchor").get_global_transform_with_canvas().origin, true)
	check(preview.controller.is_dragging(), "Viewport press picks up kettle")
	var cup: Cup = preview.screen.get_node("WorldRoot/ToolLayer/TrayStation/Cups").get_child(0)
	var target: Vector2 = cup.get_node("PourTarget").get_global_transform_with_canvas().origin
	var motion := InputEventMouseMotion.new()
	motion.position = target
	root.push_input(motion, true)
	Input.action_press("pour")
	await create_timer(.15).timeout
	check(cup.volume_ml > 0, "Held input transfers into pointed cup")
	Input.action_release("pour")
	await process_frame
	var stopped := cup.volume_ml
	await create_timer(.1).timeout
	check(not kettle.is_pouring and cup.volume_ml == stopped, "Input release stops runtime flow")
	await mouse(target, false)
	check(not preview.controller.is_dragging() and not kettle.is_held, "Viewport mouse release returns kettle")
	preview.queue_free()
	await process_frame
	print("BREWING_INPUT: 6 checks; %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
