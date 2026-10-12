class_name TrayStation
extends Node2D

@export var tool_def: Resource
@export var cup_scene: PackedScene
# Initial supply poses only. These are not drop targets or a capacity limit.
@export var starting_cup_positions := PackedVector2Array([
	Vector2(-147.16666, -53.875), Vector2(0, -54.625), Vector2(147.16666, -55.375),
	Vector2(-166.83333, 33.375), Vector2(0, 33.125), Vector2(166.83331, 32.875),
])

@onready var interior_surface: PlacementSurface = $InteriorSurface
@onready var contents: Node2D = $Contents
@onready var table_footprint_bounds: CollisionPolygon2D = $TableFootprintBounds/CollisionPolygon2D


func _ready() -> void:
	assert(tool_def != null, "TrayStation requires a tool definition.")
	assert(cup_scene != null, "TrayStation requires a Cup scene.")
	assert(tool_def.starting_cup_count >= 0, "Starting cup supply cannot be negative.")
	assert(tool_def.starting_cup_count <= starting_cup_positions.size(),
		"Author an initial pose for each starting cup; placement capacity depends on free space.")
	for index in tool_def.starting_cup_count:
		var cup := cup_scene.instantiate() as Cup
		assert(cup != null, "TrayStation cup_scene root must be Cup.")
		cup.name = "Cup%d" % index
		cup.position = starting_cup_positions[index]
		contents.add_child(cup)


func get_contents() -> Node2D:
	return contents


func get_cups() -> Array[Cup]:
	var result: Array[Cup] = []
	for child in contents.get_children():
		if child is Cup:
			result.append(child)
	return result


func get_cup_count() -> int:
	return get_cups().size()


func get_available_clean_cup() -> Cup:
	for cup in get_cups():
		if cup.state == Cup.CupState.CLEAN:
			return cup
	return null


func get_table_footprint_world_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in table_footprint_bounds.polygon:
		result.append(table_footprint_bounds.to_global(point))
	return result
