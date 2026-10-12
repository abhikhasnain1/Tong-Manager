class_name DevelopmentPortionStock
extends PortionStockProvider

# Deliberately separate from GameState and production inventory. These counts
# are a finite interaction fixture, not recipe doses or bag-to-gram conversion.
const INITIAL_STOCK := {&"black_tea":6, &"sugar":12, &"condensed_milk":12, &"banana":6, &"biscuits":8}
const UNITS := {&"black_tea":&"teabag", &"sugar":&"spoonful", &"condensed_milk":&"spoonful", &"banana":&"piece", &"biscuits":&"piece"}

var _stock: Dictionary = {}
var _reservations: Dictionary = {}
var _next_token := 1
var _committing := false

func _init() -> void:
	reset_fixture()

func reset_fixture() -> bool:
	if _committing:
		return false
	_stock = INITIAL_STOCK.duplicate()
	_reservations.clear()
	# Never reuse a token: a payload held over a reset must stay invalid.
	changed.emit()
	return true

func remaining(item_id: StringName) -> int:
	return int(_stock.get(item_id,0))

func available(item_id: StringName) -> int:
	var result := remaining(item_id)
	for record: Dictionary in _reservations.values():
		if record.item_id == item_id:
			result -= int(record.quantity)
	return maxi(0,result)

func reserve(item_id: StringName, unit: StringName, quantity: int, source_id: int) -> int:
	if (_committing or source_id <= 0 or quantity <= 0 or not UNITS.has(item_id)
		or UNITS[item_id] != unit or available(item_id) < quantity):
		return 0
	var token := _next_token
	_next_token += 1
	_reservations[token] = {"item_id":item_id,"unit":unit,"quantity":quantity,"source_id":source_id}
	changed.emit()
	return token

func reservation_matches(token: int, item_id: StringName, unit: StringName, quantity: int, source_id: int) -> bool:
	if not _reservations.has(token):
		return false
	var record: Dictionary = _reservations[token]
	return record.item_id == item_id and record.unit == unit and record.quantity == quantity and record.source_id == source_id

func commit(token: int, apply: Callable) -> bool:
	if _committing or not _reservations.has(token) or not apply.is_valid():
		return false
	var record: Dictionary = _reservations[token]
	if remaining(record.item_id) < int(record.quantity):
		return false
	# Consume the token before calling target code so synchronous signals cannot
	# repeat this command. No stock signal or await exposes an unfinished commit.
	_committing = true
	_reservations.erase(token)
	_stock[record.item_id] = remaining(record.item_id) - int(record.quantity)
	var applied := bool(apply.call())
	if not applied:
		_stock[record.item_id] = remaining(record.item_id) + int(record.quantity)
	_committing = false
	changed.emit()
	return applied

func release(token: int) -> void:
	if _reservations.erase(token):
		changed.emit()
