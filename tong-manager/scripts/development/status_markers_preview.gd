extends Node
## Vessel-only visual fixtures. Production inventory and day water are untouched.

const EXAMPLES := [
	"Brewed tea · warm and cold cups",
	"Water warming on the stove",
	"Bubbling water",
	"Steeping · burner off",
	"Oversteeped and dirty",
	"Dry ingredients and empty vessels",
	"Extra bags and partial spoonfuls",
]

@onready var screen: Node2D = $TongDayScreen
@onready var kettle: Kettle = $TongDayScreen/WorldRoot/ToolLayer/KettleStation
@onready var stove: Stove = $TongDayScreen/WorldRoot/ToolLayer/StoveStation
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var scenario_picker: OptionButton
var clear_button: Button
var example_index := 0


func _ready() -> void:
	_build_controls()
	apply_example(0)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewUI"
	layer.layer = 15
	add_child(layer)
	var ui := Control.new()
	ui.name = "Root"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(22, 86)
	panel.custom_minimum_size.x = 230
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	var title := Label.new()
	title.text = "DEVELOPMENT · MARKERS"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 14)
	rows.add_child(title)
	scenario_picker = OptionButton.new()
	scenario_picker.name = "Example"
	scenario_picker.focus_mode = Control.FOCUS_NONE
	scenario_picker.add_theme_font_size_override("font_size", 12)
	for caption in EXAMPLES:
		scenario_picker.add_item(caption)
	scenario_picker.item_selected.connect(apply_example)
	rows.add_child(scenario_picker)
	clear_button = Button.new()
	clear_button.name = "ClearVessels"
	clear_button.text = "Reset vessels · play normally"
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.add_theme_font_size_override("font_size", 12)
	clear_button.pressed.connect(clear_vessels)
	rows.add_child(clear_button)
	var note := Label.new()
	note.name = "FixtureNote"
	note.text = "Vessel fixtures · supplies unchanged.\nReset makes clean, empty sample vessels."
	note.add_theme_font_size_override("font_size", 11)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(note)


func _blocked() -> bool:
	return controller.is_dragging() or controller.has_active_action() or controller.is_world_input_blocked()


func _process(_delta: float) -> void:
	var blocked := _blocked()
	scenario_picker.disabled = blocked
	clear_button.disabled = blocked


func clear_vessels() -> void:
	if _blocked():
		return
	for burner in stove.burners:
		burner.set_heat(0)
	kettle.discard_contents()
	kettle.temperature = kettle.config.ambient_temperature
	stove.burners[0].seat(kettle)
	for cup in screen.get_cups():
		cup.reset_clean()
	_refresh_badges()


func apply_example(index: int) -> void:
	if _blocked() or index < 0 or index >= EXAMPLES.size():
		return
	clear_vessels()
	example_index = index
	scenario_picker.select(index)
	var cups: Array[Cup] = screen.get_cups()
	if cups.size() < 3:
		return
	match index:
		1, 2:
			kettle.add_water(1200.0)
			kettle.apply_heat(4.0 if index == 1 else 20.0, 1.0)
			stove.burners[0].set_heat(1 if index == 1 else 3)
			cups[0].receive_liquid(&"black_tea", 150.0, 67.0)
			cups[0].add_relish(&"condensed_milk")
			cups[1].add_relish(&"sugar")
			cups[2].receive_liquid(&"black_tea", 65.0, 30.0)
		3:
			_prepare_batch(1, false)
			cups[0].add_relish(&"sugar")
			cups[0].add_relish(&"condensed_milk")
			cups[1].receive_liquid(&"black_tea", 125.0, 68.0)
			cups[2].receive_liquid(&"black_tea", 230.0, 30.0)
		4:
			_prepare_batch()
			kettle.advance_brewing(kettle.config.oversteep_seconds)
			cups[0].receive_liquid(&"black_tea", 100.0, 30.0)
			cups[1].receive_liquid(&"black_tea", 250.0, 65.0)
			cups[1].mark_served()
			cups[1].mark_dirty()
			cups[1].discard_contents()
		5:
			cups[0].add_relish(&"sugar")
			cups[0].add_relish(&"condensed_milk")
			cups[1].receive_liquid(&"black_tea", 1.0, 30.0)
			cups[1].mark_served()
			cups[1].mark_dirty()
			cups[1].discard_contents()
		6:
			_prepare_batch(5)
			kettle.apply_ingredient(&"sugar", 2, &"mix")
			kettle.apply_ingredient(&"condensed_milk", 1, &"mix")
			cups[0].add_relish(&"sugar")
			# Use the normal action lock for this controlled fixture transfer, then
			# restore the player's chosen mode before returning to live review.
			var previous_mode := controller.current_mode
			controller.set_mode(InteractionController.MODE_INTERACT)
			var started := kettle.start_pour(cups[0])
			if started:
				kettle.update_pour(250.0 / kettle.config.pour_rate_ml)
				kettle.stop_pour()
			controller.set_mode(previous_mode)
			assert(started, "The fractional marker example must complete its controlled pour")
			cups[1].receive_liquid(&"black_tea", 125.0, 30.0)
			cups[1].apply_ingredient(&"sugar", 4, &"mix")
			cups[1].apply_ingredient(&"condensed_milk", 2, &"mix")
			cups[2].receive_liquid(&"black_tea", 75.0, 65.0, {&"condensed_milk": 0.001})
		_:
			_prepare_batch()
			cups[0].receive_liquid(&"black_tea", 250.0, 70.0)
			cups[0].add_relish(&"sugar")
			cups[0].add_relish(&"condensed_milk")
			cups[1].receive_liquid(&"black_tea", 125.0, 62.0)
			cups[1].add_relish(&"sugar")
			cups[2].receive_liquid(&"black_tea", 70.0, 30.0)
	_refresh_badges()


func _prepare_batch(bags := 1, finish_brewing := true) -> void:
	kettle.add_water(1000.0)
	kettle.apply_heat(20.0, 1.0)
	kettle.apply_ingredient(&"black_tea", bags, &"infuse", &"black_tea")
	if finish_brewing:
		kettle.advance_brewing(kettle.config.steep_seconds)


func _refresh_badges() -> void:
	var layer := screen.get_node_or_null("HUDLayer/RootUI/StatusBadges")
	if is_instance_valid(layer):
		layer.refresh()
