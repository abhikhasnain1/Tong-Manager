class_name OrderState
extends RefCounted
## One authoritative order snapshot. Its owner supplies unique runtime IDs.

var _data: Dictionary = {}
var _results: Dictionary = {}
var _accepted_result: Dictionary = {}
var _terminal_result: Dictionary = {}

var order_id: StringName:
	get: return _data.get("order_id", &"")
	set(_value): pass
var customer_id: StringName:
	get: return _data.get("customer_id", &"")
	set(_value): pass
var request_id: StringName:
	get: return _data.get("request_id", &"")
	set(_value): pass
var request_kind: StringName:
	get: return _data.get("request_kind", &"")
	set(_value): pass
var recipe_id: StringName:
	get: return _data.get("recipe_id", &"")
	set(_value): pass
var item_id: StringName:
	get: return _data.get("item_id", &"")
	set(_value): pass
var created_time: float:
	get: return _data.get("created_time", 0.0)
	set(_value): pass
var fulfilled: bool:
	get: return not _accepted_result.is_empty()
	set(_value): pass
var closed: bool:
	get: return not _terminal_result.is_empty()
	set(_value): pass


static func create(order_identity: StringName, customer_identity: StringName, request: Dictionary, time: float, service_policy: Dictionary = {}) -> OrderState:
	if not OrderRequestDef.valid_identity(order_identity) or not OrderRequestDef.valid_identity(customer_identity): return null
	if not is_finite(time) or time < 0.0 or not _valid_request_snapshot(request): return null
	var policy := {"unhappy_response": &"accept", "remake_patience": &"continue"} if service_policy.is_empty() else service_policy.duplicate(true)
	if (policy.size() != 2 or policy.get("unhappy_response") not in [&"accept", &"refuse_leave", &"refuse_retry"]
		or policy.get("remake_patience") not in [&"continue", &"reset"]): return null
	var order := OrderState.new()
	order._data = {
		"order_id": order_identity, "customer_id": customer_identity,
		"request_id": request.id, "request_kind": request.kind,
		"recipe_id": request.recipe_id, "item_id": request.item_id,
		"created_time": time, "request": request.duplicate(true), "service_policy": policy,
	}
	return order


func record_result(result: ServiceResult) -> bool:
	if _data.is_empty() or result == null or closed: return false
	var data := result.get_snapshot()
	if data.is_empty() or data.order_id != order_id or data.customer_id != customer_id or data.request_kind != request_kind:
		return false
	if _results.has(data.handoff_id): return false
	_results[data.handoff_id] = data.duplicate(true)
	if data.accepted: _accepted_result = data.duplicate(true)
	if data.accepted or data.get("response") == &"refuse_leave": _terminal_result = data.duplicate(true)
	return true


func get_service_policy() -> Dictionary:
	return (_data.get("service_policy", {}) as Dictionary).duplicate(true)


func get_request() -> Dictionary:
	return (_data.get("request", {}) as Dictionary).duplicate(true)


func get_result(handoff_id: StringName) -> Dictionary:
	return (_results.get(handoff_id, {}) as Dictionary).duplicate(true)


func get_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for result: Dictionary in _results.values(): results.append(result.duplicate(true))
	return results


func get_accepted_result() -> Dictionary:
	return _accepted_result.duplicate(true)


func get_terminal_result() -> Dictionary:
	return _terminal_result.duplicate(true)


func get_snapshot() -> Dictionary:
	if _data.is_empty(): return {}
	var snapshot := _data.duplicate(true)
	snapshot["fulfilled"] = fulfilled
	snapshot["closed"] = closed
	snapshot["results"] = get_results()
	snapshot["accepted_result"] = get_accepted_result()
	snapshot["terminal_result"] = get_terminal_result()
	return snapshot


static func _valid_request_snapshot(request: Dictionary) -> bool:
	for key in ["id", "kind", "recipe_id", "item_id"]:
		if not request.has(key) or typeof(request[key]) not in [TYPE_STRING, TYPE_STRING_NAME]: return false
	if not OrderRequestDef.valid_identity(StringName(request.id)): return false
	if typeof(request.get("quantity")) != TYPE_INT or request.quantity != 1: return false
	if typeof(request.get("price")) != TYPE_INT or int(request.price) <= 0: return false
	if typeof(request.get("display_name_key")) != TYPE_STRING: return false
	if request.get("icon") != null and not request.get("icon") is Texture2D: return false
	match String(request.kind):
		"tea":
			return (OrderRequestDef.valid_identity(StringName(request.recipe_id))
				and String(request.item_id).is_empty() and request.get("unit") == &"cup"
				and _valid_tea_metadata(request))
		"ready_item":
			return OrderRequestDef.valid_identity(StringName(request.item_id)) and String(request.recipe_id).is_empty() and request.get("unit") == &"piece"
	return false


static func _valid_tea_metadata(request: Dictionary) -> bool:
	# Structural safety only; Catalog owns resource eligibility and unit identity.
	for key in ["output_item_id", "brewed_liquid_id"]:
		if not _valid_identity_value(request.get(key)): return false
	for key in ["base_item_ids", "relish_item_ids"]:
		if not _valid_item_list(request.get(key)): return false
	for key in ["kettle_portion_counts", "cup_portion_counts", "kettle_portion_units", "cup_portion_units"]:
		if not request.get(key) is Dictionary: return false
	if not _valid_portion_metadata(request.kettle_portion_counts, request.kettle_portion_units): return false
	if not _valid_portion_metadata(request.cup_portion_counts, request.cup_portion_units): return false
	if request.kettle_portion_counts.is_empty() or request.brewed_liquid_id not in request.base_item_ids: return false
	if typeof(request.get("batch_requires_boiling_water")) != TYPE_BOOL: return false
	if request.batch_requires_boiling_water and &"water" not in request.base_item_ids: return false
	for ingredient in request.kettle_portion_counts:
		if ingredient not in request.base_item_ids: return false
	for ingredient in request.base_item_ids:
		if ingredient != &"water" and not request.kettle_portion_counts.has(ingredient): return false
	for ingredient in request.cup_portion_counts:
		if ingredient not in request.relish_item_ids: return false
	for ingredient in request.relish_item_ids:
		if not request.cup_portion_counts.has(ingredient): return false
	for key in ["minimum_serving_volume_ml", "target_serving_volume_ml", "max_batch_volume_ml"]:
		if typeof(request.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(request[key])): return false
	return (request.minimum_serving_volume_ml > 0.0
		and request.minimum_serving_volume_ml <= request.target_serving_volume_ml
		and request.target_serving_volume_ml <= request.max_batch_volume_ml)


static func _valid_identity_value(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and OrderRequestDef.valid_identity(StringName(value))


static func _valid_item_list(value: Variant) -> bool:
	if not value is Array: return false
	var seen: Dictionary = {}
	for item in value:
		if not _valid_identity_value(item) or seen.has(item): return false
		seen[item] = true
	return true


static func _valid_portion_metadata(counts: Dictionary, units: Dictionary) -> bool:
	if counts.size() != units.size(): return false
	for ingredient in counts:
		if not _valid_identity_value(ingredient) or not units.has(ingredient): return false
		if typeof(counts[ingredient]) != TYPE_INT or counts[ingredient] <= 0: return false
		if not _valid_identity_value(units[ingredient]): return false
	return true
