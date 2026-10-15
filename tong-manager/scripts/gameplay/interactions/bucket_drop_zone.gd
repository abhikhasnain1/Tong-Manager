class_name BucketDropZone
extends DropZone

var bucket: BucketStation

func _init() -> void:
	name = "BucketDropTarget"
	input_pickable = false
	snap_radius = 1.0
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.hide()
	add_child(preview)

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return (payload != null and is_instance_valid(payload.world_node) and payload.world_node is Cup
		and payload.metadata.get("category") in [&"cup", &"cup_transfer"])

func get_probe_position(_payload: HeldItemPayload, point: Vector2) -> Vector2:
	if is_instance_valid(bucket) and bucket.contains_pointer(point):
		return get_global_transform_with_canvas().origin
	return Vector2(INF, INF)

func accepts(payload: HeldItemPayload) -> DropValidation:
	if not is_instance_valid(bucket) or not is_relevant_to(payload):
		return DropValidation.invalid("bucket.unavailable")
	return bucket.can_receive(payload)

func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid:
		return false
	var self_ref: WeakRef = weakref(self)
	var accepted := bucket.try_receive(payload)
	if self_ref.get_ref() == null:
		return accepted
	if not accepted:
		return false
	clear_highlight()
	drop_applied.emit(payload)
	return true

func apply_drop(payload: HeldItemPayload) -> void:
	try_apply_drop(payload)

func on_rejected_release(_payload: HeldItemPayload, validation: DropValidation) -> void:
	if is_instance_valid(bucket):
		bucket.report_rejection(validation.reason_key)

func set_highlight(valid: bool) -> void:
	if is_instance_valid(bucket):
		bucket.set_drop_highlight(true, valid)

func clear_highlight() -> void:
	if is_instance_valid(bucket):
		bucket.set_drop_highlight(false, false)
