class_name IngredientPolicy
extends Resource
## Shared by physical and pantry input. Recipe doses never cap player actions.

const KETTLE_STAGES: Array[StringName] = [&"empty", &"water", &"heating", &"boiling", &"steeping", &"liquor_ready", &"oversteeped"]
const CUP_STAGES: Array[StringName] = [&"clean", &"in_use", &"filled", &"served", &"dirty"]
@export var rules: Array[IngredientRule] = []


func configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen: Dictionary = {}
	for index in rules.size():
		var rule := rules[index]
		if rule == null:
			errors.append("Rule %d is empty" % index)
			continue
		if not rule.enabled:
			continue
		var key := "%s/%s" % [rule.item_id, rule.vessel_kind]
		if seen.has(key): errors.append("Duplicate rule: " + key)
		seen[key] = true
		if rule.item_id.is_empty() or rule.unit.is_empty() or rule.quantity <= 0:
			errors.append(key + ": provide an item, unit and positive drop quantity")
		if rule.vessel_kind not in ["kettle", "cup"]:
			errors.append(key + ": unsupported vessel")
		if rule.effect not in ["mix", "infuse"] or (rule.effect == "infuse" and (rule.vessel_kind != "kettle" or rule.output_liquid_id.is_empty())):
			errors.append(key + ": infusion requires a kettle and an output liquid; cups support mix")
		if rule.effect == "mix" and (not rule.output_liquid_id.is_empty() or rule.restart_steeping):
			errors.append(key + ": mixing does not choose a liquid or restart brewing")
		if rule.max_portions < -1 or not is_finite(rule.minimum_volume_ml) or rule.minimum_volume_ml < 0:
			errors.append(key + ": invalid count or minimum volume")
		if not is_finite(rule.max_batch_volume_ml) or (rule.max_batch_volume_ml < 0 and rule.max_batch_volume_ml != -1):
			errors.append(key + ": maximum batch volume must be -1 or nonnegative")
		if (not is_finite(rule.minimum_temperature) or not is_finite(rule.maximum_temperature)
			or rule.minimum_temperature > rule.maximum_temperature):
			errors.append(key + ": invalid temperature range")
		var stages := KETTLE_STAGES if rule.vessel_kind == "kettle" else CUP_STAGES
		for stage in rule.allowed_stages:
			if stage not in stages: errors.append(key + ": unknown stage " + String(stage))
		for liquid in rule.allowed_liquid_ids:
			if liquid.is_empty(): errors.append(key + ": empty liquid identifier")
	return errors


func rule_for(item_id: StringName, target: Node2D) -> IngredientRule:
	var kind := "kettle" if target is Kettle else ("cup" if target is Cup else "")
	for rule in rules:
		if rule != null and rule.enabled and rule.item_id == item_id and rule.vessel_kind == kind:
			return rule
	return null


func validate(item_id: StringName, unit: StringName, quantity: int, target: Node2D) -> DropValidation:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		return DropValidation.invalid("Ingredient target is unavailable")
	var errors := configuration_errors()
	if not errors.is_empty():
		return DropValidation.invalid("Ingredient configuration: " + errors[0])
	var rule := rule_for(item_id, target)
	if rule == null:
		return DropValidation.invalid("This ingredient is not permitted in this vessel")
	if quantity <= 0 or quantity != rule.quantity or unit != rule.unit:
		return DropValidation.invalid("Use the configured portion unit and quantity")
	if target.call("get_ingredient_stage") not in rule.allowed_stages:
		return DropValidation.invalid("This ingredient is not permitted at this stage")
	var volume: float = target.get("volume_ml")
	var temperature: float = target.get("temperature")
	var config: BrewingConfig = target.get("config")
	if config == null:
		return DropValidation.invalid("This vessel has no brewing configuration")
	if not is_finite(volume) or volume < 0 or not is_finite(temperature):
		return DropValidation.invalid("This vessel has invalid contents")
	if volume < rule.minimum_volume_ml or (volume <= 0 and not rule.allow_empty):
		return DropValidation.invalid("Add the required liquid first")
	if (temperature < rule.minimum_temperature or temperature > rule.maximum_temperature
		or (rule.requires_boiling and temperature < config.boiling_temperature)):
		return DropValidation.invalid("This ingredient needs a different liquid temperature")
	var liquid: StringName
	if target is Kettle:
		var kettle := target as Kettle
		if kettle.tool_def == null:
			return DropValidation.invalid("This kettle has no capacity configuration")
		liquid = kettle.brewed_liquid_id if kettle.contains_tea else &"water"
		if (volume > float(kettle.tool_def.kettle_capacity_ml)
			or (rule.max_batch_volume_ml >= 0 and volume > rule.max_batch_volume_ml)):
			return DropValidation.invalid("This batch exceeds its water allowance")
		if kettle.is_pouring: return DropValidation.invalid("Finish pouring first")
	else:
		var cup := target as Cup
		liquid = cup.liquid_type
		if (not is_finite(cup.capacity_ml) or cup.capacity_ml <= 0 or volume > cup.capacity_ml
			or cup.contents_base_id != cup.liquid_type or (volume <= 0 and not liquid.is_empty())):
			return DropValidation.invalid("This cup has invalid contents")
	if volume > 0 and not rule.allowed_liquid_ids.is_empty() and liquid not in rule.allowed_liquid_ids:
		return DropValidation.invalid("This ingredient is not permitted in this liquid")
	var amounts: Dictionary[StringName, float] = target.call("get_ingredient_amounts")
	var existing: float = amounts.get(item_id, 0.0)
	if (not is_finite(existing) or existing < 0 or (not rule.allow_repeated and existing > 0)
		or (rule.max_portions >= 0 and existing + quantity > rule.max_portions + 0.000001)):
		return DropValidation.invalid("This vessel has reached the ingredient limit")
	if not target.call("can_apply_ingredient", item_id, quantity, StringName(rule.effect), rule.output_liquid_id):
		return DropValidation.invalid("This ingredient effect is incompatible with the contents")
	return DropValidation.valid()


func apply(item_id: StringName, unit: StringName, quantity: int, target: Node2D) -> bool:
	if not validate(item_id, unit, quantity, target).is_valid:
		return false
	var rule := rule_for(item_id, target)
	return target.call("apply_ingredient", item_id, quantity, StringName(rule.effect), rule.output_liquid_id, rule.restart_steeping)
