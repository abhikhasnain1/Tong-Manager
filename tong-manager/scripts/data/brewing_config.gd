class_name BrewingConfig
extends Resource

@export_range(1.0, 1000.0) var pour_rate_ml := 150.0
@export_range(1.0, 120.0) var boiling_temperature := 100.0
@export_range(1.0, 120.0) var ambient_temperature := 20.0
@export_range(0.1, 60.0) var heat_rate := 8.0
@export_range(0.0, 20.0) var cooling_rate := 1.5
@export_range(0.1, 60.0) var steep_seconds := 3.0
@export_range(1.0, 180.0) var oversteep_seconds := 30.0
@export var heat_levels := PackedFloat32Array([0.0, 0.5, 1.0, 1.75])
