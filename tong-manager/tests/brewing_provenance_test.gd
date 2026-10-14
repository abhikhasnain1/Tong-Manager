extends SceneTree

const KETTLE_SCENE := preload("res://scenes/gameplay/tools/Kettle.tscn")
const CUP_SCENE := preload("res://scenes/gameplay/tools/Cup.tscn")

var checks := 0
var failures: Array[String] = []
var owned: Array[Node] = []


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func kettle() -> Kettle:
	var value := KETTLE_SCENE.instantiate() as Kettle
	root.add_child(value)
	value.set_process(false)
	owned.append(value)
	return value


func cup() -> Cup:
	var value := CUP_SCENE.instantiate() as Cup
	root.add_child(value)
	value.set_process(false)
	owned.append(value)
	return value


func prepare(source: Kettle, boiling := true, amount := 500.0) -> void:
	source.discard_contents()
	source.temperature = source.config.ambient_temperature
	source.add_water(amount)
	if boiling:
		source.apply_heat(100.0, 1.0)
	check(source.apply_ingredient(&"black_tea", 1, &"infuse", &"black_tea"), "Fixture infusion uses the same generic vessel effect")


func transfer(source: Kettle, receiver: Cup, amount := 15.0) -> void:
	check(source.start_pour(receiver), "Eligible liquid starts a physical pour")
	source.update_pour(amount / source.config.pour_rate_ml)
	source.stop_pour()


func _run() -> void:
	check_liquid_states()
	check_immutable_history()
	check_unknown_history()
	check_silent_service_commit()
	check_frame_invariance()
	check_mixed_batch_history()
	check_liquid_presentation()
	await check_held_boundary()
	for node in owned:
		if is_instance_valid(node): node.queue_free()
	await process_frame
	print("BREWING_PROVENANCE: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check_liquid_states() -> void:
	var source := kettle()
	var receiver := cup()
	check(not source.can_pour_into(receiver), "Empty kettle cannot create liquid")
	for phase in [Kettle.BrewState.WATER, Kettle.BrewState.HEATING, Kettle.BrewState.BOILING, Kettle.BrewState.STEEPING, Kettle.BrewState.LIQUOR_READY, Kettle.BrewState.OVERSTEEPED]:
		source.discard_contents()
		receiver.reset_clean()
		source.temperature = source.config.ambient_temperature
		source.add_water(100.0)
		if phase >= Kettle.BrewState.HEATING: source.apply_heat(.1, 1.0)
		if phase >= Kettle.BrewState.BOILING: source.apply_heat(100.0, 1.0)
		if phase >= Kettle.BrewState.STEEPING: check(source.add_tea_leaves(), "Default policy still accepts one bag in boiling water")
		if phase >= Kettle.BrewState.LIQUOR_READY: source.advance_brewing(source.config.steep_seconds)
		if phase == Kettle.BrewState.OVERSTEEPED: source.advance_brewing(source.config.oversteep_seconds)
		check(source.state == phase, "Fixture reaches liquid phase %d" % phase)
		var expected: StringName = &"water" if phase < Kettle.BrewState.STEEPING else (&"underbrewed" if phase == Kettle.BrewState.STEEPING else (&"ready" if phase == Kettle.BrewState.LIQUOR_READY else &"oversteeped"))
		transfer(source, receiver)
		check(receiver.volume_ml == 15.0 and source.volume_ml == 85.0, "Phase %d transfer conserves actual liquid" % phase)
		check(receiver.liquid_type == (&"water" if expected == &"water" else &"black_tea"), "Phase %d preserves liquid identity" % phase)
		check(receiver.brew_batches.size() == 1 and receiver.brew_batches[0].state == expected, "Phase %d records its contribution quality" % phase)
		check(receiver.brew_history_complete, "Kettle transfer supplies complete provenance")

	prepare(source)
	receiver.reset_clean()
	receiver.receive_liquid(&"water", 1.0)
	check(not source.can_pour_into(receiver), "Permissive quality does not bypass incompatible-liquid protection")
	receiver.reset_clean()
	receiver.receive_liquid(&"black_tea", receiver.capacity_ml)
	check(not source.can_pour_into(receiver), "A full cup still stops pouring")
	receiver.mark_served()
	check(not source.can_pour_into(receiver), "Served cups reject incoming liquid")
	receiver.mark_dirty()
	check(not source.can_pour_into(receiver), "Dirty cups reject incoming liquid")
	source.discard_contents()
	source.add_water(100.0)
	check(not source.add_tea_leaves(), "Permissive pouring does not relax default cold-water ingredient placement")


func check_immutable_history() -> void:
	var source := kettle()
	var receiver := cup()
	receiver.capacity_ml = 1000.0
	prepare(source)
	transfer(source, receiver)
	transfer(source, receiver)
	check(receiver.brew_batches.size() == 1, "Repeated transfer with identical quality is one distinct contribution")
	source.advance_brewing(source.config.steep_seconds)
	transfer(source, receiver)
	source.advance_brewing(source.config.oversteep_seconds)
	transfer(source, receiver)
	check(receiver.brew_batches.size() == 3, "Same cup retains underbrewed, ready and oversteeped contributions")
	var saved := receiver.get_service_snapshot()
	check(saved.kind == &"cup" and saved.lifecycle == &"filled" and saved.volume == 60.0 and saved.capacity == 1000.0, "Service snapshot exposes actual physical contents and lifecycle")
	check(saved.temperature == receiver.temperature and saved.cold_threshold == receiver.config.cold_temperature, "Snapshot carries live handoff temperature and configured threshold")
	check(saved.brew_batches[0].used_boiling_water and saved.brew_batches[0].infused_counts == {&"black_tea": 1}, "Snapshot records initial boiling preparation and counted batch")
	check(saved.brew_batches.all(func(batch: Dictionary) -> bool: return batch.batch_volume == 500.0), "Partial pours retain the original first-infusion volume")
	saved.brew_batches[0].infused_counts[&"black_tea"] = 99
	saved.brew_batches.clear()
	saved.ingredient_amounts[&"sugar"] = 99.0
	check(receiver.brew_batches.size() == 3 and receiver.brew_batches[0].infused_counts == {&"black_tea": 1} and receiver.get_ingredient_amounts().is_empty(), "Service snapshot nested containers cannot mutate cup authority")
	var public_batches := receiver.brew_batches
	public_batches[0].state = &"water"
	check(receiver.brew_batches[0].state == &"underbrewed", "Public batch history is a defensive copy")
	source.discard_contents()
	check(receiver.brew_batches.size() == 3, "Discarding or reusing source cannot rewrite existing cups")
	prepare(source, false, 100.0)
	source.apply_heat(100.0, 1.0)
	source.apply_ingredient(&"black_tea", 1, &"infuse", &"black_tea", true)
	source.advance_brewing(source.config.steep_seconds)
	check(not source.get_brew_batch_snapshot().used_boiling_water, "Reheating/restarting does not rewrite first-infusion boiling provenance")
	transfer(source, receiver, 100.0)
	check(source.volume_ml == 0.0 and source.get_infused_counts().is_empty(), "Exhausted batch clears source identity")
	check(receiver.brew_batches.back().infused_counts == {&"black_tea": 2} and not receiver.brew_batches.back().used_boiling_water, "Last positive transfer captures batch before source empties")
	check(receiver.brew_batches.back().batch_volume == 100.0, "Last transfer retains original batch volume even when source becomes empty")
	check(source.get_brew_batch_snapshot().state == &"water" and not source.get_brew_batch_snapshot().used_boiling_water, "Cleared kettle cannot retain old preparation history")
	receiver.discard_contents()
	check(receiver.brew_batches.is_empty() and receiver.brew_history_complete, "Discard removes all prior contribution history")
	prepare(source, true, 100.0)
	transfer(source, receiver)
	receiver.reset_clean()
	check(receiver.brew_batches.is_empty() and receiver.brew_history_complete, "Clean reset removes all prior contribution history")


func check_unknown_history() -> void:
	var receiver := cup()
	var known := {"state": &"ready", "infused_counts": {&"black_tea": 1}, "used_boiling_water": true, "batch_volume": 500.0}
	check(receiver.receive_liquid(&"black_tea", 10.0, 70.0, {}, true, known) == 10.0, "Explicit valid contribution is accepted")
	known.infused_counts[&"black_tea"] = 20
	check(receiver.brew_batches[0].infused_counts == {&"black_tea": 1}, "Input provenance is copied rather than retained by reference")
	check(receiver.receive_liquid(&"black_tea", 10.0) == 10.0 and not receiver.brew_history_complete, "Legacy nonwater receive remains compatible but marks incomplete history")
	receiver.receive_liquid(&"black_tea", 10.0, 70.0, {}, true, known)
	check(not receiver.get_service_snapshot().brew_history_complete, "A later recorded transfer cannot conceal earlier unknown tea")
	var before := receiver.get_service_snapshot()
	for invalid in [{"state": &"unknown", "infused_counts": {}, "used_boiling_water": true}, {"state": &"ready", "infused_counts": {&"black_tea": -1}, "used_boiling_water": true}, {"state": &"ready", "infused_counts": {}, "used_boiling_water": 1}]:
		check(receiver.receive_liquid(&"black_tea", 5.0, 70.0, {}, true, invalid) == 0.0 and receiver.get_service_snapshot() == before, "Malformed provenance rejects atomically")
	receiver.discard_contents()
	receiver.receive_liquid(&"water", 10.0)
	check(receiver.brew_history_complete and receiver.brew_batches.is_empty(), "Explicit plain water requires no invented tea provenance")


func check_silent_service_commit() -> void:
	var receiver := cup()
	check(not receiver.commit_served(&"empty_order"), "Physically empty cup cannot commit service")
	receiver.add_relish(&"sugar")
	var events: Array[StringName] = []
	receiver.state_changed.connect(func(_before: int, _after: int) -> void: events.append(&"state"))
	receiver.contents_changed.connect(func(_base: StringName, _items: Array[StringName], _order: StringName) -> void: events.append(&"contents"))
	check(not receiver.commit_served(&""), "Invalid order identity cannot claim cup")
	check(receiver.commit_served(&"dry_order"), "Positive dry ingredients are nonempty service contents")
	check(receiver.state == Cup.CupState.SERVED and receiver.assigned_order_id == &"dry_order" and events.is_empty(), "Silent commit stages lifecycle and ownership without notifying observers")
	check(receiver.get_service_snapshot().ingredient_amounts == {&"sugar": 1.0} and receiver.volume_ml == 0.0, "Service commit preserves offered contents for downstream custody")
	check(not receiver.commit_served(&"dry_order") and not receiver.commit_served(&"other_order"), "Already committed cup cannot be consumed twice or reassigned")
	receiver.notify_contents_changed()
	check(events == [&"state", &"contents"], "Explicit publication exposes exactly one completed transition and contents event")
	receiver.notify_contents_changed(false)
	check(events.count(&"state") == 1, "Repeated publication cannot duplicate lifecycle transition")
	receiver.mark_dirty()
	receiver.discard_contents()
	check(receiver.assigned_order_id == &"dry_order" and receiver.state == Cup.CupState.DIRTY and not receiver.commit_served(&"next_order"), "Discard preserves served history and washing requirement")
	receiver.reset_clean()
	receiver.receive_liquid(&"water", 1.0)
	check(receiver.commit_served(&"water_order"), "Any positive water volume can be committed for evaluation")
	receiver.reset_clean()
	receiver.receive_liquid(&"black_tea", 1.0)
	check(receiver.mark_served() and receiver.mark_served(), "Existing mark_served lifecycle API stays compatible and idempotent")


func check_frame_invariance() -> void:
	var coarse := kettle()
	var fine := kettle()
	var coarse_cup := cup()
	var fine_cup := cup()
	for source: Kettle in [coarse, fine]:
		prepare(source)
		source.config = source.config.duplicate() as BrewingConfig
		source.config.steep_seconds = .2
		source.config.oversteep_seconds = .3
	check(coarse.start_pour(coarse_cup) and fine.start_pour(fine_cup), "Underbrewed liquid can begin continuous pouring")
	coarse._process(.8)
	for step in 80: fine._process(.01)
	check(is_equal_approx(coarse_cup.volume_ml, 120.0) and is_equal_approx(coarse_cup.volume_ml, fine_cup.volume_ml), "One long frame and many short frames transfer the same volume across both brew boundaries")
	check(coarse.state == Kettle.BrewState.OVERSTEEPED and fine.state == coarse.state and coarse.is_pouring and fine.is_pouring, "Equivalent elapsed time preserves continuous flow and final quality")
	check(coarse_cup.brew_batches == fine_cup.brew_batches and coarse_cup.brew_batches.size() == 3, "Quality provenance is frame-size independent across underbrewed, ready and oversteeped flow")
	check(coarse.ready_heat_seconds == coarse.config.oversteep_seconds and fine.ready_heat_seconds == fine.config.oversteep_seconds, "Splitting flow does not double-advance brewing clocks")
	coarse.stop_pour()
	fine.stop_pour()


func check_mixed_batch_history() -> void:
	var source := kettle()
	var first := cup()
	var second := cup()
	var third := cup()
	prepare(source, true, 1000.0)
	source.apply_ingredient(&"sugar", 4, &"mix")
	source.apply_ingredient(&"condensed_milk", 2, &"mix")
	source.advance_brewing(source.config.steep_seconds)
	first.add_relish(&"sugar")
	transfer(source, first, 250.0)
	check(first.get_service_snapshot().inherited_ingredient_amounts == {&"sugar": 1.0, &"condensed_milk": .5}, "Service snapshot distinguishes carried ingredients from direct cup additions")
	check(first.get_service_snapshot().ingredient_amounts == {&"sugar": 2.0, &"condensed_milk": .5}, "Combined offered amounts preserve carried and direct doses")
	check(first.brew_batches[0].mixed_counts == {&"sugar": 4.0, &"condensed_milk": 2.0}, "First pour records mixed doses relative to original batch size")
	transfer(source, second, 250.0)
	check(second.brew_batches[0].mixed_counts == first.brew_batches[0].mixed_counts and second.brew_batches[0].batch_volume == 1000.0, "Partial pours preserve original-equivalent batch concentration")
	source.apply_ingredient(&"sugar", 1, &"mix")
	transfer(source, third, 250.0)
	check(third.brew_batches[0].mixed_counts == {&"sugar": 6.0, &"condensed_milk": 2.0}, "Adding another spoon to a half-empty batch records its changed equivalent dose")
	check(third.get_inherited_ingredient_amounts() == {&"sugar": 1.5, &"condensed_milk": .5}, "Normalized history does not change actual proportional transfer")
	check(first.brew_batches[0].mixed_counts[&"sugar"] == 4.0, "Later batch additions cannot rewrite a previously poured cup")
	var detached := third.get_service_snapshot()
	detached.inherited_ingredient_amounts[&"sugar"] = 99.0
	detached.brew_batches[0].mixed_counts[&"sugar"] = 99.0
	check(third.get_inherited_ingredient_amounts()[&"sugar"] == 1.5 and third.brew_batches[0].mixed_counts[&"sugar"] == 6.0, "Carried amounts and mixed history are nested defensive snapshots")
	var receiver := cup()
	var bad := source.get_brew_batch_snapshot()
	for amount: float in [-1.0, 0.0, NAN, INF]:
		bad.mixed_counts[&"sugar"] = amount
		check(receiver.receive_liquid(&"black_tea", 10.0, 70.0, {}, true, bad) == 0.0 and not receiver.has_contents(), "Invalid mixed provenance cannot partially mutate the cup")


func check_liquid_presentation() -> void:
	var source := kettle()
	var water := cup()
	var tea := cup()
	var original := tea.contents_overlay.texture as GradientTexture2D
	var original_colors := original.gradient.colors
	source.add_water(100.0)
	check(source.get_pour_color().b > source.get_pour_color().r, "Plain-water stream uses its distinct blue tint")
	transfer(source, water)
	var water_texture := water.contents_overlay.texture as GradientTexture2D
	check(water.contents_overlay.visible and water_texture != original and water_texture.gradient != original.gradient, "Water cup uses an independent gradient without mutating shared tea art")
	check(water_texture.gradient.colors[0].b > water_texture.gradient.colors[0].r, "Water cup surface matches water identity")
	check(water_texture.gradient.offsets == original.gradient.offsets and is_equal_approx(water_texture.gradient.colors[0].a, original_colors[0].a) and water_texture.gradient.colors[1].a == original_colors[1].a, "Water tint preserves authored liquid shape and transparency")
	check(original.gradient.colors == original_colors, "Tinting water leaves another cup's shared tea palette untouched")
	prepare(source)
	check(source.get_pour_color() == Color(.58, .29, .10, .9), "Tea retains its existing stream palette")
	transfer(source, tea)
	check(tea.contents_overlay.texture == original and (tea.contents_overlay.texture as GradientTexture2D).gradient.colors == original_colors, "Tea cup retains its existing surface palette")
	water.discard_contents()
	transfer(source, water)
	check(water.contents_overlay.texture == original, "Refilling a former water cup with tea restores the original tea surface")


func check_held_boundary() -> void:
	var screen := (load("res://scenes/gameplay/tong/TongDayScreen.tscn") as PackedScene).instantiate() as Node2D
	screen.set("customer_queue_enabled", false)
	root.add_child(screen)
	owned.append(screen)
	await process_frame
	var source := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	var receiver := tray.get_cups()[0] as Cup
	var controller := screen.get_node("InteractionController") as InteractionController
	source.set_process(false)
	receiver.set_process(false)
	controller.set_mode(InteractionController.MODE_INTERACT)
	prepare(source)
	source.advance_brewing(source.config.steep_seconds + source.config.oversteep_seconds - .1)
	check(source.begin_drag(source.grip_anchor.get_global_transform_with_canvas().origin), "Real controller picks up ready kettle")
	var target := (receiver.get_node("PourTarget") as Node2D).get_global_transform_with_canvas().origin
	var pointer := source.grip_anchor.get_global_transform_with_canvas().origin + target - source.get_pour_probe_viewport()
	controller.update_drag(pointer)
	Input.action_press(InteractionController.INPUT_POUR)
	source._process(.5)
	check(source.is_pouring and source.is_held and source.state == Kettle.BrewState.OVERSTEEPED, "Held Space keeps flow active through ready-to-oversteeped transition")
	check(is_equal_approx(receiver.volume_ml, 75.0) and is_equal_approx(source.volume_ml, 425.0), "Boundary crossing does not truncate or duplicate liquid")
	check(receiver.brew_batches.size() == 2 and receiver.brew_batches[0].state == &"ready" and receiver.brew_batches[1].state == &"oversteeped", "A single held frame crossing the boundary records both actual contribution qualities")
	source._process(.1)
	check(receiver.brew_batches.any(func(batch: Dictionary) -> bool: return batch.state == &"oversteeped"), "Continuing held flow records oversteeped liquid")
	Input.action_release(InteractionController.INPUT_POUR)
	source._process(.1)
	check(not source.is_pouring and receiver.volume_ml == 90.0, "Releasing Space still stops imperfect liquid immediately")
	controller.cancel_drag()
