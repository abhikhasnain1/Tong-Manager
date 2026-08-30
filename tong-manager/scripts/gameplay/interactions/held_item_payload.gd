class_name HeldItemPayload
extends Resource

@export var source: StringName = &""
@export var item_id: StringName = &""
@export_range(1, 999, 1, "or_greater") var quantity: int = 1
var world_node: Node
@export var metadata: Dictionary = {}


func _init(
	p_source: StringName = &"",
	p_item_id: StringName = &"",
	p_quantity: int = 1,
	p_world_node: Node = null,
	p_metadata: Dictionary = {}
) -> void:
	source = p_source
	item_id = p_item_id
	quantity = maxi(1, p_quantity)
	world_node = p_world_node
	metadata = p_metadata.duplicate(true)
