class_name DiscardDropZone
extends DropZone

var controller: InteractionController
var _highlighted := false
var _valid := false
var _feedback_seconds := 0.0
var _caption: Label
var _basket: Sprite2D

func _init() -> void:
	name = "DiscardArea"
	snap_radius = 62.0
	input_pickable = false
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)

func _ready() -> void:
	_basket = get_node_or_null("Basket") as Sprite2D
	_caption = Label.new()
	_caption.position = Vector2(-105, 84)
	_caption.size = Vector2(210, 55)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_color_override("font_outline_color", Color("211f20"))
	_caption.add_theme_constant_override("outline_size", 6)
	add_child(_caption)
	_caption.text = "Discard contents\nDrop kettle or cup"
	queue_redraw()

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and payload.source != &"cup_transfer" and is_instance_valid(payload.world_node) and (payload.world_node is Kettle or payload.world_node is Cup)

func accepts(payload: HeldItemPayload) -> DropValidation:
	if (not is_inside_tree() or is_queued_for_deletion() or not is_relevant_to(payload)
		or not payload.world_node.is_inside_tree() or payload.world_node.is_queued_for_deletion()
		or not is_instance_valid(controller) or not controller.is_dragging()
		or controller.current_payload != payload or controller.current_mode != InteractionController.MODE_INTERACT
		or bool(payload.metadata.get("discard_committed", false))):
		return DropValidation.invalid("discard.vessel_drag_required")
	return DropValidation.valid()

func apply_drop(payload: HeldItemPayload) -> void:
	if not accepts(payload).is_valid:
		return
	# A payload may commit only once, even if delivered again after a refill.
	payload.metadata["discard_committed"] = true
	var discarded := 0.0
	if payload.world_node is Kettle:
		var kettle := payload.world_node as Kettle
		discarded = kettle.discard_contents()
		kettle.finish_cup_interaction()
	else:
		var cup := payload.world_node as Cup
		for candidate in get_tree().get_nodes_in_group("kettles"):
			if candidate is Kettle and (candidate as Kettle).pour_target == cup:
				(candidate as Kettle).stop_pour()
		discarded = cup.discard_contents()
		controller.restore_drag_origin()
	_caption.text = "Contents emptied\n%d ml discarded" % roundi(discarded)
	_feedback_seconds = 2.5
	drop_applied.emit(payload)

func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	if is_instance_valid(_basket):
		_basket.modulate = Color(1.3, 1.3, 1.3) if valid else Color(1.0, 0.65, 0.65)
	queue_redraw()

func clear_highlight() -> void:
	_highlighted = false
	if is_instance_valid(_basket):
		_basket.modulate = Color.WHITE
	queue_redraw()

func _process(delta: float) -> void:
	if _feedback_seconds > 0.0:
		_feedback_seconds -= delta
		if _feedback_seconds <= 0.0:
			_caption.text = "Discard contents\nDrop kettle or cup"

func _draw() -> void:
	if is_instance_valid(_basket):
		return
	var edge := Color("ca9b80")
	if _highlighted:
		edge = Color("edc28c") if _valid else Color("d87365")
	draw_circle(Vector2.ZERO, 66, Color("302b2a"))
	draw_arc(Vector2.ZERO, 63, 0, TAU, 64, edge, 3, true)
	# Downward liquid drops distinguish contents disposal from vessel deletion.
	for x in [-18.0, 0.0, 18.0]:
		draw_line(Vector2(x, -30), Vector2(x, -6), edge, 3, true)
		draw_circle(Vector2(x, 1), 3.5, edge)
	draw_arc(Vector2(0, 12), 30, 0, PI, 32, edge, 4, true)
	draw_line(Vector2(-36, 12), Vector2(36, 12), edge, 3, true)
