extends SceneTree

const KETTLE_SCENE := preload("res://scenes/gameplay/tools/Kettle.tscn")
const CUP_SCENE := preload("res://scenes/gameplay/tools/Cup.tscn")

var checks := 0
var failures: Array[String] = []
var owned: Array[Node] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	check_generic_effects()
	check_mixed_transfers()
	check_receiving_validation()
	check_signal_atomicity()
	check_default_compatibility()
	for node in owned:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Configurable vessels: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


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


func check_generic_effects() -> void:
	var source := kettle()
	check(source.get_ingredient_stage() == &"empty" and source.get_ingredient_amounts().is_empty(), "Empty kettle begins with no counted contents")
	check(not source.apply_ingredient(&"herbal_bag", 1, &"infuse", &"herbal_tea"), "Infusion needs positive liquid")
	check(source.apply_ingredient(&"sugar", 3, &"mix"), "Generic mixing can retain dry portions when a policy permits it")
	check(source.has_contents() and not source.contains_tea and source.state == Kettle.BrewState.EMPTY, "Dry sugar is content but does not start a brew")
	check(source.get_mixed_amounts() == {&"sugar": 3.0}, "Mixed units are counted without liquid conversion")
	check(source.add_water(1000.0) == 1000.0, "Water can fill an uninfused batch")
	source.apply_heat(10.0, 1.0)
	check(source.get_ingredient_stage() == &"boiling", "Stage accessor exposes boiling state")
	var before_volume := source.volume_ml
	var before_temperature := source.temperature
	check(source.apply_ingredient(&"herbal_bag", 5, &"infuse", &"herbal_tea"), "Generic infusion stores five non-black-tea portions")
	check(source.get_infused_counts() == {&"herbal_bag": 5} and source.brewed_liquid_id == &"herbal_tea", "Infusion counts and output identity are independent of black tea")
	check(source.volume_ml == before_volume and source.temperature == before_temperature, "Ingredient effects do not invent volume or heat")
	source.advance_brewing(1.0)
	check(source.apply_ingredient(&"herbal_bag", 1, &"infuse", &"herbal_tea"), "Additional same-output infusion is physically supported")
	check(source.steep_progress == 1.0 and source.get_infused_counts()[&"herbal_bag"] == 6, "Repeated infusion preserves the existing clock by default")
	var before := source.get_ingredient_amounts()
	check(not source.apply_ingredient(&"coffee", 1, &"infuse", &"coffee"), "A different beverage cannot overwrite an existing batch")
	check(source.get_ingredient_amounts() == before and source.brewed_liquid_id == &"herbal_tea", "Incompatible infusion rejects without partial mutation")
	check(source.apply_ingredient(&"condensed_milk", 2, &"mix"), "Mixing works during a brew when selected policy allows it")
	check(source.steep_progress == 1.0 and source.brewed_liquid_id == &"herbal_tea", "Milk does not masquerade as tea or restart steeping")
	source.advance_brewing(source.config.steep_seconds + 2.0)
	var ready_elapsed := source.ready_heat_seconds
	check(source.get_ingredient_stage() == &"liquor_ready", "Infusion reaches the generic ready stage")
	check(source.apply_ingredient(&"herbal_bag", 1, &"infuse", &"herbal_tea") and source.ready_heat_seconds == ready_elapsed, "A preserved ready batch keeps its elapsed clock after another allowed bag")
	check(source.apply_ingredient(&"herbal_bag", 1, &"infuse", &"herbal_tea", true), "An explicit repeat-infusion restart is supported")
	check(source.state == Kettle.BrewState.STEEPING and source.steep_progress == 0.0 and source.ready_heat_seconds == 0.0, "Restart resets only brewing clocks and phase")
	var snapshot := source.get_mixed_amounts()
	snapshot[&"sugar"] = 99.0
	check(source.get_mixed_amounts()[&"sugar"] == 3.0, "External count snapshots cannot mutate vessel contents")
	for effect in [&"unknown", &""]:
		check(not source.apply_ingredient(&"sugar", 1, effect), "Unknown kettle effects fail closed")
	check(not source.apply_ingredient(&"", 1, &"mix") and not source.apply_ingredient(&"sugar", 0, &"mix"), "Empty IDs and zero-quantity applications do not create contents")
	check(not source.apply_ingredient(&"sugar", -1, &"mix"), "Negative quantities cannot remove committed ingredients")
	check(not source.apply_ingredient(&"sugar", 1, &"mix", &"black_tea"), "A mix effect cannot secretly assign brewed output")
	check(source.discard_contents() == 1000.0 and not source.has_contents(), "Kettle disposal clears liquid, infusing bags and mixed ingredients")
	check(source.brewed_liquid_id.is_empty() and source.get_ingredient_amounts().is_empty(), "Discard resets beverage identity without refunding ingredients")
	var receiver := cup()
	check(receiver.get_ingredient_stage() == &"clean", "Cup exposes its lifecycle stage")
	check(not receiver.apply_ingredient(&"herbal_bag", 1, &"infuse", &"herbal_tea"), "Cup infusion fails closed because cup brewing is not implemented")
	check(receiver.apply_ingredient(&"herbal_bag", 2, &"mix"), "A configured cup mix can count teabags without brewing them")
	check(receiver.get_ingredient_amounts() == {&"herbal_bag": 2.0} and receiver.liquid_type.is_empty(), "A cup-side mix does not invent a beverage")
	receiver.state = Cup.CupState.DIRTY
	check(receiver.can_apply_ingredient(&"sugar", 1, &"mix") and receiver.apply_ingredient(&"sugar", 1, &"mix"), "Generic cup effects leave dirty-stage permission to central policy")
	check(receiver.state == Cup.CupState.DIRTY and not receiver.add_relish(&"sugar"), "A generic mix never washes the cup; legacy default still rejects dirty additions")
	check(receiver.discard_contents() == 0.0 and not receiver.has_contents(), "Dry mixed additions can be discarded from the same cup")


func prepared_source() -> Kettle:
	var source := kettle()
	source.add_water(1000.0)
	source.apply_ingredient(&"herbal_bag", 5, &"infuse", &"herbal_tea")
	source.apply_ingredient(&"sugar", 4, &"mix")
	source.apply_ingredient(&"condensed_milk", 2, &"mix")
	source.advance_brewing(source.config.steep_seconds)
	return source


func check_mixed_transfers() -> void:
	var source := prepared_source()
	var first := cup()
	first.add_relish(&"sugar")
	check(source.start_pour(first), "Generic beverage can start pouring into an empty eligible cup")
	source.update_pour(250.0 / source.config.pour_rate_ml)
	check(first.volume_ml == 250.0 and first.liquid_type == &"herbal_tea", "Pour preserves the generic output identity")
	check(first.get_inherited_ingredient_amounts() == {&"sugar": 1.0, &"condensed_milk": 0.5}, "One quarter batch carries one quarter of its dissolved units")
	check(first.get_ingredient_amounts() == {&"sugar": 2.0, &"condensed_milk": 0.5}, "Combined read model includes pre-added and inherited units")
	check(first.get_relish_counts() == {&"sugar": 1}, "Legacy direct-spoon list is not polluted with rounded inherited units")
	check(source.get_mixed_amounts() == {&"sugar": 3.0, &"condensed_milk": 1.5}, "Kettle retains exactly the unpoured mixed units")
	check(source.get_infused_counts() == {&"herbal_bag": 5}, "Infusing bags remain in the batch through a partial pour")
	var second := cup()
	second.capacity_ml = 100.0
	check(source.start_pour(second), "A second cup can receive the remainder")
	source.update_pour(1.0)
	check(second.volume_ml == 100.0 and source.volume_ml == 650.0, "A capacity-limited pour deducts only liquid actually accepted")
	check(near(second.get_ingredient_amounts().get(&"sugar", 0.0), 0.4) and near(second.get_ingredient_amounts().get(&"condensed_milk", 0.0), 0.2), "Capacity-limited pour scales fractional units by accepted volume")
	var third := cup()
	third.capacity_ml = 650.0
	check(source.start_pour(third), "The remaining batch can be poured without fixed cup-size assumptions")
	source.update_pour(20.0)
	check(source.volume_ml == 0.0 and not source.has_contents() and source.brewed_liquid_id.is_empty(), "Emptying the whole batch clears retained infusion and mixed state")
	check(near(total_amount([first, second, third], &"sugar"), 5.0), "All cups conserve four kettle sugar units plus one directly added spoon")
	check(near(total_amount([first, second, third], &"condensed_milk"), 2.0), "All cups conserve the original milk units without rounding")
	check(first.discard_contents() == 250.0 and first.get_ingredient_amounts().is_empty(), "Cup disposal clears both direct and inherited ingredient stores")
	first.receive_liquid(&"black_tea", 225.0, 70.0)
	check(first.get_ingredient_amounts().is_empty(), "Refill cannot revive discarded inherited fractions")
	second.reset_clean()
	check(second.get_ingredient_amounts().is_empty() and not second.has_contents(), "Clean reset clears inherited content as well")


func check_receiving_validation() -> void:
	var receiver := cup()
	var invalid: Dictionary[StringName, float] = {&"sugar": NAN}
	check(receiver.receive_liquid(&"black_tea", 100.0, 70.0, invalid) == 0.0 and not receiver.has_contents(), "Nonfinite carried units reject before any liquid mutation")
	invalid[&"sugar"] = -1.0
	check(receiver.receive_liquid(&"black_tea", 100.0, 70.0, invalid) == 0.0, "Negative carried units reject without creating contents")
	var carried: Dictionary[StringName, float] = {&"sugar": 2.0}
	receiver.capacity_ml = 100.0
	check(receiver.receive_liquid(&"black_tea", 200.0, 70.0, carried) == 100.0, "Direct receive accepts only free liquid capacity")
	check(receiver.get_ingredient_amounts() == {&"sugar": 1.0}, "Direct receive scales the requested payload to accepted liquid")
	check(receiver.apply_ingredient(&"sugar", 1, &"mix") and receiver.get_ingredient_amounts() == {&"sugar": 2.0}, "Liquid-full cups still take abstract mixed portions")
	receiver.volume_ml = INF
	check(not receiver.can_apply_ingredient(&"sugar", 1, &"mix"), "Configurable stage permissions cannot bypass invalid physical state")
	receiver.volume_ml = 100.0
	var detached := cup()
	root.remove_child(detached)
	check(not detached.apply_ingredient(&"sugar", 1, &"mix"), "Detached vessels reject generic ingredient effects")
	detached.free()


func check_signal_atomicity() -> void:
	var source := prepared_source()
	var receiver := cup()
	receiver.liquid_changed.connect(func(_amount: float):
		check(near(source.volume_ml + receiver.volume_ml, 1000.0), "Cup signal observes both completed liquid mutations")
		check(near(source.get_mixed_amounts().get(&"sugar", 0.0) + receiver.get_ingredient_amounts().get(&"sugar", 0.0), 4.0), "Cup signal observes conserved mixed ingredients across both vessels")
	, CONNECT_ONE_SHOT)
	source.start_pour(receiver)
	source.update_pour(1.0)
	source.stop_pour()
	var second_source := prepared_source()
	var second := cup()
	second.liquid_changed.connect(func(_amount: float): second_source.discard_contents(), CONNECT_ONE_SHOT)
	second_source.start_pour(second)
	second_source.update_pour(1.0)
	check(second_source.volume_ml == 0.0 and not second_source.has_contents(), "Reentrant source discard cannot be followed by a stale debit")
	check(near(second.get_ingredient_amounts().get(&"sugar", 0.0), 0.6) and second.volume_ml == 150.0, "Source disposal after committed transfer retains the cup's accepted fraction")
	var freed_source := prepared_source()
	var retained := cup()
	retained.liquid_changed.connect(func(_amount: float): freed_source.queue_free(), CONNECT_ONE_SHOT)
	freed_source.start_pour(retained)
	freed_source.update_pour(1.0)
	check(freed_source.is_queued_for_deletion() and retained.volume_ml == 150.0 and near(retained.get_ingredient_amounts().get(&"sugar", 0.0), 0.6), "Removing the source from a receiver callback preserves the committed received portion")
	var retained_source := prepared_source()
	var freed_receiver := cup()
	freed_receiver.liquid_changed.connect(func(_amount: float): freed_receiver.queue_free(), CONNECT_ONE_SHOT)
	retained_source.start_pour(freed_receiver)
	retained_source.update_pour(1.0)
	check(freed_receiver.is_queued_for_deletion() and retained_source.volume_ml == 850.0 and not retained_source.is_pouring, "Removing the receiver during notification stops future flow after the committed transfer")
	check(near(retained_source.get_mixed_amounts().get(&"sugar", 0.0), 3.4), "Removed receiver cannot cause a duplicate or missing source ingredient debit")


func check_default_compatibility() -> void:
	var source := kettle()
	source.add_water(1000.0)
	check(not source.add_tea_leaves(), "Legacy tea call still respects the central default boiling requirement")
	source.apply_heat(10.0, 1.0)
	check(source.add_tea_leaves() and source.contains_tea, "Legacy tea call delegates the configured default infusion")
	check(not source.add_tea_leaves() and source.get_infused_counts() == {&"black_tea": 1}, "Default central max-count still rejects a second bag")
	source.apply_ingredient(&"sugar", 1, &"mix")
	source.contains_tea = false
	check(source.get_infused_counts().is_empty() and source.brewed_liquid_id.is_empty() and source.get_mixed_amounts() == {&"sugar": 1.0}, "Compatibility false setter clears infusion authority without erasing separate mixed contents")
	source.contains_tea = true
	check(source.get_infused_counts() == {&"black_tea": 1}, "Compatibility true setter maps to one counted legacy bag")


func total_amount(cups: Array, item_id: StringName) -> float:
	var total := 0.0
	for value: Cup in cups:
		total += value.get_ingredient_amounts().get(item_id, 0.0)
	return total


func near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.00000001


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
