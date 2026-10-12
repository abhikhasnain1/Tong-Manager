class_name StoveDial
extends Area2D

@export_node_path("Node2D") var burner_path: NodePath
@onready var burner: Burner = get_node(burner_path) as Burner
@onready var knob: Sprite2D = $Sprite
@onready var label: Label = $HeatLabel
var _turn: Tween
var _hovered := false

func _ready() -> void:
	input_event.connect(_on_input)
	burner.heat_changed.connect(_on_heat_changed)
	_on_heat_changed(burner.heat_level)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))

func cycle_heat() -> bool:
	var controller := burner.controller
	if controller == null or controller.current_mode != InteractionController.MODE_INTERACT or controller.is_dragging() or controller.has_active_action():
		return false
	if not controller.can_start_world_action():
		return false
	burner.set_heat((burner.heat_level + 1) % 4)
	return true

func _on_hover(entered: bool) -> void:
	_hovered = entered
	var controller := burner.controller
	if controller == null or controller.is_dragging() or controller.has_active_action():
		return
	var actionable := entered and controller.current_mode == InteractionController.MODE_INTERACT and controller.can_start_world_action()
	get_node("/root/CursorService").set_state(&"hover_actionable" if actionable else &"default")
	if actionable:
		controller.report_hint("Use · click dial to cycle heat: Off, Low, Medium, High")

func refresh_hover(_mode: StringName) -> void:
	if _hovered:
		_on_hover(true)

func _on_input(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if cycle_heat():
			get_viewport().set_input_as_handled()

func _on_heat_changed(level: int) -> void:
	if _turn != null:
		_turn.kill()
	_turn = create_tween()
	_turn.tween_property(knob, "rotation", deg_to_rad(float(level * 45)), .15)
	label.text = tr(["Off", "Low", "Medium", "High"][level])
