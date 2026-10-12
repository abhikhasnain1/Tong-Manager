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

func begin_batch(kettle: Kettle) -> void:
	kettle.discard_contents()
	kettle.update_held_pour(false)
	kettle.temperature = kettle.config.ambient_temperature
	kettle.add_water(500)
	kettle.apply_heat(10, 1)
	check(kettle.add_tea_leaves(), "Boiling water starts a tea batch")

func ready_batch(kettle: Kettle) -> void:
	begin_batch(kettle)
	kettle.advance_brewing(kettle.config.steep_seconds)

func hold_over_cup(kettle: Kettle, cup: Cup, controller: InteractionController) -> void:
	if not controller.is_dragging():
		kettle.begin_drag(kettle.grip_anchor.get_global_transform_with_canvas().origin)
	var target := (cup.get_node("PourTarget") as Node2D).get_global_transform_with_canvas().origin
	var pointer := kettle.grip_anchor.get_global_transform_with_canvas().origin + target - kettle.get_pour_probe_viewport()
	controller.update_drag(pointer)
	kettle.update_held_pour(true)
	check(kettle.is_pouring, "Held kettle finds an active owned cup target")

func run() -> void:
	var screen := load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate() as Node2D
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
	for child in tray.cups.get_children():
		child.set_process(false)

	begin_batch(kettle)
	stove.burners[0].set_heat(3)
	stove.burners[0]._process(1)
	check(kettle.steep_progress == 0, "Burner input does not advance the brewing clock")
	kettle._process(1)
	check(kettle.steep_progress == 1, "Kettle advances brewing once while seated on heat")
	stove.burners[0].set_heat(0)
	kettle._process(1)
	check(kettle.steep_progress == 2 and kettle.temperature < 100, "Off burner allows steeping while liquid cools")
	kettle.begin_drag(kettle.grip_anchor.get_global_transform_with_canvas().origin)
	var before_heat := kettle.temperature
	stove.burners[0].set_heat(3)
	stove.burners[0]._process(1)
	check(kettle.temperature == before_heat, "Held kettle gets no applied burner heat")
	kettle._process(1)
	check(kettle.state == Kettle.BrewState.LIQUOR_READY and kettle.steep_progress == 3, "Held kettle continues steeping to ready")
	controller.cancel_drag()
	stove.burners[0].release(kettle)
	kettle._process(kettle.config.oversteep_seconds - .5)
	check(kettle.state == Kettle.BrewState.LIQUOR_READY, "Unseated ready tea stays ready before oversteep boundary")
	kettle._process(.5)
	check(kettle.state == Kettle.BrewState.OVERSTEEPED and kettle.ready_heat_seconds == kettle.config.oversteep_seconds, "Unseated ready tea reaches configured oversteep duration")
	check(not kettle.can_pour_into(cup), "Oversteeped eligibility remains unchanged")
	stove.burners[0].seat(kettle)
	stove.burners[0].set_heat(0)
	ready_batch(kettle)
	var until_cold := (kettle.temperature - kettle.config.cold_temperature) / kettle.config.cooling_rate
	kettle._process(until_cold)
	check(kettle.state == Kettle.BrewState.LIQUOR_READY and is_equal_approx(kettle.temperature, kettle.config.cold_temperature), "Default timing permits naturally cooled ready tea before oversteeping")
	check(kettle.can_pour_into(cup), "Naturally cold ready kettle remains pourable")

	begin_batch(kettle)
	var total_brew_time := kettle.config.steep_seconds + kettle.config.oversteep_seconds
	kettle.advance_brewing(total_brew_time)
	var single_state := kettle.state
	var single_steep := kettle.steep_progress
	var single_ready := kettle.ready_heat_seconds
	begin_batch(kettle)
	for step in 1000:
		kettle.advance_brewing(total_brew_time / 1000.0)
	check(kettle.state == single_state and is_equal_approx(kettle.steep_progress, single_steep) and is_equal_approx(kettle.ready_heat_seconds, single_ready), "Equivalent elapsed time has consistent phase/timers across frame steps")
	begin_batch(kettle)
	kettle.temperature = 20
	kettle.advance_brewing(3)
	check(kettle.state == Kettle.BrewState.LIQUOR_READY and kettle.ready_heat_seconds == 0, "Exact ready boundary adds no extra ready elapsed time")
	kettle.advance_brewing(NAN)
	kettle.advance_brewing(INF)
	kettle.advance_brewing(-1)
	check(kettle.ready_heat_seconds == 0, "Invalid elapsed values do not mutate brewing")

	cup.reset_clean()
	check(kettle.start_pour(cup), "Cold ready tea remains pourable")
	kettle.update_pour(.5)
	check(cup.volume_ml == 75 and cup.temperature == 20 and cup.is_cold(), "Cold liquid temperature transfers with accepted volume")
	check(kettle.volume_ml == 425, "Thermal transfer preserves source volume accounting")
	kettle.stop_pour()
	ready_batch(kettle)
	cup.reset_clean()
	kettle.advance_brewing(kettle.config.oversteep_seconds - .1)
	check(kettle.start_pour(cup), "Ready tea can start pouring immediately before oversteep boundary")
	kettle._process(.5)
	check(is_equal_approx(cup.volume_ml, kettle.config.pour_rate_ml * .1) and kettle.state == Kettle.BrewState.OVERSTEEPED and not kettle.is_pouring, "A long final frame transfers only the remaining eligible pour interval")
	cup.reset_clean()
	check(cup.receive_liquid(&"black_tea", 100, 80) == 100, "Warm liquid can enter cup")
	cup.receive_liquid(&"black_tea", 100, 20)
	check(cup.volume_ml == 200 and cup.temperature == 50, "Equal warm/cold volumes mix by volume")
	check(cup.receive_liquid(&"black_tea", 500, 100) == 50, "Top-up accepts only remaining capacity")
	check(cup.temperature == 60 and cup.volume_ml == 250, "Temperature weights accepted top-up rather than offered overflow")
	check(cup.receive_liquid(&"black_tea", 1, NAN) == 0, "Invalid temperature is rejected")
	cup.advance_cooling(5)
	check(cup.temperature == 50 and cup.volume_ml == 250, "Cup cooling leaves volume unchanged")
	cup.advance_cooling(2.5)
	check(cup.temperature == 45 and cup.is_cold(), "Configured threshold classifies cold inclusively")
	var original_config := cup.config
	cup.config = original_config.duplicate() as BrewingConfig
	cup.config.cold_temperature = 40
	check(not cup.is_cold(), "Cold threshold is resource configurable")
	cup.config = original_config
	cup.advance_cooling(1000)
	check(cup.temperature == cup.config.ambient_temperature, "Cup cooling approaches ambient without overshoot")
	cup.reset_clean()
	cup.receive_liquid(&"black_tea", 100, 80)
	cup.advance_cooling(20)
	var single_temperature := cup.temperature
	cup.reset_clean()
	cup.receive_liquid(&"black_tea", 100, 80)
	for step in 200:
		cup.advance_cooling(.1)
	check(is_equal_approx(cup.temperature, single_temperature), "Cup cooling agrees across equivalent frame steps")
	var stable_temperature := cup.temperature
	cup.advance_cooling(NAN)
	cup.advance_cooling(-1)
	check(cup.temperature == stable_temperature, "Invalid cup cooling leaves temperature unchanged")
	check(cup.get_node("VolumeMarker").text.contains("°C"), "Cup marker exposes temperature without blocking use")
	var holder := Node2D.new()
	screen.add_child(holder)
	var cup_transform := cup.transform
	cup.reparent(holder, true)
	check(cup.temperature == stable_temperature and cup.volume_ml == 100, "Reparenting keeps liquid thermal state and volume")
	cup.reparent(tray.cups, false)
	cup.transform = cup_transform
	check(cup.receive_liquid(&"black_tea", 1) == 1, "Two-argument liquid callers remain compatible")

	ready_batch(kettle)
	cup.reset_clean()
	hold_over_cup(kettle, cup, controller)
	tray.cups.remove_child(cup)
	kettle.update_pour(.5)
	check(not kettle.is_pouring and cup.volume_ml == 0 and kettle.volume_ml == 500, "Detached live cup immediately stops transfer")
	tray.cups.add_child(cup)
	controller.cancel_drag()
	hold_over_cup(kettle, cup, controller)
	var zone := cup.get_node("PourTarget") as Node2D
	cup.remove_child(zone)
	kettle.update_pour(.5)
	check(not kettle.is_pouring and cup.volume_ml == 0, "Detached live zone immediately stops transfer")
	holder.add_child(zone)
	kettle.update_held_pour(true)
	check(not kettle.is_pouring, "Zone outside its target cup cannot reactivate pouring")
	zone.reparent(cup, false)
	controller.cancel_drag()
	hold_over_cup(kettle, cup, controller)
	cup.reparent(holder, true)
	kettle.update_pour(.1)
	check(kettle.is_pouring and cup.volume_ml == 15, "Completed synchronous reparent does not invalidate owned target")
	cup.reparent(tray.cups, false)
	cup.transform = cup_transform
	var source_before_discard := kettle.volume_ml
	check(cup.discard_contents() == 15, "Discard returns the actual cup liquid amount")
	check(not kettle.is_pouring and cup.volume_ml == 0, "Cup discard stops incoming liquid before clearing")
	kettle.update_held_pour(true)
	kettle.update_pour(.5)
	check(cup.volume_ml == 0 and kettle.volume_ml == source_before_discard, "Held Space cannot immediately refill a discarded cup")
	kettle.update_held_pour(false)
	hold_over_cup(kettle, cup, controller)
	kettle.update_pour(.1)
	check(cup.volume_ml == 15, "A fresh pour gesture can reuse eligible discarded cup")
	var discarded_heat := kettle.temperature
	var original_burner := kettle.current_burner
	var kettle_discarded := kettle.volume_ml
	check(kettle.discard_contents() == kettle_discarded, "Kettle discard returns remaining liquid")
	check(not kettle.is_pouring and kettle.state == Kettle.BrewState.EMPTY and kettle.volume_ml == 0 and not kettle.contains_tea, "Kettle discard stops outgoing flow and clears contents")
	check(kettle.temperature == discarded_heat and kettle.current_burner == original_burner, "Kettle discard retains temperature and burner ownership")
	check(kettle.steep_progress == 0 and kettle.ready_heat_seconds == 0, "Kettle discard clears obsolete brew timers")
	controller.cancel_drag()
	check(kettle.discard_contents() == 0, "Repeated empty kettle discard is harmless")
	check(kettle.add_water(100) == 100, "Discarded kettle accepts a new fill")
	var kettle_id := kettle.get_instance_id()
	var kettle_parent := kettle.get_parent()
	for phase in Kettle.BrewState.values():
		kettle.discard_contents()
		kettle.temperature = kettle.config.ambient_temperature
		if phase != Kettle.BrewState.EMPTY:
			kettle.add_water(100)
		if phase >= Kettle.BrewState.HEATING:
			kettle.apply_heat(1, .5)
		if phase >= Kettle.BrewState.BOILING:
			kettle.apply_heat(100, 1)
		if phase >= Kettle.BrewState.STEEPING:
			kettle.add_tea_leaves()
		if phase >= Kettle.BrewState.LIQUOR_READY:
			kettle.advance_brewing(kettle.config.steep_seconds)
		if phase == Kettle.BrewState.OVERSTEEPED:
			kettle.advance_brewing(kettle.config.oversteep_seconds)
		check(kettle.state == phase, "Discard fixture reaches brew phase %d" % phase)
		var phase_volume := kettle.volume_ml
		var phase_heat := kettle.temperature
		check(kettle.discard_contents() == phase_volume and kettle.state == Kettle.BrewState.EMPTY and kettle.temperature == phase_heat, "Discard clears brew phase %d and retains heat" % phase)
		check(kettle.get_instance_id() == kettle_id and kettle.get_parent() == kettle_parent and kettle.current_burner == original_burner, "Discard phase %d keeps vessel identity and burner ownership" % phase)

	cup.add_relish(&"sugar")
	cup.assigned_order_id = &"history_test"
	var cup_id := cup.get_instance_id()
	var cup_parent := cup.get_parent()
	check(cup.discard_contents() == 15, "Ordinary partial cup contents can be discarded")
	check(cup.state == Cup.CupState.IN_USE and cup.can_receive_liquid(&"black_tea"), "Discarded unserved cup becomes usable empty without washing")
	check(cup.get_instance_id() == cup_id and cup.get_parent() == cup_parent, "Discard keeps cup identity and owner")
	check(cup.assigned_order_id == &"history_test" and cup.relish_item_ids.is_empty() and cup.contents_base_id.is_empty(), "Discard clears ingredients but preserves order history")
	cup.receive_liquid(&"black_tea", 20, 70)
	cup.mark_served()
	check(cup.discard_contents() == 20 and cup.state == Cup.CupState.SERVED, "Served cup disposal preserves served lifecycle")
	check(not cup.can_receive_liquid(&"black_tea") and not cup.contents_overlay.visible, "Empty served cup is not washed or shown full")
	cup.reset_clean()
	cup.receive_liquid(&"black_tea", 20, 70)
	cup.assigned_order_id = &"history_test"
	cup.mark_served()
	cup.mark_dirty()
	check(cup.discard_contents() == 20 and cup.state == Cup.CupState.DIRTY, "Discarded dirty contents leave the cup dirty")
	check(cup.discard_contents() == 0 and cup.state == Cup.CupState.DIRTY, "Repeated empty dirty discard remains harmless")
	check(cup.assigned_order_id == &"history_test" and cup.cup_sprite.texture == cup.dirty_texture, "Dirty disposal preserves order history and dirty artwork")
	cup.reset_clean()
	check(cup.discard_contents() == 0 and cup.state == Cup.CupState.CLEAN and not cup.is_cold(), "Empty clean discard is a safe no-op")
	screen.queue_free()
	await process_frame
	print("BREWING_THERMAL: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
