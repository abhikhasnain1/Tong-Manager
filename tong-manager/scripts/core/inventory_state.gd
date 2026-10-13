class_name InventoryState
extends PortionStockProvider

# One run's integer portion balances. Water remains in DailyWaterSupply (ml).
# Expose a snapshot so views cannot bypass validation or change notifications.
var quantities: Dictionary[StringName, int]:
	get:
		return _quantities.duplicate()
var initialized := false
var _quantities: Dictionary[StringName, int] = {}
var _units: Dictionary[StringName, StringName] = {}
var _reservations: Dictionary[int, Dictionary] = {}
var _next_token := 1
var _committing := false


func can_reset(starting: Dictionary, units: Dictionary) -> bool:
	if _committing:
		return false
	for item_id: Variant in units:
		if not _valid_name(item_id) or not _valid_name(units[item_id]) or StringName(units[item_id]) == &"ml":
			return false
	for item_id: Variant in starting:
		if (not _valid_name(item_id) or not units.has(item_id)
			or not starting[item_id] is int or starting[item_id] < 0):
			return false
	return true


func reset(starting: Dictionary, units: Dictionary, notify := true) -> bool:
	if not can_reset(starting, units):
		return false
	_quantities.clear()
	_units.clear()
	for item_id: Variant in units:
		var key := StringName(item_id)
		_units[key] = StringName(units[item_id])
		_quantities[key] = int(starting.get(item_id, 0))
	_reservations.clear()
	# Old payloads cannot become valid again after a new day.
	initialized = true
	if notify:
		changed.emit()
	return true


func get_quantity(item_id: StringName) -> int:
	return _quantities.get(item_id, 0)


func get_unit(item_id: StringName) -> StringName:
	return _units.get(item_id, &"")


func remaining(item_id: StringName) -> int:
	return get_quantity(item_id)


func available(item_id: StringName) -> int:
	return get_quantity(item_id) - _reserved(item_id)


func can_consume(item_id: StringName, amount: int) -> bool:
	return not _committing and amount > 0 and _units.has(item_id) and available(item_id) >= amount


func consume(item_id: StringName, amount: int) -> bool:
	if not can_consume(item_id, amount):
		return false
	_quantities[item_id] -= amount
	changed.emit()
	return true


func add(item_id: StringName, amount: int) -> bool:
	if (_committing or amount <= 0 or not _units.has(item_id)
		or amount > 9223372036854775807 - get_quantity(item_id)):
		return false
	_quantities[item_id] += amount
	changed.emit()
	return true


func set_quantity(item_id: StringName, amount: int) -> bool:
	if _committing or not _units.has(item_id) or amount < 0 or amount < _reserved(item_id):
		return false
	if get_quantity(item_id) != amount:
		_quantities[item_id] = amount
		changed.emit()
	return true


func reserve(item_id: StringName, unit: StringName, quantity: int, source_id: int) -> int:
	if source_id <= 0 or get_unit(item_id) != unit or not can_consume(item_id, quantity):
		return 0
	var token := _next_token
	_next_token += 1
	_reservations[token] = {"item_id":item_id, "unit":unit, "quantity":quantity, "source_id":source_id}
	changed.emit()
	return token


func reservation_matches(token: int, item_id: StringName, unit: StringName, quantity: int, source_id: int) -> bool:
	if not _reservations.has(token):
		return false
	var record: Dictionary = _reservations[token]
	return record.item_id == item_id and record.unit == unit and record.quantity == quantity and record.source_id == source_id


func commit(token: int, apply: Callable) -> bool:
	if _committing or not _reservations.has(token):
		return false
	var record: Dictionary = _reservations[token]
	if not apply.is_valid() or get_quantity(record.item_id) < int(record.quantity):
		release(token)
		return false
	# The adapter revalidates its live source/target in this synchronous callback.
	# Claim first; no signal exposes an unfinished debit, and retries cannot repeat it.
	_committing = true
	_reservations.erase(token)
	_quantities[record.item_id] -= int(record.quantity)
	var accepted := bool(apply.call())
	if not accepted:
		_quantities[record.item_id] += int(record.quantity)
	_committing = false
	changed.emit()
	return accepted


func release(token: int) -> void:
	# Cleanup of another held portion is legal inside a receiver's callback.
	# The completing commit publishes all resulting changes together.
	if _reservations.erase(token) and not _committing:
		changed.emit()


func is_committing() -> bool:
	return _committing


func _reserved(item_id: StringName) -> int:
	var amount := 0
	for record: Dictionary in _reservations.values():
		if record.item_id == item_id:
			amount += int(record.quantity)
	return amount


func _valid_name(value: Variant) -> bool:
	return (value is StringName or value is String) and not String(value).is_empty()
