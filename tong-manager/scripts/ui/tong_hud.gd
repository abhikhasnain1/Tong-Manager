class_name TongHud
extends Control

const MODE_INTERACT := &"interact"
const MODE_ORGANIZE := &"organize"
const ACTIVE_MODE_COLOR := Color.WHITE
const INACTIVE_MODE_COLOR := Color(1.0, 1.0, 1.0, 0.45)

@onready var clock_label: Label = %ClockLabel
@onready var cash_label: Label = %CashLabel
@onready var interact_mode_label: Label = %InteractModeLabel
@onready var organize_mode_label: Label = %OrganizeModeLabel

var current_mode: StringName = MODE_INTERACT


func _ready() -> void:
	set_mode(current_mode)


func set_clock_text(value: String) -> void:
	clock_label.text = value


func set_cash(value: int) -> void:
	cash_label.text = "৳ %d" % value


func set_mode(mode: StringName) -> void:
	assert(mode == MODE_INTERACT or mode == MODE_ORGANIZE, "Unsupported HUD mode: %s" % mode)
	current_mode = mode
	var is_organize := current_mode == MODE_ORGANIZE
	interact_mode_label.modulate = INACTIVE_MODE_COLOR if is_organize else ACTIVE_MODE_COLOR
	organize_mode_label.modulate = ACTIVE_MODE_COLOR if is_organize else INACTIVE_MODE_COLOR
