extends SceneTree
## Exercise alternate resources through the same stock-conserving command path.

class CallbackStock extends InventoryState:
	var before_apply: Callable
	func commit(token: int, apply: Callable) -> bool:
		return super.commit(token, func() -> bool:
			if before_apply.is_valid(): before_apply.call()
			return apply.call())

var checks := 0
var failures: Array[String] = []
var screen: Node2D
var kettle: Kettle
var cup: Cup
var source := Node2D.new()
var stock := CallbackStock.new()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func policy_copy() -> IngredientPolicy:
	return IngredientDropCommand.DEFAULT_POLICY.duplicate(true) as IngredientPolicy

func reset_vessels(ml := 500.0, degrees := 100.0) -> void:
	kettle.discard_contents()
	kettle.add_water(ml)
	kettle.temperature = degrees
	cup.reset_clean()

func drop(policy: IngredientPolicy, target: Node2D, id: StringName, expected: bool) -> void:
	var before := stock.remaining(id)
	var old_contents: Dictionary = target.call("get_ingredient_amounts")
	var portion := IngredientPortion.new(id, stock.get_unit(id), source, stock)
	portion.token = stock.reserve(id, portion.unit, 1, source.get_instance_id())
	var command := IngredientDropCommand.new(portion, target, policy, screen)
	check(command.can_execute().is_valid == expected, "%s reports the selected rule" % id)
	check(command.execute() == expected, "%s applies only the selected rule" % id)
	check(stock.remaining(id) == before - int(expected), "Shared stock follows the actual committed effect")
	var after_contents: Dictionary = target.call("get_ingredient_amounts")
	if not expected: check(after_contents == old_contents, "Rejected configuration leaves contents unchanged")
	check(not command.execute() and target.call("get_ingredient_amounts") == after_contents, "One command cannot replay")
	portion.cancel()
	check(stock.available(id) == stock.remaining(id), "Resolved action has no orphan reservation")

func check_count_limits() -> void:
	var five := load("res://data/examples/ingredient_rules/five_teabags.tres") as IngredientPolicy
	var zero := load("res://data/examples/ingredient_rules/no_teabags.tres") as IngredientPolicy
	check(five.configuration_errors().is_empty() and zero.configuration_errors().is_empty(), "Alternate count resources validate")
	reset_vessels()
	for index in 5:
		drop(five, kettle, &"black_tea", true)
		check(kettle.get_infused_counts().get(&"black_tea") == index + 1, "Each bag is counted in this batch")
	drop(five, kettle, &"black_tea", false)
	check(kettle.get_infused_counts().get(&"black_tea") == 5, "Sixth bag cannot exceed configured five")
	reset_vessels()
	drop(zero, kettle, &"black_tea", false)
	check(not kettle.contains_tea and kettle.brewed_liquid_id.is_empty(), "Zero allowed does not turn water into tea")
	drop(IngredientDropCommand.DEFAULT_POLICY, kettle, &"black_tea", true)
	drop(IngredientDropCommand.DEFAULT_POLICY, kettle, &"black_tea", false)
	check(IngredientDropCommand.DEFAULT_POLICY.rule_for(&"black_tea", kettle).max_portions == 1, "Examples never mutate the normal default")
	var recipe: Resource = load("res://data/recipes/cha.tres")
	check(recipe.kettle_portion_counts[&"black_tea"] == 1, "Recipe desired dose is independent of the five-bag permission")

func check_stages_and_mixing() -> void:
	var policy := load("res://data/examples/ingredient_rules/mixing_and_stages.tres") as IngredientPolicy
	check(policy.configuration_errors().is_empty(), "Stage and mixing example validates")
	reset_vessels(500, 20)
	drop(policy, kettle, &"sugar", false)
	drop(policy, kettle, &"black_tea", true)
	check(kettle.state == Kettle.BrewState.STEEPING and kettle.temperature == 20, "Disabling boiling really starts the permitted cool infusion")
	kettle.advance_brewing(0.5)
	drop(policy, kettle, &"black_tea", true)
	check(is_equal_approx(kettle.steep_progress, 0.5), "Repeated infusion preserves elapsed progress by default")
	drop(policy, kettle, &"sugar", true)
	check(is_equal_approx(kettle.steep_progress, 0.5) and kettle.get_infused_counts().size() == 1, "Sugar records a mixed dose without restarting or becoming tea")
	drop(policy, kettle, &"condensed_milk", false)
	kettle.advance_brewing(kettle.config.steep_seconds)
	drop(policy, kettle, &"condensed_milk", true)
	check(kettle.volume_ml == 500 and kettle.temperature == 20, "Kettle spoon units leave volume and temperature unchanged")
	check(kettle.start_pour(cup), "Generic output can use the normal pour path")
	kettle.update_pour(250.0 / kettle.config.pour_rate_ml)
	check(cup.volume_ml == 250 and kettle.volume_ml == 250, "Pour preserves measured water volume")
	for id: StringName in [&"sugar", &"condensed_milk"]:
		check(is_equal_approx(cup.get_ingredient_amounts().get(id, 0.0), 0.5)
			and is_equal_approx(kettle.get_mixed_amounts().get(id, 0.0), 0.5), "Mixed abstract units distribute with the liquid, without duplication")
	check(kettle.get_infused_counts()[&"black_tea"] == 2 and not cup.get_ingredient_amounts().has(&"black_tea"), "Infusing bags remain with the batch")
	var service := load("res://scripts/development/brewing_preview_service_zone.gd").new() as DropZone
	var sample: Dictionary = service.call("_snapshot", cup)
	check(sample.garnish_count == 2 and not service.review.inspect(&"mixed_sample", sample, 225.0).accepted,
		"Plain-tea sample rejects additions inherited from kettle liquid")
	service.free()
	cup.discard_contents()
	check(cup.get_ingredient_amounts().is_empty(), "Discard clears inherited units too")
	check(kettle.start_pour(cup), "Remainder can be poured after emptying the cup")
	kettle.update_pour(250.0 / kettle.config.pour_rate_ml)
	check(kettle.get_ingredient_amounts().is_empty() and kettle.brewed_liquid_id.is_empty(), "An emptied kettle resets the whole batch")
	reset_vessels(500, 20)
	var restart := policy.duplicate(true) as IngredientPolicy
	restart.rule_for(&"black_tea", kettle).restart_steeping = true
	drop(restart, kettle, &"black_tea", true)
	kettle.advance_brewing(1.0)
	drop(restart, kettle, &"black_tea", true)
	check(kettle.steep_progress == 0, "Configured repeat infusion can explicitly restart its clock")

func check_new_identity_and_destinations() -> void:
	var policy := policy_copy()
	var coffee := IngredientRule.new()
	coffee.item_id = &"test_coffee"
	coffee.unit = &"spoonful"
	coffee.vessel_kind = "kettle"
	coffee.effect = "infuse"
	coffee.output_liquid_id = &"coffee"
	coffee.allowed_stages = [&"water", &"steeping", &"liquor_ready"]
	coffee.allowed_liquid_ids = [&"water", &"coffee"]
	coffee.max_portions = 5
	policy.rules.append(coffee)
	reset_vessels(500, 30)
	drop(policy, kettle, &"test_coffee", true)
	kettle.advance_brewing(kettle.config.steep_seconds)
	check(kettle.start_pour(cup), "Data-defined coffee output pours without a tea branch")
	kettle.update_pour(0.5)
	kettle.stop_pour()
	check(cup.liquid_type == &"coffee" and cup.contents_base_id == &"coffee", "The configured beverage identity reaches the cup")
	drop(policy, cup, &"sugar", false)
	policy.rule_for(&"sugar", cup).allowed_liquid_ids.append(&"coffee")
	drop(policy, cup, &"sugar", true)
	var cup_bag := IngredientRule.new()
	cup_bag.item_id = &"black_tea"
	cup_bag.unit = &"teabag"
	cup_bag.vessel_kind = "cup"
	cup_bag.allowed_stages = [&"clean", &"in_use", &"filled"]
	cup_bag.allow_empty = true
	policy.rules.append(cup_bag)
	cup.reset_clean()
	drop(policy, cup, &"black_tea", true)
	check(cup.get_ingredient_amounts()[&"black_tea"] == 1 and cup.liquid_type.is_empty(), "Cup permission records a bag; mix never invents cup brewing")

func check_bad_configuration_and_revalidation() -> void:
	reset_vessels()
	var policy := policy_copy()
	policy.rules.append(policy.rules[0].duplicate(true))
	check(not policy.configuration_errors().is_empty(), "Duplicate item/vessel rules fail clearly")
	drop(policy, kettle, &"black_tea", false)
	policy = policy_copy()
	var rule := policy.rule_for(&"sugar", cup)
	rule.effect = "infuse"
	rule.output_liquid_id = &"black_tea"
	check(not policy.configuration_errors().is_empty(), "Unsupported cup infusion is explicit, never silently mixing")
	drop(policy, cup, &"sugar", false)
	policy = policy_copy()
	rule = policy.rule_for(&"sugar", cup)
	rule.allowed_stages = [&"typo"]
	check(not policy.configuration_errors().is_empty(), "Unknown brewing stage reports a configuration error")
	policy = policy_copy()
	rule = policy.rule_for(&"sugar", cup)
	stock.before_apply = func() -> void: rule.max_portions = 0
	var portion := IngredientPortion.new(&"sugar", &"spoonful", source, stock)
	portion.token = stock.reserve(&"sugar", &"spoonful", 1, source.get_instance_id())
	var command := IngredientDropCommand.new(portion, cup, policy, screen)
	var before := stock.remaining(&"sugar")
	check(command.can_execute().is_valid and not command.execute(), "Policy is revalidated inside the inventory transaction")
	check(stock.remaining(&"sugar") == before and cup.get_ingredient_amounts().is_empty(), "Callback-time rule changes roll back with no contents or stock loss")
	stock.before_apply = Callable()
	portion.cancel()
	check(stock.available(&"sugar") == before, "Cancelled rejected command releases its pending reservation")
	check(screen.set_ingredient_policy(policy_copy()), "A valid scene policy can be selected")
	for target in screen.find_children("IngredientTarget", "", true, false):
		check(target.policy == screen.ingredient_policy, "All current physical/pantry target adapters share the selected policy")
	var bad := policy_copy()
	bad.rules[0].effect = "unknown"
	check(not screen.set_ingredient_policy(bad), "Invalid scene policy cannot replace the working selection")

func check_permissions_and_bounds() -> void:
	reset_vessels()
	var policy := policy_copy()
	var sugar := policy.rule_for(&"sugar", cup)
	sugar.allow_repeated = false
	drop(policy, cup, &"sugar", true)
	drop(policy, cup, &"sugar", false)
	sugar.allow_repeated = true
	cup.receive_liquid(&"black_tea", 250, 65)
	cup.mark_served()
	drop(policy, cup, &"sugar", false)
	sugar.allowed_stages.append(&"served")
	drop(policy, cup, &"sugar", true)
	check(cup.state == Cup.CupState.SERVED, "Configured served-stage addition does not change serving state")
	cup.mark_dirty()
	drop(policy, cup, &"sugar", false)
	sugar.allowed_stages.append(&"dirty")
	drop(policy, cup, &"sugar", true)
	check(cup.state == Cup.CupState.DIRTY, "Configured dirty-stage addition does not wash a cup")
	var kettle_mix := sugar.duplicate(true) as IngredientRule
	kettle_mix.vessel_kind = "kettle"
	kettle_mix.allowed_stages = [&"empty", &"water"]
	kettle_mix.allowed_liquid_ids = [&"water"]
	policy.rules.append(kettle_mix)
	kettle.discard_contents()
	drop(policy, kettle, &"sugar", true)
	check(kettle.volume_ml == 0 and not kettle.contains_tea and kettle.has_contents(), "Empty-stage mixing records a dry addition without brewing or liquid")
	kettle.add_water(500)
	kettle_mix.minimum_volume_ml = 600
	drop(policy, kettle, &"sugar", false)
	kettle_mix.minimum_volume_ml = 500
	kettle_mix.max_batch_volume_ml = 400
	drop(policy, kettle, &"sugar", false)
	kettle_mix.max_batch_volume_ml = 500
	kettle_mix.minimum_temperature = 30
	kettle_mix.maximum_temperature = 40
	drop(policy, kettle, &"sugar", false)
	kettle.temperature = 41
	drop(policy, kettle, &"sugar", false)
	kettle.temperature = 30
	drop(policy, kettle, &"sugar", true)
	check(kettle.get_mixed_amounts()[&"sugar"] == 2, "Inclusive configured temperature and volume boundaries permit the intended addition")
	kettle.discard_contents()

func run() -> void:
	screen = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await physics_frame
	screen.add_child(source)
	kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	cup = screen.get_cups()[0]
	kettle.controller.set_mode(InteractionController.MODE_USE)
	kettle.set_process(false)
	cup.set_process(false)
	for burner in screen.get_node("WorldRoot/ToolLayer/StoveStation").burners: burner.set_process(false)
	check(stock.reset({&"black_tea": 100, &"sugar": 100, &"condensed_milk": 100, &"test_coffee": 100},
		{&"black_tea": &"teabag", &"sugar": &"spoonful", &"condensed_milk": &"spoonful", &"test_coffee": &"spoonful"}), "Alternative ingredient fixture uses the same stock authority")
	check_count_limits()
	check_stages_and_mixing()
	check_new_identity_and_destinations()
	check_permissions_and_bounds()
	check_bad_configuration_and_revalidation()
	screen.queue_free()
	await process_frame
	print("DESIGNER_INGREDIENT_RULES: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
