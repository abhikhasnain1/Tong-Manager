extends Node

@onready var screen: Node2D = $TongDayScreen
@onready var kettle: Kettle = $TongDayScreen/WorldRoot/ToolLayer/KettleStation
@onready var stove: Stove = $TongDayScreen/WorldRoot/ToolLayer/StoveStation
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var tea_button: Button

func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(670, 24)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	var title := Label.new()
	title.text = "BREWING PREVIEW · seeded supplies"
	title.add_theme_font_size_override("font_size", 24)
	rows.add_child(title)
	var hint := Label.new()
	hint.text = "Click a dial to heat → add tea when boiling → wait for Tea ready.\nDrag by the handle · Aim the spout above a cup · Hold Space to pour\nRelease Space to stop · Release mouse to return / seat · Esc cancels · G toggles mode"
	rows.add_child(hint)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset preview · 750 ml water"
	reset.pressed.connect(reset_fixture)
	buttons.add_child(reset)
	tea_button = Button.new()
	tea_button.text = "Add tea leaves"
	tea_button.pressed.connect(func(): kettle.add_tea_leaves())
	buttons.add_child(tea_button)
	reset_fixture()

func reset_fixture() -> void:
	if controller.is_dragging():
		controller.cancel_drag()
	kettle.stop_pour()
	controller.set_mode(InteractionController.MODE_INTERACT)
	stove.burners[0].seat(kettle)
	for burner in stove.burners:
		burner.set_heat(0)
	kettle.volume_ml = 0.0
	kettle.contains_tea = false
	kettle.steep_progress = 0.0
	kettle.ready_heat_seconds = 0.0
	kettle.temperature = kettle.config.ambient_temperature
	kettle.add_water(750.0)
	for cup in screen.get_node("WorldRoot/ToolLayer/TrayStation/Cups").get_children():
		(cup as Cup).reset_clean()

func _process(_delta: float) -> void:
	tea_button.disabled = (
		kettle.temperature < kettle.config.boiling_temperature or kettle.contains_tea
		or kettle.volume_ml <= 0.0 or controller.is_dragging()
		or controller.current_mode != InteractionController.MODE_INTERACT
	)
