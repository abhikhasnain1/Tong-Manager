extends Node

@export var initial_screen: PackedScene

@onready var current_screen: Node = $SceneRoot/CurrentScreen

func _ready() -> void:
	if initial_screen == null:
		return

	var screen := initial_screen.instantiate()
	current_screen.add_child(screen)
