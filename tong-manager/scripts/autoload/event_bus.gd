extends Node


signal toast_requested(message_key: String)


func emit_toast(message_key: String) -> void:
	toast_requested.emit(message_key)
