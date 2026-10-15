class_name WaterDrum
extends Area2D

var controller: InteractionController
var supply: DailyWaterSupply
var _active_payload: HeldItemPayload
var _origin_parent: Node
var _origin_transform := Transform2D.IDENTITY
var _hovered := false

@onready var remaining_label: Label = $Remaining
@onready var icon: Sprite2D = $Icon


func _ready() -> void:
	var game_state := get_node("/root/GameState")
	game_state.ensure_water_day(_find_day_config())
	supply = game_state.water_supply
	supply.remaining_changed.connect(_update_remaining)
	_update_remaining(supply.remaining_ml)
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _find_day_config() -> Resource:
	# Children become ready before the owning screen, so use its authored config
	# when this first source initializes the day. Reparenting never starts a day.
	var ancestor := get_parent()
	while ancestor != null:
		var candidate: Variant = ancestor.get("day_config")
		if candidate is Resource:
			return candidate as Resource
		ancestor = ancestor.get_parent()
	return null


func bind_controller(value: InteractionController) -> void:
	if is_instance_valid(controller) and controller.drag_canceled.is_connected(_on_drag_canceled):
		controller.drag_canceled.disconnect(_on_drag_canceled)
	if is_instance_valid(controller) and controller.mode_changed.is_connected(_refresh_hover):
		controller.mode_changed.disconnect(_refresh_hover)
	controller = value
	if is_instance_valid(controller):
		controller.drag_canceled.connect(_on_drag_canceled)
		controller.mode_changed.connect(_refresh_hover)


func begin_drag(viewport_position: Vector2) -> bool:
	if (not is_instance_valid(controller) or controller.current_mode != InteractionController.MODE_INTERACT
		or not controller.can_start_world_action()
		or controller.has_active_action() or controller.is_dragging() or _active_payload != null):
		return false
	var token := supply.reserve_transfer(self)
	if token == 0:
		return false
	_origin_parent = get_parent()
	_origin_transform = transform
	_active_payload = HeldItemPayload.new(&"daily_water", &"water", 1, self, {
		"category": &"water_supply", "water_token": token,
	})
	if controller.start_drag(_active_payload, self, viewport_position):
		return true
	supply.cancel_transfer(token)
	_active_payload = null
	return false


func is_active_payload(payload: HeldItemPayload) -> bool:
	return payload != null and payload == _active_payload and payload.world_node == self


func finish_transfer(payload: HeldItemPayload) -> void:
	if not is_active_payload(payload):
		return
	supply.cancel_transfer(int(payload.metadata.get("water_token", 0)))
	_active_payload = null
	if is_instance_valid(_origin_parent) and _origin_parent.is_inside_tree():
		if get_parent() != _origin_parent:
			reparent(_origin_parent, true)
		transform = _origin_transform


func _on_drag_canceled(payload: HeldItemPayload) -> void:
	finish_transfer(payload)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if begin_drag(event.position):
			get_viewport().set_input_as_handled()


func _on_hover(entered: bool) -> void:
	_hovered = entered
	if is_instance_valid(controller) and not controller.is_dragging() and not controller.has_active_action():
		var actionable := entered and controller.can_start_world_action() and controller.current_mode == InteractionController.MODE_INTERACT and supply.remaining_ml > 0.0
		get_node("/root/CursorService").set_state(&"hover_actionable" if actionable else &"default")
		if actionable:
			controller.report_hint("Use · drag water jug to kettle to fill")


func _refresh_hover(_mode: StringName) -> void:
	if _hovered:
		_on_hover(true)


func _update_remaining(amount_ml: float) -> void:
	remaining_label.text = "Water · %d ml" % roundi(amount_ml)
	icon.modulate = Color.WHITE if amount_ml > 0.0 else Color(0.65, 0.65, 0.65, 1.0)


func _exit_tree() -> void:
	# A live drag reparents the icon, so ordinary tree-exit must not cancel its token.
	if is_queued_for_deletion() and _active_payload != null and supply != null:
		supply.cancel_transfer(int(_active_payload.metadata.get("water_token", 0)))
