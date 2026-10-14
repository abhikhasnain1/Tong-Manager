class_name ServiceResult
extends RefCounted
## One recorded outcome. Matching and quality evidence share one review outcome.

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
		"response": &"accept" if accepted else &"refuse_retry", "remake_patience": &"continue",
		"cold_at_handoff": cold_at_handoff, "unhappy": cold_review,
		"bad_review": cold_review, "reason": reason,
		"served_kind": (&"cup" if request_kind == &"tea" else &"ready_item") if accepted else &"",
		"reasons": [&"cold_tea"] if cold_review else [], "served": {},
	}
	return result


static func create_evaluated(handoff_id: StringName, order: OrderState, evaluation: Dictionary) -> ServiceResult:
	if not OrderRequestDef.valid_identity(handoff_id) or order == null: return null
	if not evaluation.get("can_handoff", false) or not evaluation.get("served") is Dictionary: return null
	if (evaluation.get("order_id") != order.order_id or evaluation.get("customer_id") != order.customer_id
		or evaluation.get("request_id") != order.request_id): return null
	# Reassess the detached contents, preventing stale/edited flags from certifying
	# a different or already completed order. Live ownership is the command's job.
	var checked := ServiceEvaluation.evaluate(order, evaluation.served)
	if not checked.can_handoff: return null
	var reasons: Array = checked.reasons
	var policy := order.get_service_policy()
	var response: StringName = policy.unhappy_response if checked.bad_review else &"accept"
	var accepted := response == &"accept"
	var primary: StringName = reasons[0] if not reasons.is_empty() else (&"tea_served" if order.request_kind == &"tea" else &"ready_item_served")
	var result := ServiceResult.new()
	result._data = {
		"handoff_id": handoff_id, "order_id": order.order_id, "customer_id": order.customer_id,
		"request_kind": order.request_kind, "accepted": accepted, "fulfilled": accepted,
		"response": response, "remake_patience": policy.remake_patience,
		"cold_at_handoff": checked.cold_at_handoff, "unhappy": checked.bad_review,
		"bad_review": checked.bad_review, "reason": primary,
		"served_kind": checked.served_kind, "reasons": reasons.duplicate(),
		"served": (checked.served as Dictionary).duplicate(true),
	}
	return result


func get_snapshot() -> Dictionary:
	return _data.duplicate(true)
