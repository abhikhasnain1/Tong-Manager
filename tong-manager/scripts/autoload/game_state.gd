extends Node

const DEFAULT_DAY_CONFIG = preload("res://data/balance/demo_day_1.tres")

# This run's daily supply survives scene changes. Persistence/day scheduling is separate.
var water_supply := DailyWaterSupply.new()


func ensure_water_day(day_config: Resource = null) -> void:
	if water_supply.day_id < 0:
		var allocation := float(day_config.get("daily_water_ml")) if day_config != null else -1.0
		start_water_day(1, allocation)


func start_water_day(day_id: int, allocation_ml: float = -1.0) -> bool:
	var amount := float(DEFAULT_DAY_CONFIG.daily_water_ml) if allocation_ml == -1.0 else allocation_ml
	return water_supply.begin_day(day_id, amount)


func reset_demo_state() -> void:
	# Only an explicit new sample day replenishes water; a screen reload does not.
	start_water_day(maxi(1, water_supply.day_id + 1))
