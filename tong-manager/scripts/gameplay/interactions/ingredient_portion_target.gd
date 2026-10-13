class_name IngredientPortionTarget
extends DropZone

@export var policy: IngredientPolicy = preload("res://data/balance/ingredient_policy.tres")
var controller: InteractionController
var target: Node2D
var _context_ref: WeakRef
var _highlighted := false
var _valid := false

func _init() -> void:
	input_pickable = false
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)

func configure(interaction: InteractionController, owner_node: Node2D) -> void:
	if is_instance_valid(controller) and controller != interaction:
		controller.unregister_drop_zone(self)
	controller = interaction
	target = owner_node
	_context_ref = weakref(controller.get_parent()) if is_instance_valid(controller) and controller.get_parent() != null else null
	zone_id = &"ingredient_portion"
	snap_radius = 30.0 if target is Cup else 44.0
	if _belongs_to_context(target):
		controller.register_drop_zone(self)

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and payload.metadata.get("category") == &"ingredient_portion"

func accepts(payload: HeldItemPayload) -> DropValidation:
	if (not is_relevant_to(payload) or not is_inside_tree() or is_queued_for_deletion()
		or not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion()
		or not target.is_ancestor_of(self) or not _belongs_to_context(target)):
		return DropValidation.invalid("Ingredient target is unavailable")
	if (not is_instance_valid(controller) or not controller.is_inside_tree() or controller.is_queued_for_deletion()
		or not controller.can_address_drop_zone(payload, self)
		or (not controller.is_modal_export_active() and controller.current_mode != InteractionController.MODE_INTERACT)):
		return DropValidation.invalid("Use an active ingredient portion")
	var portion := payload.metadata.get("portion") as IngredientPortion
	if portion == null or not portion.is_available():
		return DropValidation.invalid("This ingredient portion is no longer available")
	if not _belongs_to_context(portion.source_ref.get_ref() as Node):
		return DropValidation.invalid("Use an ingredient from this stall")
	if (payload.item_id != portion.item_id or payload.quantity != portion.quantity
		or payload.metadata.get("item_id") != portion.item_id or payload.metadata.get("unit") != portion.unit
		or payload.metadata.get("quantity") != portion.quantity or payload.metadata.get("source_id") != portion.source_id
		or payload.metadata.get("cleanup_callback") != Callable(portion, "cancel")):
		return DropValidation.invalid("Use the original held portion")
	return IngredientDropCommand.new(portion, target, policy, _context_ref.get_ref() as Node).can_execute()

func apply_drop(payload: HeldItemPayload) -> void:
	try_apply_drop(payload)

func try_apply_drop(payload: HeldItemPayload) -> bool:
	var validation := accepts(payload)
	if not validation.is_valid:
		if is_instance_valid(controller):
			controller.report_hint(validation.reason_key)
		return false
	var portion := payload.metadata.get("portion") as IngredientPortion
	var hint := "Added one teabag" if portion.unit == &"teabag" else "Added one spoonful of %s" % ("milk" if portion.item_id == &"condensed_milk" else "sugar")
	var self_ref: WeakRef = weakref(self)
	if not IngredientDropCommand.new(portion, target, policy, _context_ref.get_ref() as Node).execute():
		return false
	if self_ref.get_ref() == null:
		return true
	clear_highlight()
	if is_instance_valid(controller):
		controller.report_hint(hint)
	if self_ref.get_ref() != null:
		drop_applied.emit(payload)
	return true

func _enter_tree() -> void:
	if is_instance_valid(controller) and _belongs_to_context(target):
		controller.register_drop_zone(self)

func _exit_tree() -> void:
	if is_instance_valid(controller):
		controller.unregister_drop_zone(self)

func _belongs_to_context(node: Node) -> bool:
	var context := _context_ref.get_ref() as Node if _context_ref != null else null
	return (is_instance_valid(context) and context.is_inside_tree() and not context.is_queued_for_deletion()
		and is_instance_valid(controller) and context.is_ancestor_of(controller)
		and is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()
		and context.is_ancestor_of(node))

func set_highlight(valid: bool) -> void:
	_highlighted = true
	_valid = valid
	queue_redraw()

func clear_highlight() -> void:
	_highlighted = false
	queue_redraw()

func _draw() -> void:
	if _highlighted:
		draw_arc(Vector2.ZERO,27 if target is Cup else 38,0,TAU,40,VALID_HIGHLIGHT if _valid else INVALID_HIGHLIGHT,3,true)
