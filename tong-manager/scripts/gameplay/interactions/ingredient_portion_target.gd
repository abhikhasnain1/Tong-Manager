class_name IngredientPortionTarget
extends DropZone

# Narrow review fixture: this is not the final recipe eligibility/dose policy.
var controller: InteractionController
var target: Node2D
var _highlighted := false
var _valid := false

func _init() -> void:
	input_pickable = false
	var preview := Sprite2D.new()
	preview.name = "DebugPreview"
	preview.visible = false
	add_child(preview)

func configure(interaction: InteractionController, owner_node: Node2D) -> void:
	controller = interaction
	target = owner_node
	zone_id = &"ingredient_portion"
	snap_radius = 30.0 if target is Cup else 44.0
	controller.register_drop_zone(self)

func is_relevant_to(payload: HeldItemPayload) -> bool:
	return payload != null and payload.metadata.get("category") == &"ingredient_portion"

func accepts(payload: HeldItemPayload) -> DropValidation:
	if (not is_relevant_to(payload) or not is_inside_tree() or is_queued_for_deletion()
		or not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion()
		or not target.is_ancestor_of(self)):
		return DropValidation.invalid("Ingredient target is unavailable")
	if (not is_instance_valid(controller) or not controller.is_inside_tree() or controller.is_queued_for_deletion()
		or controller.current_mode != InteractionController.MODE_INTERACT or controller.is_world_input_blocked()
		or controller.current_payload != payload or controller.current_drag_node != payload.world_node):
		return DropValidation.invalid("Use an active ingredient portion")
	var portion := payload.metadata.get("portion") as IngredientPortion
	if portion == null or not portion.is_available():
		return DropValidation.invalid("This ingredient portion is no longer available")
	return _fixture_eligibility(portion.item_id)

func _fixture_eligibility(item_id: StringName) -> DropValidation:
	if target is Kettle:
		if item_id != &"black_tea":
			return DropValidation.invalid("This preview uses sugar and milk in tea cups")
		var kettle := target as Kettle
		if kettle.contains_tea:
			return DropValidation.invalid("This kettle already contains tea")
		if kettle.volume_ml <= 0:
			return DropValidation.invalid("Fill the kettle with water first")
		if kettle.temperature < kettle.config.boiling_temperature:
			return DropValidation.invalid("Wait for the water to boil")
		return DropValidation.invalid("Finish pouring first") if kettle.is_pouring else DropValidation.valid()
	if target is Cup:
		if item_id not in [&"sugar",&"condensed_milk"]:
			return DropValidation.invalid("This preview brews teabags in the kettle")
		var cup := target as Cup
		if cup.volume_ml <= 0 or cup.liquid_type != &"black_tea" or cup.contents_base_id != &"black_tea":
			return DropValidation.invalid("Pour tea into this cup first")
		if not cup.can_accept_relish(item_id):
			return DropValidation.invalid("This cup cannot accept another ingredient")
		return DropValidation.valid()
	return DropValidation.invalid("Ingredient target is unavailable")

func apply_drop(payload: HeldItemPayload) -> void:
	try_apply_drop(payload)

func try_apply_drop(payload: HeldItemPayload) -> bool:
	var validation := accepts(payload)
	if not validation.is_valid:
		if is_instance_valid(controller):
			controller.report_hint(validation.reason_key)
		return false
	var portion := payload.metadata.get("portion") as IngredientPortion
	if not portion.commit(_apply_fixture.bind(portion.item_id)):
		return false
	controller.report_hint("Added one teabag" if portion.unit == &"teabag" else "Added one spoonful of %s" % ("milk" if portion.item_id == &"condensed_milk" else "sugar"))
	clear_highlight()
	drop_applied.emit(payload)
	return true

func _apply_fixture(item_id: StringName) -> bool:
	if (not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion()
		or not target.is_ancestor_of(self) or not _fixture_eligibility(item_id).is_valid):
		return false
	if target is Kettle:
		return (target as Kettle).add_tea_leaves()
	# Milk is represented as an abstract garnish here, without changing liquid
	# volume/temperature or selecting a quantified production recipe dose.
	return (target as Cup).add_relish(item_id)

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
