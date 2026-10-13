extends Node

const DEFAULT_DAY_CONFIG = preload("res://data/balance/demo_day_1.tres")

# This run's daily supply survives scene changes. Persistence/day scheduling is separate.
var water_supply := DailyWaterSupply.new()
var inventory := InventoryState.new()
var _resetting := false


func ensure_inventory(day_config: Resource = null) -> bool:
	if inventory.initialized:
		return true
	if _resetting:
		return false
	var config: Resource = DEFAULT_DAY_CONFIG if day_config == null else day_config
	return inventory.reset(config.starting_inventory, _inventory_units())


func ensure_water_day(day_config: Resource = null) -> void:
	if water_supply.day_id < 0:
		var allocation := float(day_config.get("daily_water_ml")) if day_config != null else -1.0
		start_water_day(1, allocation)


func start_water_day(day_id: int, allocation_ml: float = -1.0) -> bool:
	if _resetting:
		return false
	var amount := float(DEFAULT_DAY_CONFIG.daily_water_ml) if allocation_ml == -1.0 else allocation_ml
	return water_supply.begin_day(day_id, amount)


func reset_demo_state(day_config: Resource = null) -> bool:
	# Only an explicit reset replenishes supplies. Keep provider identities so
	# existing sources and future Khata views still observe the same authority.
	if _resetting:
		return false
	var config: Resource = DEFAULT_DAY_CONFIG if day_config == null else day_config
	var units := _inventory_units()
	var next_day := maxi(1, water_supply.day_id + 1)
	if (not inventory.can_reset(config.starting_inventory, units)
		or not water_supply.can_begin_day(next_day, config.daily_water_ml)):
		return false
	_resetting = true
	# Publish only after both balances are coherent; synchronous observers cannot
	# see new stock alongside the previous day's water or recursively reset.
	inventory.reset(config.starting_inventory, units, false)
	water_supply.begin_day(next_day, config.daily_water_ml, false)
	inventory.changed.emit()
	water_supply.remaining_changed.emit(water_supply.remaining_ml)
	_resetting = false
	return true


func _inventory_units() -> Dictionary:
	var units: Dictionary = {}
	var catalog := get_node("/root/Catalog")
	for item_id: StringName in catalog.items:
		var item: Resource = catalog.items[item_id]
		if item.unit != &"ml":
			units[item_id] = item.unit
	return units
