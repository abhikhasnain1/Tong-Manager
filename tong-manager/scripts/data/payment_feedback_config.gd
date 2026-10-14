class_name PaymentFeedbackConfig
extends Resource
## Presentation tuning only; this resource never changes a payment amount.

@export_group("Motion")
@export_range(0.2, 2.0, 0.05) var duration := 0.85
@export_range(0.0, 80.0, 1.0) var arc_height := 32.0
@export_range(0.5, 2.0, 0.05) var coin_scale := 1.0
@export_range(12, 32, 1) var amount_font_size := 18
@export_range(0.04, 0.2, 0.01) var coin_launch_stagger_seconds := 0.11
@export var reduced_motion := false

@export_group("Sound")
@export var sound_enabled := true
@export var sound_stream: AudioStream = preload("res://assets/audio/sfx/coin_drop.mp3")
@export_range(-60.0, 0.0, 1.0) var sound_volume_db := -17.0
@export var sound_bus: StringName = &"Master"
@export_range(0.5, 2.0, 0.05) var sound_base_pitch := 1.0
@export_range(0.0, 7.0, 0.5) var sound_pitch_step_semitones := 2.0
@export_range(1, 8, 1) var sound_pitch_cycle := 4

@export_group("Palette")
@export var gold := Color("f5cc69")
@export var shine := Color("fff0b8")
@export var edge := Color("9e682c")
@export var ink := Color("493621")
