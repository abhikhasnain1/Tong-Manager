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

func run() -> void:
	var screen: Node2D = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var controller: InteractionController = screen.get_node("InteractionController")
	var kettle: Kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	var tray: TrayStation = screen.get_node("WorldRoot/ToolLayer/TrayStation")
	var discard: DiscardDropZone = screen.get_node("WorldRoot/DropZoneRoot/DiscardArea")
	var cup := tray.cups.get_child(0) as Cup
	kettle.set_process(false)
	cup.set_process(false)
	var water_before: float = root.get_node("GameState").water_supply.remaining_ml
	cup.receive_liquid(&"black_tea", 175, 80)
	cup.add_relish(&"sugar")
	var original := cup.transform
	var original_parent := cup.get_parent()
	var payload := HeldItemPayload.new(&"tray", &"cup", 1, cup, {"category": &"cup"})
	discard.apply_drop(payload)
	check(cup.volume_ml == 175, "Unheld payload cannot discard contents")
	controller.start_drag(payload, cup, cup.get_global_transform_with_canvas().origin)
	controller.update_drag(discard.get_global_transform_with_canvas().origin)
	check(controller.hovered_drop_zone == discard, "Discard is selected by a deliberate vessel drag")
	controller.cancel_drag()
	check(cup.volume_ml == 175 and cup.relish_item_ids.size() == 1, "Cancel keeps liquid and ingredients")
	controller.start_drag(payload, cup, cup.get_global_transform_with_canvas().origin)
	controller.release_drop(discard.get_global_transform_with_canvas().origin)
	check(cup.volume_ml == 0 and cup.relish_item_ids.is_empty(), "Valid drop empties liquid and ingredients")
	check(cup.get_parent() == original_parent and cup.transform == original, "Discard retains exact cup ownership and placement")
	check(cup.state == Cup.CupState.IN_USE, "Emptying a used clean cup does not perform washing")
	cup.receive_liquid(&"black_tea", 50, 70)
	discard.apply_drop(payload)
	check(cup.volume_ml == 50, "Repeated payload cannot erase a later refill")
	cup.mark_served()
	cup.mark_dirty()
	cup.assigned_order_id = &"past_order"
	payload = HeldItemPayload.new(&"tray", &"cup", 1, cup, {"category": &"cup"})
	controller.start_drag(payload, cup, cup.get_global_transform_with_canvas().origin)
	controller.release_drop(discard.get_global_transform_with_canvas().origin)
	check(cup.volume_ml == 0 and cup.state == Cup.CupState.DIRTY, "Discard can empty dirty cups without washing")
	check(cup.assigned_order_id == &"past_order", "Discard preserves historical order identity")
	check(root.get_node("GameState").water_supply.remaining_ml == water_before, "No daily water refunded by discard")
	kettle.add_water(600)
	kettle.temperature = 92
	var kettle_original := kettle.transform
	var burner := kettle.current_burner
	check(kettle.begin_drag(kettle.grip_anchor.get_global_transform_with_canvas().origin), "Kettle drag begins for discard")
	controller.release_drop(discard.get_global_transform_with_canvas().origin)
	check(kettle.volume_ml == 0 and kettle.temperature == 92, "Kettle discard empties contents without a thermal reset")
	check(kettle.current_burner == burner and kettle.transform == kettle_original and not kettle.is_held, "Kettle discard restores burner and pose")
	check(kettle.add_water(200) == 200, "Discarded kettle can refill")
	check(kettle.begin_drag(kettle.grip_anchor.get_global_transform_with_canvas().origin), "Refilled kettle can be picked up")
	controller.update_drag(discard.get_global_transform_with_canvas().origin)
	var parent := discard.get_parent()
	parent.remove_child(discard)
	controller.release_drop(Vector2(2000, 2000))
	check(kettle.volume_ml == 200 and not controller.is_dragging(), "Removed discard target cancels with contents intact")
	parent.add_child(discard)
	check(kettle.begin_drag(kettle.grip_anchor.get_global_transform_with_canvas().origin), "Drag starts before focus loss")
	controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not controller.is_dragging() and not kettle.is_held and kettle.volume_ml == 200, "Window focus loss safely cancels drag")
	screen.queue_free()
	await process_frame
	print("DISCARD_INTERACTION: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
