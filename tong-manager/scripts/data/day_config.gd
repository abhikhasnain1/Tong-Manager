extends Resource

@export var start_hour: int
@export var interaction_minutes: int
@export var customer_count_min: int
@export var customer_count_max: int
@export var starting_cash: int
@export var starting_inventory: Dictionary
@export_range(0.0, 100000.0, 50.0, "or_greater") var daily_water_ml: float = 3000.0
