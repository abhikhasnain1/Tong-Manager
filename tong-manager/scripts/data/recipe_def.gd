extends Resource

@export var id: StringName
@export var display_name_key: String
@export var base_item_ids: Array[StringName] = []
@export var relish_item_ids: Array[StringName] = []
@export var output_item_id: StringName
@export var price: int
@export var unlocked_by_default: bool

# Existing reference recipes stay loadable without becoming production recipes.
# Ingredient stock units and brewed-liquid identity have different meanings.
@export_group("Production portions")
@export var production_supported := false
@export var brewed_liquid_id: StringName = &""
@export var kettle_portion_counts: Dictionary[StringName, int] = {}
@export var kettle_portion_units: Dictionary[StringName, StringName] = {}
@export var cup_portion_counts: Dictionary[StringName, int] = {}
@export var cup_portion_units: Dictionary[StringName, StringName] = {}

@export_group("Batch and serving")
@export var batch_requires_boiling_water := false
@export var max_batch_volume_ml := 0.0
@export var target_serving_volume_ml := 0.0
@export var minimum_serving_volume_ml := 0.0
