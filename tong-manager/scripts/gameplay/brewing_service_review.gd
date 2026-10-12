class_name BrewingServiceReview
extends RefCounted

# A deterministic outcome seam; callers own orders and vessel mutation.
# This does not consume stock, pay money or implement a reputation economy.
var _accepted_results: Dictionary = {}

func inspect(
	order_id: StringName,
	cup: Dictionary,
	minimum_volume_ml: float = 150.0,
	expected_recipe_id: StringName = &"black_tea"
) -> Dictionary:
	if order_id.is_empty():
		return _rejected(order_id, &"missing_order")
	if _accepted_results.has(order_id):
		return _rejected(order_id, &"already_served")
	if not bool(cup.get("available", false)):
		return _rejected(order_id, &"cup_unavailable")
	if not bool(cup.get("clean", false)):
		return _rejected(order_id, &"dirty_cup")
	if StringName(cup.get("recipe_id", &"")) != expected_recipe_id or int(cup.get("garnish_count", 0)) != 0:
		return _rejected(order_id, &"wrong_recipe")
	var amount := float(cup.get("volume_ml", 0.0))
	if not is_finite(amount) or not is_finite(minimum_volume_ml) or minimum_volume_ml <= 0.0:
		return _rejected(order_id, &"invalid_volume")
	if amount < minimum_volume_ml:
		return _rejected(order_id, &"too_little_tea")
	var temperature := float(cup.get("temperature", NAN))
	var threshold := float(cup.get("cold_threshold", NAN))
	if not is_finite(temperature) or not is_finite(threshold):
		return _rejected(order_id, &"invalid_temperature")
	var cold := temperature <= threshold
	return {
		"order_id": order_id, "accepted": true, "fulfilled": true,
		"cold": cold, "unhappy": cold, "bad_review": cold,
		"reason": &"cold_tea" if cold else &"warm_tea",
		"temperature": temperature,
	}

func accept(
	order_id: StringName,
	cup: Dictionary,
	minimum_volume_ml: float = 150.0,
	expected_recipe_id: StringName = &"black_tea"
) -> Dictionary:
	var result := inspect(order_id, cup, minimum_volume_ml, expected_recipe_id)
	if bool(result.accepted):
		_accepted_results[order_id] = result.duplicate(true)
	return result

func accepted_result(order_id: StringName) -> Dictionary:
	return (_accepted_results.get(order_id, {}) as Dictionary).duplicate(true)

func accepted_count() -> int:
	return _accepted_results.size()

func bad_review_count() -> int:
	var count := 0
	for result: Dictionary in _accepted_results.values():
		if bool(result.bad_review):
			count += 1
	return count

func _rejected(order_id: StringName, reason: StringName) -> Dictionary:
	return {
		"order_id": order_id, "accepted": false, "fulfilled": false,
		"cold": false, "unhappy": false, "bad_review": false, "reason": reason,
	}
