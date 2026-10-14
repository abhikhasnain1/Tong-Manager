class_name ServiceEvaluation
extends RefCounted
## Pure handoff assessment. Recipe/quality differences become review evidence,
## never a reason to retain a physically valid offered drink or ready piece.

const AMOUNT_EPSILON := 0.000001
const BREW_STATES: Array[StringName] = [&"water", &"underbrewed", &"ready", &"oversteeped"]


static func evaluate(order: OrderState, offered: Dictionary) -> Dictionary:
	var result := {
		"can_handoff": false, "failure_reason": &"invalid_order",
		"order_id": &"", "customer_id": &"", "request_id": &"",
		"requested_kind": &"", "served_kind": &"", "reasons": [],
		"bad_review": false, "cold_at_handoff": false, "served": {},
	}
	if order == null or order.get_request().is_empty(): return result
	result.order_id = order.order_id
	result.customer_id = order.customer_id
	result.request_id = order.request_id
	result.requested_kind = order.request_kind
	if order.fulfilled:
		result.failure_reason = &"order_fulfilled"
		return result
	var normalized := _normalize_offer(offered)
	result.failure_reason = normalized.failure_reason
	if not normalized.valid: return result
	var served: Dictionary = normalized.served
	var request := order.get_request()
	var reasons: Array[StringName] = []
	result.served_kind = served.kind
	result.served = served
	if served.kind == &"ready_item":
		if order.request_kind != &"ready_item":
			reasons.append(&"wrong_item_kind")
		elif served.item_id != request.item_id:
			reasons.append(&"wrong_item")
	else:
		if order.request_kind != &"tea":
			reasons.append(&"wrong_item_kind")
		else:
			if served.liquid_id != request.brewed_liquid_id: reasons.append(&"wrong_liquid")
			if served.volume + AMOUNT_EPSILON < request.minimum_serving_volume_ml:
				reasons.append(&"insufficient_volume")
			if not _amounts_match(_cup_recipe_amounts(served, request), request.cup_portion_counts):
				reasons.append(&"wrong_ingredients")
		_append_brew_reasons(served, request, reasons)
		result.cold_at_handoff = (served.volume > 0.0 and served.liquid_id != &"water"
			and served.temperature <= served.cold_threshold)
		if result.cold_at_handoff: reasons.append(&"cold_tea")
	result.can_handoff = true
	result.failure_reason = &""
	result.reasons = reasons
	result.bad_review = not reasons.is_empty()
	return result


static func _normalize_offer(offered: Dictionary) -> Dictionary:
	var invalid := {"valid": false, "failure_reason": &"invalid_offer", "served": {}}
	if offered.get("kind") == &"ready_item":
		if not _identity(offered.get("item_id")) or offered.get("unit") != &"piece": return invalid
		if typeof(offered.get("quantity")) != TYPE_INT or offered.quantity != 1: return invalid
		return {"valid": true, "failure_reason": &"", "served": {
			"kind": &"ready_item", "item_id": StringName(offered.item_id),
			"unit": &"piece", "quantity": 1,
		}}
	if offered.get("kind") != &"cup": return invalid
	if offered.get("lifecycle") in [&"served", &"dirty"]:
		invalid.failure_reason = &"cup_unavailable"
		return invalid
	if offered.get("lifecycle") not in [&"clean", &"in_use", &"filled"]: return invalid
	for field in ["volume", "capacity", "temperature", "cold_threshold"]:
		if not _finite_number(offered.get(field)): return invalid
	if offered.capacity <= 0.0 or offered.volume < 0.0 or offered.volume > offered.capacity: return invalid
	if typeof(offered.get("liquid_id")) not in [TYPE_STRING, TYPE_STRING_NAME]: return invalid
	if offered.volume > 0.0 and not _identity(offered.liquid_id): return invalid
	if not _valid_amounts(offered.get("ingredient_amounts"), false): return invalid
	var amounts := _copy_amounts(offered.ingredient_amounts)
	if not _valid_amounts(offered.get("inherited_ingredient_amounts", {}), false): return invalid
	var inherited := _copy_amounts(offered.get("inherited_ingredient_amounts", {}))
	for item in inherited:
		if float(inherited[item]) > float(amounts.get(item, 0.0)): return invalid
	if offered.volume == 0.0 and amounts.is_empty():
		invalid.failure_reason = &"empty_cup"
		return invalid
	var batches: Array[Dictionary] = []
	var complete := typeof(offered.get("brew_history_complete", true)) == TYPE_BOOL and bool(offered.get("brew_history_complete", true))
	var incoming: Variant = offered.get("brew_batches", [])
	if incoming is Array:
		for candidate: Variant in incoming:
			if not _valid_batch(candidate):
				complete = false
				continue
			var batch := {
				"state": StringName(candidate.state),
				"infused_counts": _copy_amounts(candidate.infused_counts, true),
				"mixed_counts": _copy_amounts(candidate.get("mixed_counts", {})),
				"used_boiling_water": candidate.used_boiling_water,
				"batch_volume": float(candidate.batch_volume),
			}
			if batch not in batches: batches.append(batch)
	else:
		complete = false
	return {"valid": true, "failure_reason": &"", "served": {
		"kind": &"cup", "lifecycle": StringName(offered.lifecycle),
		"volume": float(offered.volume), "capacity": float(offered.capacity),
		"liquid_id": StringName(offered.liquid_id), "temperature": float(offered.temperature),
		"cold_threshold": float(offered.cold_threshold), "ingredient_amounts": amounts,
		"inherited_ingredient_amounts": inherited,
		"brew_batches": batches, "brew_history_complete": complete,
	}}


static func _append_brew_reasons(served: Dictionary, request: Dictionary, reasons: Array[StringName]) -> void:
	if served.volume <= 0.0: return
	var known_water: bool = served.liquid_id == &"water"
	var unknown: bool = not served.brew_history_complete or (served.brew_batches.is_empty() and not known_water)
	var underbrewed := false
	var oversteeped := false
	var wrong_counts := false
	var not_boiled := false
	var oversized := false
	for batch: Dictionary in served.brew_batches:
		underbrewed = underbrewed or batch.state == &"underbrewed"
		oversteeped = oversteeped or batch.state == &"oversteeped"
		if request.kind == &"tea":
			var batch_counts: Dictionary = batch.infused_counts.duplicate()
			for item in batch.mixed_counts:
				batch_counts[item] = float(batch_counts.get(item, 0.0)) + float(batch.mixed_counts[item])
			wrong_counts = wrong_counts or not _amounts_match(batch_counts, request.kettle_portion_counts)
			not_boiled = not_boiled or (request.batch_requires_boiling_water and not batch.used_boiling_water)
			oversized = oversized or batch.batch_volume > request.max_batch_volume_ml + AMOUNT_EPSILON
	if unknown: reasons.append(&"unknown_brew")
	if underbrewed: reasons.append(&"underbrewed")
	if oversteeped: reasons.append(&"oversteeped")
	if wrong_counts: reasons.append(&"wrong_brew_ingredients")
	if not_boiled: reasons.append(&"not_boiled")
	if oversized: reasons.append(&"oversized_batch")


static func _amounts_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for item in expected:
		if not actual.has(item) or absf(float(actual[item]) - float(expected[item])) > AMOUNT_EPSILON: return false
	return true


static func _cup_recipe_amounts(served: Dictionary, request: Dictionary) -> Dictionary:
	var amounts: Dictionary = served.ingredient_amounts.duplicate()
	# A requested batch addition travels with the liquid in fractional portions;
	# its original dose was assessed above, not as a fresh full spoon in every cup.
	# Direct additions of that same item still count toward the cup recipe.
	for item in served.inherited_ingredient_amounts:
		if not request.kettle_portion_counts.has(item): continue
		var direct := float(amounts.get(item, 0.0)) - float(served.inherited_ingredient_amounts[item])
		if direct > 0.0:
			amounts[item] = direct
		else:
			amounts.erase(item)
	return amounts


static func _valid_batch(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _identity(value.get("state")): return false
	if StringName(value.state) not in BREW_STATES or typeof(value.get("used_boiling_water")) != TYPE_BOOL: return false
	if not _valid_amounts(value.get("infused_counts"), true): return false
	if not _valid_amounts(value.get("mixed_counts", {}), false): return false
	if not _finite_number(value.get("batch_volume")) or value.batch_volume <= 0.0: return false
	return value.state != &"water" or value.infused_counts.is_empty()


static func _valid_amounts(value: Variant, integers_only: bool) -> bool:
	if not value is Dictionary: return false
	for item in value:
		if not _identity(item) or not _finite_number(value[item]) or value[item] < 0.0: return false
		if integers_only and (typeof(value[item]) != TYPE_INT or value[item] == 0): return false
	return true


static func _copy_amounts(value: Dictionary, integers_only := false) -> Dictionary:
	var result: Dictionary = {}
	for item in value:
		if value[item] == 0: continue
		result[StringName(item)] = int(value[item]) if integers_only else float(value[item])
	return result


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _identity(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and OrderRequestDef.valid_identity(StringName(value))
