extends SceneTree

const CUP_SCENE := preload("res://scenes/gameplay/tools/Cup.tscn")
const RECIPE_SCRIPT := preload("res://scripts/data/recipe_def.gd")

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	check_recipe_data()
	await check_cup_portions()
	for failure in failures:
		push_error(failure)
	print("Recipe and cup portions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check_recipe_data() -> void:
	var cases := [
		{"id": &"cha_no_sugar", "price": 5, "cup": {}},
		{"id": &"cha", "price": 6, "cup": {&"sugar": 1}},
		{"id": &"dudh_cha_no_sugar", "price": 7, "cup": {&"condensed_milk": 1}},
		{"id": &"dudh_cha", "price": 8, "cup": {&"condensed_milk": 1, &"sugar": 1}},
	]
	var tool: Resource = load("res://data/balance/tool_level_1.tres")
	for entry: Dictionary in cases:
		var recipe: Resource = load("res://data/recipes/%s.tres" % entry.id)
		check(recipe != null, "%s resource remains loadable" % entry.id)
		if recipe == null:
			continue
		check(recipe.id == entry.id and recipe.output_item_id == entry.id, "%s preserves its recipe/output identity" % entry.id)
		check(recipe.price == entry.price and recipe.unlocked_by_default, "%s preserves its price and unlock state" % entry.id)
		check(recipe.base_item_ids == [&"water", &"black_tea"], "%s retains ingredient provenance" % entry.id)
		check(recipe.production_supported and recipe.brewed_liquid_id == &"black_tea", "%s distinguishes brewed liquid from finished recipe" % entry.id)
		check(recipe.kettle_portion_counts == {&"black_tea": 1}, "%s uses one bag per batch" % entry.id)
		check(recipe.kettle_portion_units == {&"black_tea": &"teabag"}, "%s records the approved tea unit" % entry.id)
		check(recipe.batch_requires_boiling_water and recipe.max_batch_volume_ml == 1500.0, "%s records the boiling-water batch limit" % entry.id)
		check(recipe.max_batch_volume_ml == tool.kettle_capacity_ml, "%s batch limit matches the current kettle" % entry.id)
		check(recipe.target_serving_volume_ml == 250.0 and recipe.minimum_serving_volume_ml == 225.0, "%s records separate target and minimum servings" % entry.id)
		check(recipe.cup_portion_counts == entry.cup, "%s records exact standard spoon counts" % entry.id)
		check(recipe.cup_portion_units.size() == entry.cup.size(), "%s has no extra cup units" % entry.id)
		check(recipe.relish_item_ids.size() == entry.cup.size(), "%s retains the same standard ingredient list" % entry.id)
		for item_id: StringName in entry.cup:
			check(recipe.relish_item_ids.has(item_id), "%s preserves %s in the recipe" % [entry.id, item_id])
			check(recipe.cup_portion_units.get(item_id) == &"spoonful", "%s records spoonfuls for %s" % [entry.id, item_id])
			var item: Resource = load("res://data/items/%s.tres" % item_id)
			check(item.unit == recipe.cup_portion_units[item_id], "%s dose agrees with shared-stock units" % item_id)
	var tea: Resource = load("res://data/items/black_tea.tres")
	check(tea.unit == &"teabag", "Current black-tea stock remains measured in teabags")
	var water: Resource = load("res://data/items/water.tres")
	check(water.unit == &"ml", "Measured water remains separate from ingredient portions")
	for entry: Dictionary in [{"id": &"ginger_tea", "ingredient": &"ginger"}, {"id": &"lemon_tea", "ingredient": &"lemon"}]:
		var recipe: Resource = load("res://data/recipes/%s.tres" % entry.id)
		check(recipe != null, "%s legacy resource remains loadable" % entry.id)
		if recipe == null:
			continue
		check(recipe.id == entry.id and recipe.output_item_id == entry.id and recipe.price == 7 and recipe.unlocked_by_default, "%s keeps its existing identity, price and unlock flag" % entry.id)
		check(recipe.base_item_ids == [&"water", &"black_tea"] and recipe.relish_item_ids == [entry.ingredient], "%s keeps its existing no-sugar ingredient meaning" % entry.id)
		check(not recipe.production_supported and recipe.brewed_liquid_id.is_empty(), "%s is not silently enabled in production" % entry.id)
		check(recipe.kettle_portion_counts.is_empty() and recipe.cup_portion_counts.is_empty() and recipe.kettle_portion_units.is_empty() and recipe.cup_portion_units.is_empty(), "%s does not invent new ingredient doses" % entry.id)
		check(recipe.max_batch_volume_ml == 0.0 and recipe.minimum_serving_volume_ml == 0.0 and recipe.target_serving_volume_ml == 0.0, "%s does not inherit an unapproved production serving rule" % entry.id)
	var defaults: Resource = RECIPE_SCRIPT.new()
	check(not defaults.production_supported and defaults.cup_portion_counts.is_empty(), "Older resource shape retains safe unconfigured defaults")


func check_cup_portions() -> void:
	var cup := CUP_SCENE.instantiate() as Cup
	root.add_child(cup)
	await process_frame
	cup.set_process(false)
	check(not cup.has_contents() and cup.get_relish_counts().is_empty(), "New cup has no ingredient or liquid contents")
	check(not cup.add_relish(&"") and cup.state == Cup.CupState.CLEAN, "An empty ingredient ID leaves a clean cup unchanged")
	check(cup.get_relish_count(&"") == 0 and cup.get_relish_count(&"sugar") == 0, "Absent ingredient counts are zero")
	cup.state_changed.connect(func(previous: Cup.CupState, current: Cup.CupState):
		check(previous == Cup.CupState.CLEAN and current == Cup.CupState.IN_USE, "First spoon announces the completed cup lifecycle change")
		check(cup.get_relish_count(&"sugar") == 1 and cup.state == Cup.CupState.IN_USE, "Synchronous state observers see coherent ingredient and lifecycle state")
	, CONNECT_ONE_SHOT)
	for index in range(7):
		check(cup.add_relish(&"sugar"), "Dry cup accepts sugar spoon %d without a three-spoon cap" % (index + 1))
	for index in range(4):
		check(cup.add_relish(&"condensed_milk"), "Dry cup accepts milk spoon %d without a three-spoon cap" % (index + 1))
	check(cup.state == Cup.CupState.IN_USE and cup.volume_ml == 0.0 and cup.has_contents(), "Dry ingredients mark the cup in use without adding liquid")
	check(cup.get_relish_count(&"sugar") == 7 and cup.get_relish_count(&"condensed_milk") == 4, "Repeated ingredients are counted separately")
	check(cup.relish_item_ids.size() == 11, "The compatible ingredient list remains the single stored authority")
	var counts := cup.get_relish_counts()
	counts[&"sugar"] = 99
	check(cup.get_relish_count(&"sugar") == 7, "Mutating a count snapshot cannot change cup contents")
	check(cup.receive_liquid(&"black_tea", 100.0, 85.0) == 100.0, "A cup with dry ingredients receives tea")
	check(cup.get_relish_counts() == {&"sugar": 7, &"condensed_milk": 4}, "The first pour preserves all pre-added spoon counts")
	check(cup.receive_liquid(&"black_tea", 150.0, 55.0) == 150.0, "A second pour fills the cup without replacing ingredients")
	check(is_equal_approx(cup.temperature, 67.0), "Only incoming liquid affects the mixed temperature")
	var full_temperature := cup.temperature
	check(not cup.can_receive_liquid(&"black_tea") and cup.can_accept_relish(&"sugar"), "A liquid-full cup can still accept an abstract spoon")
	check(cup.add_relish(&"sugar") and cup.get_relish_count(&"sugar") == 8, "An extra spoon in a full cup remains counted")
	check(cup.volume_ml == 250.0 and cup.temperature == full_temperature, "Abstract spoons change neither liquid volume nor temperature")
	check(cup.receive_liquid(&"water", 1.0) == 0.0 and cup.get_relish_count(&"sugar") == 8, "Rejected incompatible liquid preserves ingredient counts")
	var before := cup.get_relish_counts()
	check(cup.mark_served(), "Filled cup can enter served lifecycle")
	check(not cup.add_relish(&"sugar") and cup.get_relish_counts() == before, "Served cups reject spoons without mutation")
	check(cup.mark_dirty(), "Served cup can enter dirty lifecycle")
	check(not cup.add_relish(&"condensed_milk") and cup.get_relish_counts() == before, "Dirty cups reject spoons without mutation")
	cup.assigned_order_id = &"past_order"
	check(cup.discard_contents() == 250.0, "Discard reports actual liquid volume")
	check(not cup.has_contents() and cup.get_relish_counts().is_empty(), "Discard clears every repeated ingredient")
	check(cup.state == Cup.CupState.DIRTY and cup.assigned_order_id == &"past_order", "Discard preserves cleanliness and order history")
	check(cup.discard_contents() == 0.0 and not cup.has_contents(), "Repeated discard cannot create liquid or ingredients")
	cup.reset_clean()
	check(cup.add_relish(&"sugar") and cup.has_contents(), "An ingredient-only cup is recognized as containing something")
	check(cup.discard_contents() == 0.0 and not cup.has_contents(), "Ingredient-only discard empties the cup without inventing liquid")
	check(cup.state == Cup.CupState.IN_USE, "Ingredient-only discard does not wash or replace the cup")
	check(cup.add_relish(&"condensed_milk"), "Emptied eligible cup accepts a new spoon")
	check(cup.receive_liquid(&"black_tea", 225.0, 70.0) == 225.0, "Refill uses the same cup after dry-ingredient disposal")
	check(cup.get_relish_counts() == {&"condensed_milk": 1} and cup.contents_base_id == &"black_tea", "Refill preserves only the new batch ingredients and brewed-liquid identity")
	cup.queue_free()
	await process_frame


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
