class_name TongHud
extends Control

const MODE_INTERACT := &"interact"
const MODE_ORGANIZE := &"organize"
const MODE_NEUTRAL := &"neutral"
const ACTIVE_MODE_COLOR := Color.WHITE
const INACTIVE_MODE_COLOR := Color(0.83, 0.80, 0.74, 1.0)

@export_group("Intent Controls")
@export var organize_label_text := "Organize"
@export var use_label_text := "Use"
@export_range(160.0, 260.0, 1.0) var intent_button_width := 208.0
@export_range(48.0, 72.0, 1.0) var intent_button_height := 56.0
@export_range(8.0, 32.0, 1.0) var intent_button_gap := 16.0
@export_range(8.0, 40.0, 1.0) var intent_top_margin := 16.0
@export var neutral_hint := "Choose Organize or Use to begin."
@export var organize_hint := "Drag whole objects onto the table or tray."
@export var use_hint := "Take one portion, use a tool, or serve a cup."

@onready var clock_label: Label = %ClockLabel
@onready var cash_label: Label = %CashLabel
@onready var interact_mode_label: Label = %InteractModeLabel
@onready var organize_mode_label: Label = %OrganizeModeLabel
@onready var organize_mode_button: Button = %OrganizeModeButton
@onready var use_mode_button: Button = %UseModeButton
@onready var intent_state_label: Label = %IntentStateLabel
@onready var context_hint_label: Label = %ContextHintLabel

var current_mode: StringName = MODE_NEUTRAL
var _controller: InteractionController
var _finance: FinanceState


func _ready() -> void:
	_configure_intent_layout()
	_prepare_button(organize_mode_button, MODE_ORGANIZE)
	_prepare_button(use_mode_button, MODE_INTERACT)
	set_mode(current_mode)


func _configure_intent_layout() -> void:
	var width := intent_button_width * 2.0 + intent_button_gap
	var controls := $IntentControls as Control
	controls.offset_left = -width * 0.5
	controls.offset_right = width * 0.5
	controls.offset_top = intent_top_margin
	controls.offset_bottom = intent_top_margin + intent_button_height + 94.0
	var buttons := $IntentControls/ModeButtons as HBoxContainer
	buttons.size = Vector2(width, intent_button_height)
	buttons.add_theme_constant_override("separation", roundi(intent_button_gap))
	for button in [organize_mode_button, use_mode_button]:
		button.custom_minimum_size = Vector2(intent_button_width, intent_button_height)
	for label in [organize_mode_label, interact_mode_label]:
		label.offset_left = intent_button_height - 3.0
	organize_mode_label.text = organize_label_text
	interact_mode_label.text = use_label_text
	intent_state_label.position.y = intent_button_height + 5.0
	intent_state_label.size.x = width
	context_hint_label.position.y = intent_button_height + 28.0
	context_hint_label.size.x = width


func bind_controller(value: InteractionController) -> void:
	if _controller != value and is_instance_valid(_controller):
		if _controller.mode_changed.is_connected(set_mode):
			_controller.mode_changed.disconnect(set_mode)
		if _controller.hint_changed.is_connected(set_context_hint):
			_controller.hint_changed.disconnect(set_context_hint)
	_controller = value
	if not is_instance_valid(_controller):
		return
	if not _controller.mode_changed.is_connected(set_mode):
		_controller.mode_changed.connect(set_mode)
	if not _controller.hint_changed.is_connected(set_context_hint):
		_controller.hint_changed.connect(set_context_hint)
	set_mode(_controller.current_mode)
	set_context_hint(_controller.current_hint)


func set_clock_text(value: String) -> void:
	clock_label.text = value


func set_cash(value: int) -> void:
	cash_label.text = "৳ %d" % value


func bind_finance(value: FinanceState) -> void:
	if _finance != null and _finance.changed.is_connected(_refresh_cash):
		_finance.changed.disconnect(_refresh_cash)
	_finance = value
	_connect_finance()


func _connect_finance() -> void:
	if _finance == null or not is_inside_tree(): return
	if not _finance.changed.is_connected(_refresh_cash): _finance.changed.connect(_refresh_cash)
	_refresh_cash()


func _refresh_cash() -> void:
	if _finance != null and is_node_ready() and is_inside_tree(): set_cash(_finance.cash_on_hand)


func _enter_tree() -> void:
	if is_node_ready(): _connect_finance.call_deferred()


func _exit_tree() -> void:
	if _finance != null and _finance.changed.is_connected(_refresh_cash):
		_finance.changed.disconnect(_refresh_cash)


func set_mode(mode: StringName) -> void:
	assert(mode in [MODE_NEUTRAL, MODE_INTERACT, MODE_ORGANIZE], "Unsupported HUD mode: %s" % mode)
	current_mode = mode
	if not is_instance_valid(organize_mode_button):
		return
	interact_mode_label.modulate = ACTIVE_MODE_COLOR if mode == MODE_INTERACT else INACTIVE_MODE_COLOR
	organize_mode_label.modulate = ACTIVE_MODE_COLOR if mode == MODE_ORGANIZE else INACTIVE_MODE_COLOR
	organize_mode_button.set_pressed_no_signal(mode == MODE_ORGANIZE)
	use_mode_button.set_pressed_no_signal(mode == MODE_INTERACT)
	organize_mode_button.queue_redraw()
	use_mode_button.queue_redraw()
	intent_state_label.text = "NEUTRAL · no action selected" if mode == MODE_NEUTRAL else "Click the selected mode again to return to Neutral"
	set_context_hint(_controller.current_hint if is_instance_valid(_controller) else "")


func set_context_hint(value: String) -> void:
	if not is_instance_valid(context_hint_label):
		return
	if not value.is_empty():
		context_hint_label.text = value
	elif current_mode == MODE_ORGANIZE:
		context_hint_label.text = organize_hint
	elif current_mode == MODE_INTERACT:
		context_hint_label.text = use_hint
	else:
		context_hint_label.text = neutral_hint


func _prepare_button(button: Button, mode: StringName) -> void:
	# The button's visible footprint alone blocks world input. Its label ignores
	# mouse events; no full-screen container captures clicks around the controls.
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.draw.connect(_draw_mode_button.bind(button, mode))
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.pressed.connect(_select_mode.bind(mode))


func _select_mode(mode: StringName) -> void:
	if is_instance_valid(_controller):
		_controller.select_mode(mode)
		# A modal can reject the request after Button toggled its local state.
		set_mode(_controller.current_mode)


func _draw_mode_button(button: Button, mode: StringName) -> void:
	var selected := current_mode == mode
	var fill := Color("715739") if selected else Color("302a25")
	var edge := Color("efc77e") if selected else Color("847460")
	if button.is_hovered():
		fill = fill.lightened(0.10)
		edge = edge.lightened(0.12)
	var label_shape := StyleBoxFlat.new()
	label_shape.bg_color = fill
	label_shape.border_color = edge
	label_shape.set_border_width_all(2 if selected else 1)
	label_shape.set_corner_radius_all(6)
	var height := button.size.y
	var center := Vector2(height * 0.5 - 1.0, height * 0.5)
	var radius := height * 0.5 - 3.0
	var label_left := height * 0.75
	button.draw_style_box(label_shape, Rect2(label_left,5,button.size.x-label_left,height-10))
	button.draw_circle(center,radius,fill)
	button.draw_arc(center,radius,0,TAU,48,edge,2 if selected else 1,true)
	var ink := ACTIVE_MODE_COLOR if selected else INACTIVE_MODE_COLOR
	var icon_scale := height / 56.0
	button.draw_set_transform(center - Vector2(27,28) * icon_scale, 0, Vector2.ONE * icon_scale)
	if mode == MODE_ORGANIZE:
		# Four directional arrows communicate movement without a font glyph.
		button.draw_line(Vector2(15,28),Vector2(39,28),ink,2,true)
		button.draw_line(Vector2(27,16),Vector2(27,40),ink,2,true)
		for points in [PackedVector2Array([Vector2(20,23),Vector2(15,28),Vector2(20,33)]), PackedVector2Array([Vector2(34,23),Vector2(39,28),Vector2(34,33)]), PackedVector2Array([Vector2(22,21),Vector2(27,16),Vector2(32,21)]), PackedVector2Array([Vector2(22,35),Vector2(27,40),Vector2(32,35)])]:
			button.draw_polyline(points,ink,2,true)
	else:
		# A spoon and its single bowl match the portion interaction.
		button.draw_line(Vector2(19,38),Vector2(29,25),ink,3,true)
		button.draw_arc(Vector2(31,22),6,0,TAU,24,ink,2,true)
	button.draw_set_transform(Vector2.ZERO)
