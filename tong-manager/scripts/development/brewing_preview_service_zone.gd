extends DropZone

signal sample_served(result: Dictionary)

const Review := preload("res://scripts/gameplay/brewing_service_review.gd")
const SERVING_RECIPE := preload("res://data/recipes/cha_no_sugar.tres")

var controller: InteractionController
var screen_root: Node
var review := Review.new()
var sample_index := 0
var order_id: StringName
var _highlighted := false
var _valid := false
var _last_result: Dictionary = {}
var _heading: Label
var _feedback: Label

func _init() -> void:
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)
	snap_radius = 105.0
	input_pickable = false
	z_index = 0

func _ready() -> void:
	_heading = _label(Vector2(-137, -108), Vector2(274, 62), 18)
	_feedback = _label(Vector2(-137, 38), Vector2(274, 86), 16)
	next_sample()

func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func reset_samples() -> void:
	review = Review.new()
	sample_index = 0
	next_sample()

func next_sample() -> void:
	sample_index += 1
	order_id = StringName("preview_order_%d" % sample_index)
	_last_result = {}
	_heading.text = "SAMPLE CUSTOMER %d\nPlain black tea · at least %d ml" % [sample_index, SERVING_RECIPE.minimum_serving_volume_ml]
	_show_order_hint()
	queue_redraw()

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and is_instance_valid(payload.world_node) and payload.world_node is Cup

func accepts(payload: HeldItemPayload) -> DropValidation:
	if not is_relevant_to(payload) or not is_instance_valid(controller):
		return DropValidation.invalid("preview.cup_required")
	if (
		not is_inside_tree() or is_queued_for_deletion() or controller.is_queued_for_deletion()
		or not is_instance_valid(screen_root) or screen_root.is_queued_for_deletion()
		or not screen_root.is_ancestor_of(self) or not _belongs_to_live_screen(payload.world_node)
	):
		return DropValidation.invalid("preview.target_removed")
	if controller.current_mode != InteractionController.MODE_INTERACT:
		return DropValidation.invalid("preview.use_mode_required")
	if not controller.is_dragging() or controller.current_payload != payload:
		return DropValidation.invalid("preview.active_drag_required")
	var result := review.inspect(order_id, _snapshot(payload.world_node as Cup), SERVING_RECIPE.minimum_serving_volume_ml)
	return DropValidation.valid() if bool(result.accepted) else DropValidation.invalid(String(result.reason))

func _belongs_to_live_screen(node: Node) -> bool:
	while is_instance_valid(node) and node != screen_root:
		if not node.is_inside_tree() or node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return node == screen_root

func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	var cup := payload.world_node as Cup
	# Capture at the accepted drop, not when filled or first hovered.
	var result := review.accept(order_id, _snapshot(cup), SERVING_RECIPE.minimum_serving_volume_ml)
	if not bool(result.accepted):
		return
	cup.assigned_order_id = order_id
	cup.mark_served()
	controller.restore_drag_origin()
	_last_result = result
	_feedback.text = (
		"SERVED · UNHAPPY\nBad review: “My tea was cold.”"
		if bool(result.cold) else "SERVED · HAPPY\nThe tea was warm."
	)
	_feedback.text += "\nServed: %d · Bad reviews: %d" % [review.accepted_count(), review.bad_review_count()]
	sample_served.emit(result.duplicate(true))
	drop_applied.emit(payload)
	queue_redraw()

func _snapshot(cup: Cup) -> Dictionary:
	return {
		"available": cup.state == Cup.CupState.FILLED,
		"clean": cup.state != Cup.CupState.DIRTY,
		"recipe_id": cup.contents_base_id,
		"garnish_count": cup.get_ingredient_amounts().size(),
		"volume_ml": cup.volume_ml,
		"temperature": cup.temperature,
		"cold_threshold": cup.config.cold_temperature,
	}

func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	if _last_result.is_empty() and controller.current_payload != null:
		var cup := controller.current_payload.world_node as Cup
		if is_instance_valid(cup):
			var result := review.inspect(order_id, _snapshot(cup), SERVING_RECIPE.minimum_serving_volume_ml)
			if bool(result.accepted):
				_feedback.text = "Release to serve\nCold tea is accepted, with a bad review." if bool(result.cold) else "Release to serve\nWarm tea · happy customer"
			else:
				_feedback.text = "Cannot serve: " + String(result.reason).replace("_", " ")
	queue_redraw()

func clear_highlight() -> void:
	_highlighted = false
	if _last_result.is_empty() and is_instance_valid(_feedback):
		_show_order_hint()
	queue_redraw()

func _show_order_hint() -> void:
	_feedback.text = "Drop a filled cup here.\nCold tea is accepted, with a bad review."

func _draw() -> void:
	var border := Color(0.72, 0.66, 0.49)
	if _highlighted:
		border = VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT
	draw_style_box(_panel_style(border), Rect2(-149, -120, 298, 258))
	var face_center := Vector2(0, -9)
	draw_circle(face_center, 29, Color(0.92, 0.74, 0.48))
	draw_circle(face_center + Vector2(-10, -6), 2.5, Color(0.15, 0.12, 0.1))
	draw_circle(face_center + Vector2(10, -6), 2.5, Color(0.15, 0.12, 0.1))
	if _last_result.is_empty():
		draw_line(face_center + Vector2(-10, 10), face_center + Vector2(10, 10), Color(0.15, 0.12, 0.1), 2.0)
	elif bool(_last_result.unhappy):
		draw_arc(face_center + Vector2(0, 18), 12, PI, TAU, 20, Color(0.15, 0.12, 0.1), 2.0, true)
	else:
		draw_arc(face_center + Vector2(0, 4), 12, 0, PI, 20, Color(0.15, 0.12, 0.1), 2.0, true)

func _panel_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.13, 0.94)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style

func _exit_tree() -> void:
	if is_instance_valid(controller):
		controller.unregister_drop_zone(self)
