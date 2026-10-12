class_name PortionStockProvider
extends RefCounted

# Injectable source contract. The normal scene has no ingredient stock provider
# until the shared inventory/ingredient commands supply one.
signal changed

func remaining(_item_id: StringName) -> int:
	return 0

func available(_item_id: StringName) -> int:
	return 0

func reserve(_item_id: StringName, _unit: StringName, _quantity: int, _source_id: int) -> int:
	return 0

func reservation_matches(_token: int, _item_id: StringName, _unit: StringName, _quantity: int, _source_id: int) -> bool:
	return false

func commit(_token: int, _apply: Callable) -> bool:
	return false

func release(_token: int) -> void:
	pass
