extends Node

const ServiceZone := preload("res://scripts/development/brewing_preview_service_zone.gd")

@onready var screen: Node2D = $TongDayScreen
@onready var kettle: Kettle = $TongDayScreen/WorldRoot/ToolLayer/KettleStation
@onready var stove: Stove = $TongDayScreen/WorldRoot/ToolLayer/StoveStation
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var tea_button: Button
var reset_button: Button
var next_sample_button: Button
var service_zone: ServiceZone

func _ready() -> void:
	_build_controls()
	service_zone = ServiceZone.new()
	service_zone.name = "PreviewServiceTarget"
	service_zone.controller = controller
	service_zone.screen_root = screen
	service_zone.position = Vector2(1640, 400)
	screen.get_node("WorldRoot/DropZoneRoot").add_child(service_zone)
	controller.register_drop_zone(service_zone)
	reset_fixture()

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewUI"
	layer.layer = 15
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = 18
	panel.offset_bottom = 18
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	margin.add_child(rows)
	var title := Label.new()
	title.text = "TABLE & BREWING REVIEW"
	title.add_theme_font_size_override("font_size", 20)
	rows.add_child(title)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 16)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "G: Organize to move cups, tray, tea, sugar or milk. Green fits; red returns.\nG: Interact for water, brewing, cup service and disposal. Esc cancels.\nHold Space to pour from the kettle. Drag vessels to Discard.\nIn Organize, move cups or containers onto/off the tray. No slots."
	rows.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	rows.add_child(buttons)
	reset_button = _button("ResetPreview", "Reset preview · new day", reset_fixture)
	buttons.add_child(reset_button)
	tea_button = _button("AddTeaFixture", "Add tea · fixture", _add_tea_fixture)
	buttons.add_child(tea_button)
	next_sample_button = _button("NextSample", "Next sample customer", _next_sample)
	buttons.add_child(next_sample_button)
	var fixture_note := Label.new()
	fixture_note.add_theme_font_size_override("font_size", 14)
	fixture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixture_note.text = "Tea is a stock fixture; sample customers have no payments or reputation economy."
	rows.add_child(fixture_note)

func _button(node_name: String, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	return button

func _blocked() -> bool:
	return controller.is_dragging() or controller.has_active_action()

func reset_fixture() -> void:
	# Fixture controls never interrupt a gesture or consume Space as ui_accept.
	if _blocked():
		return
	controller.set_mode(InteractionController.MODE_INTERACT)
	for burner in stove.burners:
		burner.set_heat(0)
	kettle.discard_contents()
	kettle.temperature = kettle.config.ambient_temperature
	stove.burners[0].seat(kettle)
	for cup in screen.get_cups():
		(cup as Cup).reset_clean()
	var game_state := get_node("/root/GameState")
	game_state.ensure_water_day()
	game_state.start_water_day(game_state.water_supply.day_id + 1)
	service_zone.reset_samples()

func _add_tea_fixture() -> void:
	if _blocked() or not _can_add_tea():
		return
	kettle.add_tea_leaves()

func _next_sample() -> void:
	if _blocked():
		return
	service_zone.next_sample()

func _can_add_tea() -> bool:
	return (
		kettle.temperature >= kettle.config.boiling_temperature and not kettle.contains_tea
		and kettle.volume_ml > 0.0
		and controller.current_mode == InteractionController.MODE_INTERACT
	)

func _process(_delta: float) -> void:
	var blocked := _blocked()
	reset_button.disabled = blocked
	next_sample_button.disabled = blocked
	tea_button.disabled = blocked or not _can_add_tea()
