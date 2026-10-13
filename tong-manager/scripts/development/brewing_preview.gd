extends Node

const ServiceZone := preload("res://scripts/development/brewing_preview_service_zone.gd")
const DevelopmentStock := preload("res://scripts/development/development_portion_stock.gd")
const ReadyItemZone := preload("res://scripts/development/ready_item_preview_zone.gd")

@onready var screen: Node2D = $TongDayScreen
@onready var kettle: Kettle = $TongDayScreen/WorldRoot/ToolLayer/KettleStation
@onready var stove: Stove = $TongDayScreen/WorldRoot/ToolLayer/StoveStation
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var reset_button: Button
var next_sample_button: Button
var stock_label: Label
var service_zone: ServiceZone
var ready_item_zone: ReadyItemZone
var portion_stock: PortionStockProvider = DevelopmentStock.new()

func _ready() -> void:
	_build_controls()
	screen.set_portion_provider(portion_stock)
	portion_stock.changed.connect(_update_stock_label)
	service_zone = ServiceZone.new()
	service_zone.name = "PreviewServiceTarget"
	service_zone.controller = controller
	service_zone.screen_root = screen
	# Keep the whole swinging bag clear of this temporary order card.
	service_zone.position = Vector2(1640, 470)
	screen.get_node("WorldRoot/DropZoneRoot").add_child(service_zone)
	controller.register_drop_zone(service_zone)
	ready_item_zone = ReadyItemZone.new()
	ready_item_zone.name = "PreviewReadyItemTarget"
	ready_item_zone.controller = controller
	ready_item_zone.screen_root = screen
	ready_item_zone.position = Vector2(1000, 450)
	screen.get_node("WorldRoot/DropZoneRoot").add_child(ready_item_zone)
	controller.register_drop_zone(ready_item_zone)
	_start_preview()

func _start_preview() -> void:
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
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24
	panel.offset_right = 332
	panel.offset_top = 88
	panel.offset_bottom = 88
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	var title := Label.new()
	title.name = "Title"
	title.text = "DEVELOPMENT PREVIEW"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 16)
	rows.add_child(title)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Brush to sway. Use to take one item."
	rows.add_child(hint)
	stock_label = Label.new()
	stock_label.name = "FixtureStock"
	stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_label.add_theme_font_size_override("font_size", 14)
	rows.add_child(stock_label)
	_update_stock_label()
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(buttons)
	reset_button = _button("ResetPreview", "Reset · new day", reset_fixture)
	buttons.add_child(reset_button)
	next_sample_button = _button("NextSample", "Next sample", _next_sample)
	buttons.add_child(next_sample_button)
	var fixture_note := Label.new()
	fixture_note.name = "FixtureNote"
	fixture_note.add_theme_font_size_override("font_size", 12)
	fixture_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixture_note.text = "Temporary stock and handoff fixtures."
	rows.add_child(fixture_note)

func _button(node_name: String, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button

func _blocked() -> bool:
	return controller.is_dragging() or controller.has_active_action()

func reset_fixture() -> void:
	# Fixture controls never interrupt a gesture or consume Space as ui_accept.
	if _blocked():
		return
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	for burner in stove.burners:
		burner.set_heat(0)
	kettle.discard_contents()
	kettle.temperature = kettle.config.ambient_temperature
	stove.burners[0].seat(kettle)
	for cup in screen.get_cups():
		(cup as Cup).reset_clean()
	_reset_supplies()
	if is_instance_valid(service_zone) and not service_zone.is_queued_for_deletion():
		service_zone.reset_samples()
	if is_instance_valid(ready_item_zone) and not ready_item_zone.is_queued_for_deletion():
		ready_item_zone.reset_fixture()
	for hanging in screen.hanging_sources:
		if is_instance_valid(hanging) and not hanging.is_queued_for_deletion():
			hanging.reset_sway()

func _reset_supplies() -> void:
	var game_state := get_node("/root/GameState")
	game_state.ensure_water_day()
	game_state.start_water_day(game_state.water_supply.day_id + 1)
	(portion_stock as DevelopmentPortionStock).reset_fixture()

func _next_sample() -> void:
	if _blocked():
		return
	if is_instance_valid(service_zone) and not service_zone.is_queued_for_deletion():
		service_zone.next_sample()

func _update_stock_label() -> void:
	if is_instance_valid(stock_label):
		stock_label.text = "Test stock · teabags %d\nSugar spoons %d · Milk spoons %d\nBananas %d · Biscuits %d" % [
			portion_stock.available(&"black_tea"), portion_stock.available(&"sugar"),
			portion_stock.available(&"condensed_milk"),
			portion_stock.available(&"banana"), portion_stock.available(&"biscuits"),
		]

func _process(_delta: float) -> void:
	var blocked := _blocked()
	reset_button.disabled = blocked
	next_sample_button.disabled = blocked
