class_name FinanceState
extends RefCounted
## One run's ledger. Presentation and payment consumers only observe snapshots.

signal transaction_recorded(record: Dictionary)
signal changed

const MAX_MONEY := 9223372036854775807
const MAX_METADATA_DEPTH := 32

var initialized: bool:
	get: return _initialized
	set(_value): pass
var generation: int:
	get: return _generation
	set(_value): pass
var cash_on_hand: int:
	get: return _cash
	set(_value): pass
var day_income: int:
	get: return _income
	set(_value): pass
var day_expenses: int:
	get: return _expenses
	set(_value): pass
var transaction_log: Array[Dictionary]:
	get: return _log.duplicate(true)
	set(_value): pass

var _initialized := false
var _generation := 0
var _starting_cash := 0
var _cash := 0
var _income := 0
var _expenses := 0
var _log: Array[Dictionary] = []
var _sources: Dictionary[StringName, int] = {}
var _committing := false
var _reset_pending := false
var _reset_owner: RefCounted


func can_reset(starting_cash: Variant) -> bool:
	return not _committing and _generation < MAX_MONEY and typeof(starting_cash) == TYPE_INT and starting_cash >= 0


func reset(starting_cash: Variant, notify := true) -> bool:
	var owner := RefCounted.new()
	if not begin_reset(starting_cash, owner): return false
	return finish_reset(owner, notify)


func begin_reset(starting_cash: Variant, owner: RefCounted = null) -> bool:
	# GameState keeps this guard across the coordinated supply notifications.
	if owner == null or not can_reset(starting_cash): return false
	_committing = true
	_reset_pending = true
	_reset_owner = owner
	_generation += 1
	_starting_cash = starting_cash
	_cash = starting_cash
	_income = 0
	_expenses = 0
	_log.clear()
	_sources.clear()
	_initialized = true
	return true


func finish_reset(owner: RefCounted = null, notify := true) -> bool:
	# A notification observer cannot release somebody else's staged reset.
	if not _reset_pending or owner == null or owner != _reset_owner: return false
	_reset_pending = false
	_reset_owner = null
	if notify: changed.emit()
	_committing = false
	return true


func is_committing() -> bool:
	return _committing


func record_income(source_id: Variant, amount: Variant, metadata: Dictionary = {}, aliases: Array = []) -> bool:
	return _record(&"income", source_id, amount, metadata, aliases)


func record_expense(source_id: Variant, amount: Variant, metadata: Dictionary = {}, aliases: Array = []) -> bool:
	return _record(&"expense", source_id, amount, metadata, aliases)


func get_transaction(source_id: Variant) -> Dictionary:
	if not _valid_identity(source_id): return {}
	var identity := StringName(source_id)
	return _log[_sources[identity]].duplicate(true) if _sources.has(identity) else {}


func get_snapshot() -> Dictionary:
	return {"initialized": _initialized, "generation": _generation, "starting_cash": _starting_cash,
		"cash_on_hand": _cash, "day_income": _income, "day_expenses": _expenses,
		"transaction_log": transaction_log}


func _record(kind: StringName, source_id: Variant, amount: Variant, metadata: Dictionary, aliases: Array) -> bool:
	if _committing or not _initialized or not _valid_identity(source_id): return false
	if typeof(amount) != TYPE_INT or amount <= 0: return false
	var identity := StringName(source_id)
	if _sources.has(identity) or not _valid_metadata(metadata): return false
	var names: Array[StringName] = []
	for alias: Variant in aliases:
		if not _valid_identity(alias): return false
		var name := StringName(alias)
		if name == identity or names.has(name) or _sources.has(name): return false
		names.append(name)
	if kind == &"income":
		if amount > MAX_MONEY - _cash or amount > MAX_MONEY - _income: return false
	else:
		if amount > _cash or amount > MAX_MONEY - _expenses: return false
	_committing = true
	if kind == &"income":
		_cash += amount
		_income += amount
	else:
		_cash -= amount
		_expenses += amount
	var record := {"source_id": identity, "aliases": names, "kind": kind, "amount": amount,
		"cash_after": _cash, "day_income": _income, "day_expenses": _expenses,
		"generation": _generation, "metadata": metadata.duplicate(true)}
	var index := _log.size()
	_log.append(record)
	_sources[identity] = index
	for name in names: _sources[name] = index
	# Keep mutations guarded until both signals finish; each observer sees the
	# complete committed record, balances and identity aliases at the same time.
	transaction_recorded.emit(record.duplicate(true))
	changed.emit()
	_committing = false
	return true


func _valid_identity(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]: return false
	var text := String(value)
	return not text.is_empty() and text == text.strip_edges()


func _valid_metadata(value: Variant, depth := 0) -> bool:
	if depth > MAX_METADATA_DEPTH: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _valid_metadata(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not _valid_metadata(value[key], depth + 1): return false
			return true
	return false
