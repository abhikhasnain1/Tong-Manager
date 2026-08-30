class_name InteractionCommand
extends Resource


func can_execute(_game_state: Node) -> bool:
	return false


func execute(_game_state: Node) -> void:
	pass


func get_feedback_key() -> StringName:
	return &"interaction_unavailable"
