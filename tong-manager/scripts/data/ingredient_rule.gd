class_name IngredientRule
extends Resource
## Permission for one item in one vessel. Recipe desired doses are independent.

@export_group("Identity and destination")
@export var enabled := true
@export var item_id: StringName = &""
@export var unit: StringName = &""
## Units per accepted drop. Existing sources extract one unit per gesture.
@export_range(1, 100) var quantity := 1
@export_enum("kettle", "cup") var vessel_kind := "cup"

@export_group("Effect")
## Mix records a portion without starting brewing. Infuse starts a kettle batch.
@export_enum("mix", "infuse") var effect := "mix"
## Required for infusion, e.g. black_tea or coffee. Mix does not change the base.
@export var output_liquid_id: StringName = &""
## A later infusion may restart the clock; otherwise its existing progress stays.
@export var restart_steeping := false

@export_group("Permissions")
## Empty means no permitted stages. Use vessel stage names from the authoring guide.
@export var allowed_stages: Array[StringName] = []
@export var allow_empty := false
@export var allow_repeated := true
## -1 has no count cap; 0 disables this ingredient; positive values cap present units.
@export_range(-1, 100, 1, "or_greater") var max_portions := -1
## Nonempty vessels must contain one of these bases. Empty list accepts any base.
@export var allowed_liquid_ids: Array[StringName] = []

@export_group("Temperature and volume")
## Uses the vessel's boiling threshold; false really permits cooler use.
@export var requires_boiling := false
@export var minimum_temperature := -273.15
@export var maximum_temperature := 1000.0
@export var minimum_volume_ml := 0.0
## Kettle-only limit, independent of physical capacity. -1 disables this limit.
@export var max_batch_volume_ml := 1500.0
