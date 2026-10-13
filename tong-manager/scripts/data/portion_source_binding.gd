class_name PortionSourceBinding
extends Resource
## Paths are relative to the Tong scene, then to the authored source item.

@export var node_path: NodePath
@export var item_id: StringName
@export var input_area_path: NodePath = ^"PlacementBody"
@export var placement_handle_path: NodePath = ^"PlacementHandle"
