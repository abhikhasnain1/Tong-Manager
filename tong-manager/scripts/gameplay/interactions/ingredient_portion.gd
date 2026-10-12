class_name IngredientPortion
extends RefCounted

# One reversible reservation; it never owns the payload or its transient visual.
var item_id: StringName
var unit: StringName
var quantity := 1
var source_id := 0
var source_ref: WeakRef
var provider: PortionStockProvider
var token := 0
var finished := false
var _committing := false

func _init(p_item_id: StringName = &"", p_unit: StringName = &"", source: Node2D = null, p_provider: PortionStockProvider = null, p_token: int = 0) -> void:
	item_id = p_item_id
	unit = p_unit
	provider = p_provider
	token = p_token
	if is_instance_valid(source):
		source_ref = weakref(source)
		source_id = source.get_instance_id()

func is_available() -> bool:
	if finished or provider == null or source_ref == null:
		return false
	var source := source_ref.get_ref() as Node2D
	return (is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion()
		and provider.reservation_matches(token,item_id,unit,quantity,source_id))

func create_payload(visual: Node2D) -> HeldItemPayload:
	return HeldItemPayload.new(&"physical_source",item_id,quantity,visual,{
		"category":&"ingredient_portion", "item_id":item_id, "quantity":quantity,
		"unit":unit, "source_id":source_id, "portion":self, "transient":true,
		"cursor_state":&"teabag" if unit == &"teabag" else &"spoon",
		"cleanup_callback":Callable(self,"cancel"),
	})

func commit(apply: Callable) -> bool:
	if _committing or not is_available():
		return false
	_committing = true
	var accepted := provider.commit(token,apply)
	_committing = false
	if accepted:
		finished = true
	return accepted

func cancel() -> void:
	if finished or _committing:
		return
	finished = true
	if provider != null:
		provider.release(token)
