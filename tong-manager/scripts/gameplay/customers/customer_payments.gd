class_name CustomerPayments
extends Node
## Run-owned accepted receipts survive the serving scene. Presentation is optional.

signal payment_recorded(transaction: Dictionary, screen_id: int, origin: Vector2)

var finance: FinanceState
var _pending: Array[Dictionary] = []
var _queued_ids: Dictionary = {}
var _scheduled := false
var _binding := 0


func _init() -> void:
	set_process(false)


func configure(value: FinanceState) -> void:
	if finance == value: return
	finance = value
	_binding += 1
	_pending.clear()
	_queued_ids.clear()
	set_process(false)


func enqueue_accepted(service: CustomerService, receipt: Dictionary, origin: Vector2) -> bool:
	if (finance == null or not finance.initialized or not is_inside_tree()
		or not is_instance_valid(service) or not is_instance_valid(service.screen)): return false
	# Accept only the service owner's already committed copy, never a caller's
	# edited price/result or an arbitrary emission of its presentation signal.
	if receipt not in service.get_records() or receipt.get("payment_generation", -1) != finance.generation: return false
	var result: Dictionary = receipt.get("result", {})
	var request: Dictionary = receipt.get("request", {})
	if (not result.get("accepted", false) or not result.get("fulfilled", false)
		or typeof(receipt.get("price")) != TYPE_INT or receipt.price <= 0
		or receipt.price != request.get("price")
		or result.get("handoff_id") != receipt.get("handoff_id")
		or result.get("order_id") != receipt.get("order_id")
		or result.get("customer_id") != receipt.get("customer_id")): return false
	for field in ["order_id", "handoff_id", "customer_id"]:
		if not OrderRequestDef.valid_identity(receipt.get(field, &"")): return false
	var source_id := StringName("order:" + String(receipt.order_id))
	var alias := StringName("handoff:" + String(receipt.handoff_id))
	var key := "%s:%s" % [finance.generation, source_id]
	var alias_key := "%s:%s" % [finance.generation, alias]
	if (_queued_ids.has(key) or _queued_ids.has(alias_key)
		or not finance.get_transaction(source_id).is_empty()
		or not finance.get_transaction(alias).is_empty()): return false
	_queued_ids[key] = true
	_queued_ids[alias_key] = true
	# Only detached financial facts enter the ledger, not textures or live nodes.
	var metadata := {"handoff_id": receipt.handoff_id, "order_id": receipt.order_id,
		"customer_id": receipt.customer_id, "request_id": request.get("id", &""),
		"request_kind": result.get("request_kind", &""), "served_kind": result.get("served_kind", &""),
		"bad_review": bool(result.get("bad_review", false)),
		"reasons": result.get("reasons", []).duplicate(), "served_cup_id": receipt.get("served_cup_id", 0)}
	_pending.append({"source_id": source_id, "alias": alias, "amount": receipt.price,
		"metadata": metadata, "generation": finance.generation, "binding": _binding,
		"screen_id": service.screen.get_instance_id(), "origin": origin if origin.is_finite() else Vector2.ZERO, "keys": [key, alias_key]})
	if not _scheduled:
		_scheduled = true
		_flush.call_deferred()
	return true


func _flush() -> void:
	_scheduled = false
	if finance != null and finance.is_committing():
		# A synchronous observer may ask to flush while a prior ledger write is
		# publishing. Retry on a later frame, rather than lose an accepted sale.
		set_process(true)
		return
	set_process(false)
	var receipts := _pending
	_pending = []
	var owner_ref: WeakRef = weakref(self)
	for receipt in receipts:
		for key in receipt["keys"]: _queued_ids.erase(key)
		# An explicit new-demo reset cannot import a sale from the previous run.
		if finance == null or receipt.binding != _binding or receipt.generation != finance.generation: continue
		var ledger := finance
		var committed := ledger.record_income(receipt.source_id, receipt.amount, receipt.metadata, [receipt.alias])
		if owner_ref.get_ref() == null: return
		if not committed or ledger != finance or receipt.binding != _binding or receipt.generation != ledger.generation: continue
		payment_recorded.emit(ledger.get_transaction(receipt.source_id), receipt.screen_id, receipt.origin)
		if owner_ref.get_ref() == null: return


func _process(_delta: float) -> void:
	if finance == null or not finance.is_committing(): _flush()


func get_pending_count() -> int:
	return _pending.size()
