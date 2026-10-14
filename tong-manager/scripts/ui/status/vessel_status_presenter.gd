class_name VesselStatusPresenter
extends RefCounted
## Fresh read-only presentation snapshots. Ingredients and beverage identity are distinct.


static func snapshot(vessel: Node, catalog: Node, config: StatusMarkerConfig) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(vessel) or vessel.is_queued_for_deletion() or not (vessel is Cup or vessel is Kettle):
		return result
	var settings := config if config != null else StatusMarkerConfig.new()
	var is_kettle := vessel is Kettle
	var amounts: Dictionary = vessel.get_ingredient_amounts()
	var volume: float = vessel.volume_ml
	var capacity: float = float(vessel.tool_def.kettle_capacity_ml) if is_kettle else vessel.capacity_ml
	var liquid_id: StringName = vessel.brewed_liquid_id if is_kettle else vessel.liquid_type
	if is_kettle and volume > 0.0 and liquid_id.is_empty():
		liquid_id = &"water"
	if volume <= 0.0:
		liquid_id = &""
	var ratio := clampf(volume / capacity, 0.0, 1.0) if capacity > 0.0 and is_finite(capacity) and is_finite(volume) else 0.0
	var fill_band: StringName = &"empty"
	if volume > 0.0:
		fill_band = &"low" if ratio <= settings.low_fill_limit else (&"full" if ratio >= settings.high_fill_start else &"half")
	var fill_label: String = {&"empty": "Empty", &"low": "A little left", &"half": "Partly filled", &"full": "Nearly full"}[fill_band]
	if fill_band == &"empty" and not amounts.is_empty():
		fill_label = "No liquid"
	var liquid_label := _liquid_label(liquid_id, catalog)
	var fill := _token(&"fill", &"fill", fill_label, fill_label + (" · " + liquid_label if not liquid_label.is_empty() else ""))
	fill.merge({"band": fill_band, "fill_ratio": ratio, "liquid_id": liquid_id, "liquid_label": liquid_label})
	result.append(fill)
	if volume > 0.0 and is_finite(vessel.temperature):
		var cold_limit: float = vessel.config.cold_temperature
		var thermal_band: StringName = &"cool" if vessel.temperature <= cold_limit else (&"hot" if vessel.temperature >= maxf(settings.hot_temperature, cold_limit) else &"warm")
		var thermal_label: String = {&"cool": "Cool", &"warm": "Warm", &"hot": "Hot"}[thermal_band]
		var thermal := _token(&"thermal", &"thermal", thermal_label, thermal_label + " contents")
		thermal["band"] = thermal_band
		result.append(thermal)
	if is_kettle:
		_append_kettle_state(result, vessel)
	_append_ingredients(result, amounts, catalog)
	if vessel is Cup:
		var band: StringName = &"dirty" if vessel.state == Cup.CupState.DIRTY else (&"served" if vessel.state == Cup.CupState.SERVED else &"clean")
		var label: String = {&"dirty": "Needs washing", &"served": "Used cup", &"clean": "Clean cup"}[band]
		var cleanliness := _token(&"cleanliness", &"cleanliness", label, label)
		cleanliness.merge({"band": band, "lifecycle": vessel.get_ingredient_stage()})
		result.append(cleanliness)
	return result


static func _append_kettle_state(result: Array[Dictionary], kettle: Kettle) -> void:
	var stage := kettle.get_ingredient_stage()
	var labels := {&"heating": "Water heating", &"boiling": "Water bubbling", &"steeping": "Steeping", &"liquor_ready": "Brewed", &"oversteeped": "Oversteeped"}
	if labels.has(stage) and kettle.volume_ml > 0.0:
		var brew := _token(&"brew", &"brew", labels[stage], labels[stage])
		brew["band"] = stage
		result.append(brew)
	var burner := kettle.current_burner as Burner
	if is_instance_valid(burner) and not burner.is_queued_for_deletion() and burner.seated_kettle == kettle and burner.heat_level > 0 and not kettle.is_held and not kettle.is_pouring:
		var band: StringName = &"low" if burner.heat_level == 1 else (&"medium" if burner.heat_level == 2 else &"high")
		var label: String = {&"low": "Gentle heat", &"medium": "Medium heat", &"high": "High heat"}[band]
		var heating := _token(&"heating", &"heating", label, "Burner on · " + label.to_lower())
		heating["band"] = band
		result.append(heating)


static func _append_ingredients(result: Array[Dictionary], amounts: Dictionary, catalog: Node) -> void:
	var ingredients: Array[Dictionary] = []
	for raw_id in amounts:
		var item_id := StringName(raw_id)
		var amount := float(amounts[raw_id])
		if item_id.is_empty() or not is_finite(amount) or amount <= 0.0:
			continue
		var item := _item(catalog, item_id)
		var label := item.get_portion_label() if item != null else String(item_id).replace("_", " ").capitalize()
		var unit: StringName = item.unit if item != null else &"portion"
		var text := amount_text(amount)
		var unit_text := String(unit) if is_equal_approx(amount, 1.0) else String(unit) + "s"
		var token := _token(StringName("ingredient:" + String(item_id)), &"ingredient", label, "%s · %s %s" % [label, str(amount), unit_text])
		token.merge({"item_id": item_id, "amount": amount, "amount_text": text, "unit": unit, "icon": item.icon if item != null else null, "pantry_order": item.pantry_order if item != null else 2147483647}, true)
		ingredients.append(token)
	ingredients.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.pantry_order != b.pantry_order:
			return a.pantry_order < b.pantry_order
		return String(a.item_id) < String(b.item_id))
	result.append_array(ingredients)


static func amount_text(amount: float) -> String:
	# Never cap a count or turn a positive inherited trace into a zero marker.
	if not is_finite(amount) or amount <= 0.0:
		return "0"
	var whole := floorf(amount)
	var fraction := amount - whole
	if fraction == 0.0:
		return String.num(amount, 0)
	for entry in [[0.25, "¼"], [0.5, "½"], [0.75, "¾"]]:
		if absf(fraction - float(entry[0])) < 0.00000001:
			return (String.num(whole, 0) if whole > 0.0 else "") + String(entry[1])
	if amount < 0.01:
		return "<0.01"
	var rounded := snappedf(amount, 0.01)
	var text := String.num(rounded, 2)
	return ("≈" if absf(amount - rounded) > 0.00000001 else "") + text


static func _item(catalog: Node, item_id: StringName) -> ItemDef:
	if not is_instance_valid(catalog) or catalog.is_queued_for_deletion():
		return null
	var items: Variant = catalog.get("items")
	return items.get(item_id) as ItemDef if items is Dictionary else null


static func _liquid_label(item_id: StringName, catalog: Node) -> String:
	if item_id.is_empty():
		return ""
	if item_id == &"water":
		return "Water"
	var item := _item(catalog, item_id)
	return item.get_portion_label() if item != null else String(item_id).replace("_", " ").capitalize()


static func _token(key: StringName, kind: StringName, label: String, description: String) -> Dictionary:
	return {"key": key, "kind": kind, "label": label, "description": description, "icon": null}
