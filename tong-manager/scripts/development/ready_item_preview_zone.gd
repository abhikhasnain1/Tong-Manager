extends DropZone

# A narrow handoff fixture, separate from production orders and inventory.
var controller: InteractionController
var screen_root: Node
var handed_off := {&"banana": 0, &"biscuits": 0}
var _highlighted := false
var _valid := false
var _feedback: Label


func _init() -> void:
	input_pickable = false
	snap_radius = 72.0
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.hide()
	add_child(preview)


func _ready() -> void:
	_label("PREVIEW HANDOFF", Vector2(-116, -92), Vector2(232, 28), 18)
	_label("One banana or biscuit", Vector2(-116, -63), Vector2(232, 28), 15)
	_feedback = _label("", Vector2(-116, 42), Vector2(232, 46), 14)
	reset_fixture()


func _label(caption: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func reset_fixture() -> void:
	handed_off = {&"banana": 0, &"biscuits": 0}
	_update_feedback()
	queue_redraw()


func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and payload.metadata.get("category") == &"ready_item"


func _belongs_to_live_screen(node: Node) -> bool:
	if not is_instance_valid(screen_root) or screen_root.is_queued_for_deletion() or not screen_root.is_inside_tree():
		return false
	while is_instance_valid(node) and node != screen_root:
		if not node.is_inside_tree() or node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return node == screen_root


func _live_target() -> bool:
	return (_belongs_to_live_screen(self) and is_instance_valid(controller)
		and _belongs_to_live_screen(controller)
		and (controller.is_modal_export_active() or (not controller.is_world_input_blocked()
		and controller.current_mode == InteractionController.MODE_USE)))


func accepts(payload: HeldItemPayload) -> DropValidation:
	if not is_relevant_to(payload) or not _live_target():
		return DropValidation.invalid("Preview handoff is unavailable")
	if (not controller.can_address_drop_zone(payload, self)
		or not _belongs_to_live_screen(payload.world_node)):
		return DropValidation.invalid("Use a held ready item")
	var portion := payload.metadata.get("portion") as IngredientPortion
	if (portion == null or not portion.is_available() or portion.unit != &"piece"
		or portion.quantity != 1 or not handed_off.has(portion.item_id)
		or not _belongs_to_live_screen(portion.source_ref.get_ref())):
		return DropValidation.invalid("This ready item is unavailable")
	return DropValidation.valid()


func apply_drop(payload: HeldItemPayload) -> void:
	try_apply_drop(payload)


func try_apply_drop(payload: HeldItemPayload) -> bool:
	if not accepts(payload).is_valid:
		return false
	var portion := payload.metadata.get("portion") as IngredientPortion
	if not portion.commit(_record_handoff.bind(portion.item_id)):
		return false
	controller.report_hint("Preview handoff: one %s" % ("banana" if portion.item_id == &"banana" else "biscuit"))
	clear_highlight()
	drop_applied.emit(payload)
	return true


func _record_handoff(item_id: StringName) -> bool:
	if not _live_target() or not handed_off.has(item_id):
		return false
	handed_off[item_id] += 1
	_update_feedback()
	return true


func _update_feedback() -> void:
	if is_instance_valid(_feedback):
		_feedback.text = "Handed off · bananas %d · biscuits %d\nTest only · no orders or payments" % [
			handed_off[&"banana"], handed_off[&"biscuits"]]


func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	queue_redraw()


func clear_highlight() -> void:
	_highlighted = false
	queue_redraw()


func _draw() -> void:
	var border := Color(0.72, 0.66, 0.49)
	if _highlighted:
		border = VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.13, 0.94)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	draw_style_box(style, Rect2(-126, -102, 252, 202))
	draw_arc(Vector2.ZERO, 30, 0, TAU, 40, border, 2.0, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), border, 2.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), border, 2.0)


func _exit_tree() -> void:
	if is_instance_valid(controller):
		controller.unregister_drop_zone(self)
