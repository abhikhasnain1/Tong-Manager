class_name IngredientRule
extends Resource
## One portion's destination and state requirements, separate from recipe taste.

@export var item_id: StringName = &""
@export var unit: StringName = &""
@export var quantity := 1
@export_enum("kettle", "cup") var vessel_kind := "cup"
@export var allow_empty := false
@export var allow_repeated := false
@export var requires_boiling := false
@export var allowed_liquid_id: StringName = &"black_tea"
@export var max_batch_volume_ml := 1500.0
