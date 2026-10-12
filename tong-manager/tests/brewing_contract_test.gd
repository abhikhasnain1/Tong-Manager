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

func ready_tea(kettle: Kettle, amount: float = 500.0) -> void:
	kettle.volume_ml = 0
	kettle.contains_tea = false
	kettle.state = Kettle.BrewState.EMPTY
	kettle.ready_heat_seconds = 0
	kettle.temperature = kettle.config.ambient_temperature
	kettle.add_water(amount)
	kettle.apply_heat(10.0, 1.0)
	check(kettle.add_tea_leaves(), "Tea should enter boiling water")
	kettle.apply_heat(kettle.config.steep_seconds, 1.0)
	check(kettle.state == Kettle.BrewState.LIQUOR_READY, "Steeping reaches ready")

func aim_spout(kettle: Kettle, controller: InteractionController, target: Vector2) -> Vector2:
	var grip := kettle.get_node("GripAnchor") as Node2D
	var pointer := grip.get_global_transform_with_canvas().origin + target - kettle.get_pour_probe_viewport()
	controller.update_drag(pointer)
	return pointer

func run() -> void:
	var packed := load("res://scenes/gameplay/tong/TongDayScreen.tscn") as PackedScene
	check(packed != null, "Tong scene loads")
	if packed == null:
		quit(1)
		return
	var screen := packed.instantiate()
	root.add_child(screen)
	await process_frame
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var stove := screen.get_node("WorldRoot/ToolLayer/StoveStation") as Stove
	var controller := screen.get_node("InteractionController") as InteractionController
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	var cup := tray.cups.get_child(0) as Cup
	kettle.set_process(false)
	for burner in stove.burners:
		burner.set_process(false)
	check(kettle.state == Kettle.BrewState.EMPTY, "Production kettle starts empty")
	check(not kettle.add_tea_leaves(), "Empty kettle rejects tea")
	check(kettle.add_water(-1) == 0 and kettle.add_water(NAN) == 0, "Invalid volume rejected")
	check(kettle.add_water(2000) == 1500, "Fill capped by ToolDef")
	check(kettle.add_water(20) == 0, "Full kettle rejects water")
	check(not kettle.add_tea_leaves(), "Cold water rejects tea")
	var cold := kettle.temperature
	kettle.apply_heat(1, 0)
	check(kettle.temperature == cold, "Off adds no heat")
	kettle.apply_heat(1, .5)
	var low_gain := kettle.temperature - cold
	kettle.temperature = cold
	kettle.apply_heat(1, 1.75)
	check(kettle.temperature - cold > low_gain, "High heats faster than Low")
	ready_tea(kettle)
	check(kettle.add_water(10) == 0, "Cannot dilute a brewed batch through refill")
	check(not kettle.add_tea_leaves(), "Cannot add tea twice")
	cup.reset_clean()
	check(cup.capacity_ml == float(tray.tool_def.cup_volume_ml), "Cup capacity follows data")
	var original_position := kettle.global_position
	var original_transform := kettle.global_transform
	check(kettle.start_pour(cup), "Ready tea accepts clean cup")
	check(controller.has_active_action(), "Non-drag pour holds action lock")
	check(not controller.start_drag(HeldItemPayload.new(), cup, Vector2.ZERO), "Pour locks other drags")
	var before := kettle.volume_ml + cup.volume_ml
	kettle.update_pour(.5)
	check(is_equal_approx(cup.volume_ml, 75.0), "Pour transfers gradually")
	check(is_equal_approx(kettle.volume_ml + cup.volume_ml, before), "Volume is conserved")
	kettle.update_pour(100)
	check(cup.volume_ml == cup.capacity_ml and not kettle.is_pouring, "Large delta stops at full cup")
	check(is_equal_approx(kettle.volume_ml, 250.0), "No liquid lost on overflow")
	check(not kettle.start_pour(cup), "Full cup rejects pour")
	check(kettle.global_position.is_equal_approx(original_position), "Pour returns origin")
	check(not controller.has_active_action(), "Pour unlocks actions")
	cup.mark_served(); cup.mark_dirty()
	check(not kettle.start_pour(cup), "Dirty cup rejects pour")
	cup.reset_clean(); cup.receive_liquid(&"water", 10)
	check(not kettle.start_pour(cup), "Incompatible liquid rejects mixing")
	cup.reset_clean()
	ready_tea(kettle, 50)
	kettle.start_pour(cup); kettle.update_pour(10)
	check(cup.volume_ml == 50 and kettle.volume_ml == 0, "Insufficient kettle volume conserved")
	check(kettle.state == Kettle.BrewState.EMPTY and not kettle.contains_tea, "Empty batch resets")
	ready_tea(kettle)
	kettle.apply_heat(kettle.config.oversteep_seconds, 1)
	check(kettle.state == Kettle.BrewState.OVERSTEEPED, "Continued heat oversteeps")
	check(not kettle.start_pour(cup), "Oversteeped batch rejects serving")
	ready_tea(kettle)
	cup.reset_clean()
	var pointer := kettle.get_global_transform_with_canvas().origin
	var cup_target := (cup.get_node("PourTarget") as Node2D).get_global_transform_with_canvas().origin
	check(kettle.begin_drag(pointer), "Controller begins kettle drag")
	var grip := kettle.get_node("GripAnchor") as Node2D
	check(grip.get_global_transform_with_canvas().origin.is_equal_approx(pointer), "Pickup places grip under pointer")
	controller.update_drag(cup_target)
	check(controller.hovered_drop_zone != cup.get_node("PourTarget"), "Pointer over cup does not select it when spout misses")
	kettle.update_held_pour(true)
	check(not kettle.is_pouring, "Pointer alone cannot pour into a cup")
	var cup_pointer := aim_spout(kettle, controller, cup_target)
	check(controller.hovered_drop_zone == cup.get_node("PourTarget"), "Spout landing probe selects cup target")
	check(grip.get_global_transform_with_canvas().origin.is_equal_approx(cup_pointer), "Aiming keeps grip under pointer")
	check(cup_pointer.distance_to(cup_target) > 64.0, "Hand cursor stays clear of the cup target")
	check(kettle.spout.get_global_transform_with_canvas().origin.distance_to(cup_pointer) > 64.0, "Hand cursor stays clear of the spout")
	var offset_pointer := cup_pointer + Vector2(6, 0)
	controller.update_drag(offset_pointer)
	var held_transform := kettle.global_transform
	check(controller.hovered_drop_zone == cup.get_node("PourTarget"), "Slightly off-center spout remains a valid aim")
	check(kettle.get_pour_probe_viewport().is_equal_approx(cup_target + Vector2(6, 0)), "Aim does not snap kettle to cup center")
	kettle.update_held_pour(false)
	check(not kettle.is_pouring, "Hover alone never pours")
	kettle.update_held_pour(true)
	check(kettle.is_pouring and kettle.is_held, "Held pour input starts flow during drag")
	check(kettle.global_transform.is_equal_approx(held_transform), "Pour press does not shift held pose")
	kettle.update_pour(.2)
	var partial := cup.volume_ml
	kettle.update_held_pour(false)
	kettle.update_pour(.5)
	check(not kettle.is_pouring and cup.volume_ml == partial, "Release pour input stops immediately")
	check(kettle.global_transform.is_equal_approx(held_transform), "Pour release keeps grip and held pose stable")
	kettle.update_held_pour(true)
	check(kettle.is_pouring, "Holding again resumes")
	controller.update_drag(Vector2(950, 600))
	kettle.update_held_pour(true)
	check(not kettle.is_pouring, "Moving away stops flow even while pour is held")
	controller.update_drag(cup_pointer)
	kettle.update_held_pour(true)
	controller.release_drop(cup_pointer)
	check(not kettle.is_pouring and not kettle.is_held and not controller.is_dragging(), "Mouse release stops flow and ends drag")
	check(kettle.global_position.is_equal_approx(original_position), "Mouse release restores kettle origin")
	check(kettle.global_transform.is_equal_approx(original_transform), "Mouse release restores exact original transform")
	kettle.begin_drag(pointer); controller.update_drag(cup_pointer); kettle.update_held_pour(true)
	controller.cancel_drag()
	check(not kettle.is_pouring and not kettle.is_held, "Cancel clears pour and held state")
	check(kettle.global_position.is_equal_approx(original_position), "Cancel restores original placement")
	check(kettle.global_transform.is_equal_approx(original_transform), "Active pour cancel restores exact transform")
	kettle.begin_drag(pointer); controller.update_drag(cup_pointer); kettle.update_held_pour(true)
	controller.release_drop(Vector2(950, 600))
	check(not kettle.is_pouring and not kettle.is_held and kettle.global_transform.is_equal_approx(original_transform), "Invalid release restores exact transform after active pour")
	kettle.begin_drag(pointer); controller.update_drag(cup_pointer); kettle.update_held_pour(true)
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(not kettle.is_pouring and not controller.is_dragging(), "Mode switch cancels action")
	check(kettle.global_transform.is_equal_approx(original_transform), "Mode switch restores exact original transform")
	check(not (stove.get_node("DialA") as StoveDial).cycle_heat(), "Arrange mode does not operate dials")
	controller.set_mode(InteractionController.MODE_INTERACT)
	var world := screen.get_node("WorldRoot") as Node2D
	var world_transform := world.transform
	world.scale = Vector2(.72, .83)
	world.position += Vector2(31, 17)
	var scaled_target := (cup.get_node("PourTarget") as Node2D).get_global_transform_with_canvas().origin
	kettle.begin_drag(kettle.get_global_transform_with_canvas().origin)
	var scaled_pointer := aim_spout(kettle, controller, scaled_target)
	check(controller.hovered_drop_zone == cup.get_node("PourTarget"), "Spout selection works under scaled and translated parent")
	check(grip.get_global_transform_with_canvas().origin.is_equal_approx(scaled_pointer), "Scaled parent preserves pointer grip")
	check(kettle.get_pour_probe_viewport().is_equal_approx(scaled_target), "Scaled parent preserves landing probe alignment")
	controller.cancel_drag()
	world.transform = world_transform
	check((stove.get_node("DialA") as StoveDial).cycle_heat(), "Use mode operates dial")
	check(stove.burners[0].heat_level == 1 and stove.burners[1].heat_level == 0, "Burners independent")
	kettle.begin_drag(pointer)
	check(not (stove.get_node("DialB") as StoveDial).cycle_heat(), "Dial cannot operate during drag")
	var temp := kettle.temperature
	stove.burners[0]._process(1)
	check(kettle.temperature == temp, "Held kettle receives no burner heat")
	var burner_pointer := stove.burners[1].get_global_transform_with_canvas().origin
	controller.release_drop(burner_pointer)
	check(kettle.current_burner == stove.burners[1], "Drop transfers kettle to right burner")
	check(stove.burners[0].seated_kettle == null and stove.burners[1].seated_kettle == kettle, "Seat ownership unique")
	var spare := (load("res://scenes/gameplay/tools/Kettle.tscn") as PackedScene).instantiate() as Kettle
	screen.add_child(spare);spare.set_process(false)
	check(not stove.burners[1].can_seat(spare), "Occupied burner rejects other kettle")
	spare.queue_free()
	var transient := (load("res://scenes/gameplay/tools/Cup.tscn") as PackedScene).instantiate() as Cup
	screen.add_child(transient)
	kettle.start_pour(transient)
	transient.free()
	kettle.update_pour(.5)
	check(not kettle.is_pouring and not controller.has_active_action(), "Freed target cancels safely")
	var transient_zone := BrewingDropZone.new()
	transient_zone.target = cup
	transient_zone.controller = controller
	transient_zone.is_cup_target = true
	cup.add_child(transient_zone)
	kettle.begin_drag(kettle.get_global_transform_with_canvas().origin)
	controller.hovered_drop_zone = transient_zone
	kettle.update_held_pour(true)
	transient_zone.free()
	kettle.update_held_pour(true)
	check(not kettle.is_pouring, "Removed drop zone stops held flow")
	controller.cancel_drag()
	check(not controller.is_dragging(), "Cancellation after zone removal is safe")
	var free_burner := stove.burners[0]
	var deleted_kettle := (load("res://scenes/gameplay/tools/Kettle.tscn") as PackedScene).instantiate() as Kettle
	screen.add_child(deleted_kettle)
	free_burner.seat(deleted_kettle)
	deleted_kettle.free()
	free_burner._process(.1)
	check(free_burner.seated_kettle == null, "Deleted kettle clears burner ownership")
	cup.reset_clean()
	check(cup.volume_ml == 0 and cup.liquid_type.is_empty(), "Wash resets volume/type")
	screen.queue_free()
	await process_frame
	print("BREWING: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
