class_name IngredientPolicy
extends Resource

@export var rules: Array[IngredientRule] = []


func rule_for(item_id: StringName, target: Node2D) -> IngredientRule:
	var kind := "kettle" if target is Kettle else ("cup" if target is Cup else "")
	for rule in rules:
		if rule != null and rule.item_id == item_id and rule.vessel_kind == kind:
			return rule
	return null


func validate(item_id: StringName, unit: StringName, quantity: int, target: Node2D) -> DropValidation:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		return DropValidation.invalid("Ingredient target is unavailable")
	var rule := rule_for(item_id, target)
	if rule == null:
		return DropValidation.invalid("Use a teabag in the kettle, or sugar and milk in a cup")
	if rule.quantity != 1 or quantity != rule.quantity or unit != rule.unit:
		return DropValidation.invalid("Use one matching portion at a time")
	if target is Kettle:
		var kettle := target as Kettle
		if kettle.contains_tea:
			return DropValidation.invalid("This kettle already contains a teabag")
		if not is_finite(kettle.volume_ml) or kettle.volume_ml <= 0.0:
			return DropValidation.invalid("Fill the kettle with water first")
		if (not is_finite(rule.max_batch_volume_ml) or rule.max_batch_volume_ml <= 0.0
			or kettle.volume_ml > minf(rule.max_batch_volume_ml, float(kettle.tool_def.kettle_capacity_ml))):
			return DropValidation.invalid("This batch exceeds the teabag's water allowance")
		if not is_finite(kettle.temperature) or (rule.requires_boiling and kettle.temperature < kettle.config.boiling_temperature):
			return DropValidation.invalid("Wait for the water to boil")
		return DropValidation.invalid("Finish pouring first") if kettle.is_pouring else DropValidation.valid()
	var cup := target as Cup
	if not cup.can_accept_relish(item_id):
		return DropValidation.invalid("Use an unserved, clean cup")
	if (not is_finite(cup.volume_ml) or not is_finite(cup.capacity_ml) or not is_finite(cup.temperature)
		or cup.capacity_ml <= 0.0 or cup.volume_ml < 0.0 or cup.volume_ml > cup.capacity_ml):
		return DropValidation.invalid("This cup has invalid contents")
	if cup.volume_ml <= 0.0:
		if not rule.allow_empty:
			return DropValidation.invalid("Pour tea into this cup first")
		if not cup.liquid_type.is_empty() or not cup.contents_base_id.is_empty():
			return DropValidation.invalid("Empty this cup before adding ingredients")
	elif cup.liquid_type != rule.allowed_liquid_id or cup.contents_base_id != rule.allowed_liquid_id:
		return DropValidation.invalid("Add this ingredient to tea, or to an empty cup")
	if not rule.allow_repeated and cup.relish_item_ids.has(item_id):
		return DropValidation.invalid("This cup already has that ingredient")
	# Spoonfuls are abstract portions. They do not occupy liquid capacity, so a
	# full tea cup can receive them without changing volume or temperature.
	return DropValidation.valid()
