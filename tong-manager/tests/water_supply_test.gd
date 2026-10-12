extends SceneTree

var failures: Array[String] = []
var checks := 0
var reentrant_attempts: Array[float] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func empty_kettle(kettle: Kettle) -> void:
	kettle.volume_ml = 0.0
	kettle.contains_tea = false
	kettle.state = Kettle.BrewState.EMPTY
	kettle.is_pouring = false
	kettle.is_held = false


func run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var source := Node2D.new()
	fixture.add_child(source)
	var kettle := (load("res://scenes/gameplay/tools/Kettle.tscn") as PackedScene).instantiate() as Kettle
	fixture.add_child(kettle)
	kettle.set_process(false)
	var supply := DailyWaterSupply.new()
	check(supply.begin_day(1, 3000.0), "First day grants configured water")
	var token := supply.reserve_transfer(source)
	check(token > 0 and supply.remaining_ml == 3000.0, "Starting a drag reserves permission without debiting")
	check(supply.fill_kettle(token, kettle) == 1500.0, "Fill is bounded by kettle capacity")
	check(kettle.volume_ml + supply.remaining_ml == 3000.0, "Fill conserves source plus vessel volume")
	check(supply.fill_kettle(token, kettle) == 0.0, "A successful command is consumed once")
	check(not supply.begin_day(1, 3000.0) and supply.remaining_ml == 1500.0, "Reentering the same day cannot refill supply")
	token = supply.reserve_transfer(source)
	check(not supply.can_fill(token, kettle), "Full kettle rejects refill")
	check(supply.fill_kettle(token, kettle) == 0.0 and supply.remaining_ml == 1500.0, "Invalid fill does not debit")
	supply.cancel_transfer(token)
	empty_kettle(kettle)
	kettle.add_water(1400.0)
	token = supply.reserve_transfer(source)
	check(supply.fill_kettle(token, kettle) == 100.0 and supply.remaining_ml == 1400.0, "Partial top-up only spends accepted headroom")
	empty_kettle(kettle)
	token = supply.reserve_transfer(source)
	check(supply.fill_kettle(token, kettle) == 1400.0, "Last fill uses remaining supply even below capacity")
	check(supply.remaining_ml == 0.0 and supply.reserve_transfer(source) == 0, "Empty drum cannot create more water")
	check(supply.begin_day(2, 230.0), "Explicit later day accepts a configurable allocation")
	check(not supply.begin_day(1, 3000.0) and supply.remaining_ml == 230.0, "Stale earlier-day commands do not refill")
	empty_kettle(kettle)
	token = supply.reserve_transfer(source)
	supply.cancel_transfer(token)
	check(supply.fill_kettle(token, kettle) == 0.0 and supply.remaining_ml == 230.0, "Canceled drag token cannot transfer")
	token = supply.reserve_transfer(source)
	check(supply.begin_day(3, 600.0), "New day invalidates old drag reservations")
	check(supply.fill_kettle(token, kettle) == 0.0 and supply.remaining_ml == 600.0, "Previous-day token cannot spend current water")
	token = supply.reserve_transfer(source)
	kettle.contains_tea = true
	kettle.volume_ml = 100.0
	check(supply.fill_kettle(token, kettle) == 0.0 and supply.remaining_ml == 600.0, "Tea never dilutes through the water source")
	empty_kettle(kettle)
	kettle.is_pouring = true
	check(not supply.can_fill(token, kettle), "Active pour rejects water")
	kettle.is_pouring = false
	kettle.is_held = true
	check(not supply.can_fill(token, kettle), "Held kettle rejects a concurrent fill")
	kettle.is_held = false
	fixture.remove_child(kettle)
	check(supply.fill_kettle(token, kettle) == 0.0, "Detached kettle cannot receive water")
	fixture.add_child(kettle)
	fixture.remove_child(source)
	check(supply.fill_kettle(token, kettle) == 0.0, "Detached source cannot transfer")
	fixture.add_child(source)
	source.queue_free()
	check(supply.fill_kettle(token, kettle) == 0.0, "Queued source deletion cannot transfer")
	await process_frame
	check(supply.fill_kettle(token, kettle) == 0.0, "Freed source invalidates its weak reservation")
	var next_source := Node2D.new()
	fixture.add_child(next_source)
	var reentrant_token := supply.reserve_transfer(next_source)
	var extra_token := supply.reserve_transfer(next_source)
	var callback := func():
		reentrant_attempts.append(supply.fill_kettle(reentrant_token, kettle))
		reentrant_attempts.append(supply.fill_kettle(extra_token, kettle))
		reentrant_attempts.append(1.0 if supply.begin_day(4, 3000.0) else 0.0)
	kettle.contents_changed.connect(callback)
	check(supply.fill_kettle(reentrant_token, kettle) == 600.0, "Claimed transaction transfers expected amount")
	kettle.contents_changed.disconnect(callback)
	check(reentrant_attempts == [0.0, 0.0, 0.0], "Reentrant callbacks cannot repeat or refill a transfer")
	check(supply.remaining_ml == 0.0 and kettle.volume_ml == 600.0, "Reentrant attempt preserves conservation")
	check(not supply.begin_day(4, NAN) and not supply.begin_day(4, -5.0), "Nonfinite or negative day allocations are rejected")

	# Exercise the actual shared controller and drum instead of only the supply model.
	var game_state := root.get_node("GameState")
	game_state.start_water_day(100, 1700.0)
	var drag_layer := Node2D.new()
	drag_layer.name = "DragLayer"
	fixture.add_child(drag_layer)
	var zones := Node2D.new()
	zones.name = "Zones"
	fixture.add_child(zones)
	var controller := InteractionController.new()
	controller.drag_layer_path = NodePath("../DragLayer")
	controller.drop_zone_root_path = NodePath("../Zones")
	fixture.add_child(controller)
	var drum_scene := load("res://scenes/gameplay/tools/WaterDrum.tscn") as PackedScene
	var drum := drum_scene.instantiate() as WaterDrum
	drum.position = Vector2(70.0, 170.0)
	fixture.add_child(drum)
	drum.bind_controller(controller)
	var drum_origin := drum.transform
	kettle.position = Vector2(420.0, 280.0)
	var zone := WaterFillDropZone.new()
	zone.target = kettle
	zone.controller = controller
	kettle.add_child(zone)
	controller.register_drop_zone(zone)
	empty_kettle(kettle)
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Actual drum drag starts in interaction mode")
	var completed_payload := controller.current_payload
	check(drum.get_parent() == drag_layer, "Shared controller carries the drum icon")
	controller.release_drop(zone.get_global_transform_with_canvas().origin)
	check(kettle.volume_ml == 1500.0 and game_state.water_supply.remaining_ml == 200.0, "Real drop transfers from daily balance once")
	check(drum.get_parent() == fixture and drum.transform.is_equal_approx(drum_origin), "Successful drop returns icon to exact origin")
	check(not controller.is_dragging(), "Successful drop clears controller state")
	empty_kettle(kettle)
	zone.apply_drop(completed_payload)
	check(kettle.volume_ml == 0.0 and game_state.water_supply.remaining_ml == 200.0, "Repeated stale drop cannot refill kettle")
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Remaining water supports a later drag")
	var canceled_payload := controller.current_payload
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(not controller.is_dragging() and drum.transform.is_equal_approx(drum_origin), "Changing mode cancels and restores the source")
	check(not drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Organization mode cannot take water")
	controller.set_mode(InteractionController.MODE_INTERACT)
	zone.apply_drop(canceled_payload)
	check(kettle.volume_ml == 0.0 and game_state.water_supply.remaining_ml == 200.0, "Canceled payload cannot later debit")
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Invalid-drop test starts a real drag")
	controller.release_drop(Vector2(-5000.0, -5000.0))
	check(game_state.water_supply.remaining_ml == 200.0 and drum.transform.is_equal_approx(drum_origin), "Invalid release cancels without loss")
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Detached-zone test starts a real drag")
	kettle.remove_child(zone)
	zones.add_child(zone)
	controller.release_drop(zone.get_global_transform_with_canvas().origin)
	check(game_state.water_supply.remaining_ml == 200.0 and kettle.volume_ml == 0.0, "Live zone detached from kettle cannot fill it")
	check(drum.transform.is_equal_approx(drum_origin), "Detached target restores drum")
	zones.remove_child(zone)
	kettle.add_child(zone)
	drum.queue_free()
	await process_frame
	drum = drum_scene.instantiate() as WaterDrum
	fixture.add_child(drum)
	drum.bind_controller(controller)
	check(game_state.water_supply.remaining_ml == 200.0 and drum.remaining_label.text.contains("200 ml"), "Recreated source reads existing day balance without refill")
	game_state.ensure_water_day()
	check(game_state.water_supply.remaining_ml == 200.0, "Ensure-day is idempotent after scene reload")
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Last partial fill starts")
	controller.release_drop(zone.get_global_transform_with_canvas().origin)
	check(kettle.volume_ml == 200.0 and game_state.water_supply.remaining_ml == 0.0, "Real drop accepts final partial fill")
	check(not drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Empty icon cannot start drag")
	check(drum.remaining_label.text.contains("0 ml"), "Counter displays depleted balance")
	check(game_state.start_water_day(101), "Explicit new sample day can reset to configured default")
	check(game_state.water_supply.remaining_ml == 3000.0 and drum.remaining_label.text.contains("3000 ml"), "New sample day updates all source views")
	check(drum.begin_drag(drum.get_global_transform_with_canvas().origin), "Deleted-kettle regression starts a real drag")
	var deleted_target_position := zone.get_global_transform_with_canvas().origin
	kettle.queue_free()
	check(not zone.accepts(controller.current_payload).is_valid, "Queued kettle deletion rejects a fill immediately")
	await process_frame
	controller.release_drop(deleted_target_position)
	check(game_state.water_supply.remaining_ml == 3000.0 and not controller.is_dragging(), "Deleted kettle cancels drop without debit")
	check(drum.get_parent() == fixture, "Deleted target returns source to its original parent")
	fixture.queue_free()
	await process_frame

	# The production Tong screen wires the same source and real kettle target.
	var tong_scene := load("res://scenes/gameplay/tong/TongDayScreen.tscn") as PackedScene
	var screen := tong_scene.instantiate()
	root.add_child(screen)
	await process_frame
	var scene_kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var scene_drum := screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	var scene_controller := screen.get_node("InteractionController") as InteractionController
	var scene_fill := scene_kettle.get_node("WaterFillTarget") as WaterFillDropZone
	scene_kettle.set_process(false)
	check(scene_kettle.volume_ml == 0.0, "Normal Tong kettle starts empty")
	check(scene_drum.begin_drag(scene_drum.get_global_transform_with_canvas().origin), "Normal Tong source uses its bound controller")
	scene_controller.release_drop(scene_fill.get_global_transform_with_canvas().origin)
	check(scene_kettle.volume_ml == 1500.0 and game_state.water_supply.remaining_ml == 1500.0, "Normal Tong release fills the real kettle and debits the daily source")
	screen.queue_free()
	await process_frame
	screen = tong_scene.instantiate()
	root.add_child(screen)
	await process_frame
	scene_drum = screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	check(game_state.water_supply.remaining_ml == 1500.0 and scene_drum.remaining_label.text.contains("1500 ml"), "Entire Tong screen reload preserves the remaining day supply")
	screen.queue_free()
	await process_frame

	# A fresh run honors the actual screen config, including an authored override.
	game_state.water_supply = DailyWaterSupply.new()
	screen = tong_scene.instantiate()
	screen.day_config = screen.day_config.duplicate()
	screen.day_config.daily_water_ml = 900.0
	root.add_child(screen)
	await process_frame
	scene_kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	scene_drum = screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	scene_controller = screen.get_node("InteractionController") as InteractionController
	scene_fill = scene_kettle.get_node("WaterFillTarget") as WaterFillDropZone
	check(game_state.water_supply.remaining_ml == 900.0 and scene_drum.remaining_label.text.contains("900 ml"), "First Tong load honors its customized DayConfig allocation")
	check(scene_drum.begin_drag(scene_drum.get_global_transform_with_canvas().origin), "Customized finite supply supports the production gesture")
	scene_controller.release_drop(scene_fill.get_global_transform_with_canvas().origin)
	check(scene_kettle.volume_ml == 900.0 and game_state.water_supply.remaining_ml == 0.0, "Customized allocation remains conserved through depletion")
	screen.queue_free()
	await process_frame
	screen = tong_scene.instantiate()
	screen.day_config = screen.day_config.duplicate()
	screen.day_config.daily_water_ml = 4000.0
	root.add_child(screen)
	await process_frame
	scene_drum = screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	check(game_state.water_supply.day_id == 1 and game_state.water_supply.remaining_ml == 0.0 and scene_drum.remaining_label.text.contains("0 ml"), "Same-day screen recreation cannot replenish even when its config differs")
	screen.queue_free()
	await process_frame
	print("Water supply checks: %d; failures: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
