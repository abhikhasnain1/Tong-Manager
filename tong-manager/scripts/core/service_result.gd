class_name ServiceResult
extends RefCounted
## A recorded outcome supplied by a consumer, not a cup or payload evaluator.

var _data: Dictionary = {}


static func create(
	handoff_id: StringName,
	order_id: StringName,
	customer_id: StringName,
	request_kind: StringName,
	accepted: bool,
	cold_at_handoff := false,
	rejection_reason: StringName = &""
) -> ServiceResult:
	for identity in [handoff_id, order_id, customer_id]:
		if not OrderRequestDef.valid_identity(identity): return null
	if request_kind not in [&"tea", &"ready_item"]: return null
	if cold_at_handoff and request_kind != &"tea": return null
	if accepted and not rejection_reason.is_empty(): return null
	if not accepted and not OrderRequestDef.valid_identity(rejection_reason): return null
	var cold_review := accepted and request_kind == &"tea" and cold_at_handoff
	var reason := rejection_reason
	if accepted:
		reason = &"cold_tea" if cold_review else (&"tea_served" if request_kind == &"tea" else &"ready_item_served")
	var result := ServiceResult.new()
	result._data = {
		"handoff_id": handoff_id, "order_id": order_id, "customer_id": customer_id,
		"request_kind": request_kind, "accepted": accepted, "fulfilled": accepted,
		"cold_at_handoff": cold_at_handoff, "unhappy": cold_review,
		"bad_review": cold_review, "reason": reason,
	}
	return result


func get_snapshot() -> Dictionary:
	return _data.duplicate(true)
