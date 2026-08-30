class_name PlaceableFootprint
extends Resource

@export var size: Vector2i = Vector2i.ONE
@export var can_rotate: bool = false


func supports_rotation(rotation_quarters: int) -> bool:
	return posmod(rotation_quarters, 2) == 0 or can_rotate


func dimensions(rotation_quarters: int = 0) -> Vector2i:
	if can_rotate and posmod(rotation_quarters, 2) == 1:
		return Vector2i(size.y, size.x)
	return size


func cells_from(origin_cell: Vector2i, rotation_quarters: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var footprint_size := dimensions(rotation_quarters)
	for y in footprint_size.y:
		for x in footprint_size.x:
			result.append(origin_cell + Vector2i(x, y))
	return result
