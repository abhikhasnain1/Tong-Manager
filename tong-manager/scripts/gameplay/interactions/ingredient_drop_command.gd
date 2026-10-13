class_name IngredientDropCommand
extends RefCounted
## Both pantry and physical-source drops commit through this same transaction.

const DEFAULT_POLICY: IngredientPolicy = preload("res://data/balance/ingredient_policy.tres")

var _portion: IngredientPortion
var _target_ref: WeakRef
var _context_ref: WeakRef
var _policy: IngredientPolicy
var _item_id: StringName
var _unit: StringName
var _quantity: int
var _source_id: int
var _executing := false
var _finished := false


func _init(portion: IngredientPortion = null, target: Node2D = null, policy: IngredientPolicy = DEFAULT_POLICY, context: Node = null) -> void:
	_portion = portion
	_policy = policy
	if is_instance_valid(target):
		_target_ref = weakref(target)
	if is_instance_valid(context):
		_context_ref = weakref(context)
	if portion != null:
		_item_id = portion.item_id
		_unit = portion.unit
		_quantity = portion.quantity
		_source_id = portion.source_id


func can_execute() -> DropValidation:
	if _executing or _finished or _portion == null or not _portion.is_available():
		return DropValidation.invalid("This ingredient portion is no longer available")
	return _validate_current_state()


func execute() -> bool:
	if not can_execute().is_valid:
		return false
	_executing = true
	var accepted := _portion.commit(_apply)
	_executing = false
	_finished = accepted
	return accepted


func _target() -> Node2D:
	return _target_ref.get_ref() as Node2D if _target_ref != null else null


func _validate_current_state() -> DropValidation:
	if (_portion == null or _policy == null or _portion.item_id != _item_id
		or _portion.unit != _unit or _portion.quantity != _quantity or _portion.source_id != _source_id
		or _portion.source_ref == null):
		return DropValidation.invalid("The ingredient portion changed")
	var source := _portion.source_ref.get_ref() as Node2D
	var target := _target()
	if (not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion()
		or source.get_instance_id() != _source_id or not is_instance_valid(target)
		or not target.is_inside_tree() or source.get_tree() != target.get_tree()):
		return DropValidation.invalid("Ingredient source or target is unavailable")
	if _context_ref != null:
		var context := _context_ref.get_ref() as Node
		if (not is_instance_valid(context) or not context.is_inside_tree() or context.is_queued_for_deletion()
			or not context.is_ancestor_of(source) or not context.is_ancestor_of(target)):
			return DropValidation.invalid("Ingredient source or target left this stall")
	return _policy.validate(_item_id, _unit, _quantity, target)


func _apply() -> bool:
	# The provider has already claimed the token and debited stock. Recheck the
	# world here, without trying to claim or validate that reservation again.
	if not _validate_current_state().is_valid:
		return false
	var target := _target()
	if target is Kettle:
		return (target as Kettle).add_tea_leaves()
	return (target as Cup).add_relish(_item_id)
