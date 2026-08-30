class_name DropValidation
extends Resource

@export var is_valid: bool = false
@export var reason_key: String = ""
@export var preview_command: Resource


func _init(
	p_is_valid: bool = false,
	p_reason_key: String = "",
	p_preview_command: Resource = null
) -> void:
	is_valid = p_is_valid
	reason_key = p_reason_key
	preview_command = p_preview_command


static func valid(command: Resource = null) -> DropValidation:
	return DropValidation.new(true, "", command)


static func invalid(reason: String) -> DropValidation:
	return DropValidation.new(false, reason)
