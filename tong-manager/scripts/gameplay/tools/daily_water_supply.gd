class_name DailyWaterSupply
extends RefCounted

signal remaining_changed(amount_ml: float)

var day_id: int = -1
var remaining_ml: float = 0.0
var _next_token: int = 1
var _pending: Dictionary = {}
var _transferring := false


func begin_day(next_day_id: int, allocation_ml: float) -> bool:
	if _transferring or next_day_id < 0 or next_day_id <= day_id:
		return false
	if not is_finite(allocation_ml) or allocation_ml < 0.0:
		return false
	day_id = next_day_id
	remaining_ml = allocation_ml
	_pending.clear()
	remaining_changed.emit(remaining_ml)
	return true


func reserve_transfer(source: Node) -> int:
	if _transferring or day_id < 0 or remaining_ml <= 0.0 or not _live(source):
		return 0
	var token := _next_token
	_next_token += 1
	_pending[token] = {"day_id": day_id, "source": weakref(source)}
	return token


func cancel_transfer(token: int) -> void:
	_pending.erase(token)


func can_fill(token: int, kettle: Node) -> bool:
	if _transferring or not _pending.has(token) or not _live(kettle) or not kettle is Kettle:
		return false
	var reservation: Dictionary = _pending[token]
	var source: Node = (reservation.source as WeakRef).get_ref() as Node
	if reservation.day_id != day_id or not _live(source) or remaining_ml <= 0.0:
		return false
	var receiver := kettle as Kettle
	return (
		not receiver.contains_tea and not receiver.is_pouring and not receiver.is_held
		and is_finite(receiver.volume_ml) and receiver.volume_ml >= 0.0
		and receiver.tool_def != null and receiver.tool_def.kettle_capacity_ml > receiver.volume_ml
	)


func fill_kettle(token: int, kettle: Node) -> float:
	if not can_fill(token, kettle):
		return 0.0
	var receiver := kettle as Kettle
	var requested := minf(remaining_ml, float(receiver.tool_def.kettle_capacity_ml) - receiver.volume_ml)
	# Claim before add_water emits state signals: retries/reentrant callbacks cannot spend twice.
	_pending.erase(token)
	_transferring = true
	remaining_ml -= requested
	var accepted := receiver.add_water(requested)
	remaining_ml += requested - accepted
	_transferring = false
	remaining_changed.emit(remaining_ml)
	return accepted


func _live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()
