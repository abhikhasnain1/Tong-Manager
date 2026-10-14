class_name StatusMarkerConfig
extends Resource
## Presentation only. Vessel quantities, brewing and serving rules remain elsewhere.

@export_group("Bubble layout")
@export_range(24.0, 80.0) var bubble_size := 32.0
@export_range(0.0, 20.0) var bubble_gap := 3.0
@export_range(1, 8, 1) var columns := 3
@export_range(12, 28, 1) var amount_font_size := 18
@export var font: Font

@export_group("Owner placement and hover")
@export var hover_lift := 14.0
@export var hover_rise_seconds := 1.0
@export var hover_fade_in_seconds := 0.25
@export var hover_fade_out_seconds := 0.8
@export var hover_bob_amplitude := 3.0
@export var hover_sway_amplitude := 2.0
@export var hover_bob_period := 3.8
@export var anchor_gap := 7.0
@export var screen_margin := 10.0
@export var cluster_gap := 5.0

@export_group("Qualitative bands")
@export_range(0.0, 1.0) var low_fill_limit := 0.3
@export_range(0.0, 1.0) var high_fill_start := 0.8
@export var hot_temperature := 75.0

@export_group("Cozy palette")
@export var ink := Color("624630")
@export var paper := Color("fff3d9")
@export var mint := Color("c8e5ba")
@export var pink := Color("ffced1")
@export var peach := Color("ffdfa9")
@export var lilac := Color("dfd2f7")
@export var blue := Color("cbe7f2")
@export var tea := Color("b87836")
@export var water := Color("72b9d1")
