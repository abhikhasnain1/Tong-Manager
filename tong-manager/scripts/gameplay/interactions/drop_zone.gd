class_name DropZone
extends Area2D

signal drop_applied(payload: HeldItemPayload)

const VALID_HIGHLIGHT := Color(0.25, 1.0, 0.4, 0.45)
const INVALID_HIGHLIGHT := Color(1.0, 0.25, 0.25, 0.45)

@export var zone_id: StringName = &""
@export var accepted_categories: Array[StringName] = []
@export_range(0.0, 2048.0, 1.0, "or_greater") var snap_radius: float = 64.0

# Optional presentation filter: (payload, viewport_position) -> bool. It only
# resolves visible pointer ownership; eligibility remains in accepts().
var pointer_gate := Callable()

@onready var debug_preview: Sprite2D = $DebugPreview


func allows_pointer(payload: HeldItemPayload, viewport_position: Vector2) -> bool:
	if pointer_gate.is_null(): return true
	if not pointer_gate.is_valid(): return false
	var allowed: Variant = pointer_gate.call(payload, viewport_position)
	return allowed is bool and allowed


func is_relevant_to(_payload: HeldItemPayload) -> bool:
	return true


func get_probe_position(_payload: HeldItemPayload, viewport_position: Vector2) -> Vector2:
	return viewport_position


func accepts(payload: HeldItemPayload) -> DropValidation:
	if payload == null:
		return DropValidation.invalid("drop.missing_payload")
	if accepted_categories.is_empty():
		return DropValidation.valid()

	var category := StringName(payload.metadata.get("category", payload.metadata.get("payload_type", &"")))
	if category.is_empty():
		return DropValidation.invalid("drop.missing_category")
	if not accepted_categories.has(category):
		return DropValidation.invalid("drop.category_not_accepted")
	return DropValidation.valid()


func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	drop_applied.emit(payload)


func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid:
		return false
	apply_drop(payload)
	return true


func on_rejected_release(_payload: HeldItemPayload, _validation: DropValidation) -> void:
	# A released, selected target may explain a rejection. Hover validation stays
	# read-only, and the controller still rolls the original gesture back.
	pass


func set_highlight(valid: bool) -> void:
	debug_preview.modulate = VALID_HIGHLIGHT if valid else INVALID_HIGHLIGHT
	debug_preview.visible = true


func clear_highlight() -> void:
	debug_preview.visible = false
