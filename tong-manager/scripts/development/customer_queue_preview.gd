extends Node
## Review authored schedules in the live stall without changing shared supplies.

const DAY_PATHS := [
	"res://data/examples/customer_days/authored_day_1.tres",
	"res://data/examples/customer_days/authored_day_2.tres",
	"res://data/balance/demo_day_1.tres",
]
const DAY_LABELS := ["Authored day 1 · quick review", "Authored day 2 · quick review", "Generated demo · normal timing"]

@export var preview_seed := 64

@onready var screen: Node2D = $TongDayScreen
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var queue: CustomerQueueManager
var day_picker: OptionButton
var restart_button: Button
var departure_buttons: Array[Button] = []
var dialogue_toggle: CheckButton
var motion_toggle: CheckButton
var status_label: Label
var event_label: Label
var selected_day := 0


func _ready() -> void:
	queue = screen.customer_queue
	_build_controls()
	queue.customer_spawned.connect(_on_spawned)
	queue.customer_timed_out.connect(_on_timed_out)
	queue.customer_removed.connect(_on_removed)
	queue.queue_completed.connect(_on_completed)
	restart_schedule()


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewUI"
	layer.layer = 110
	add_child(layer)
	var ui := Control.new()
	ui.name = "Root"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(18, 88)
	panel.custom_minimum_size.x = 230
	ui.add_child(panel)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f2e7cc")
	paper.border_color = Color("b6a17d")
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(10)
	paper.content_margin_left = 12
	paper.content_margin_right = 12
	paper.content_margin_top = 10
	paper.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", paper)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_label(rows, "CUSTOMER QUEUE REVIEW", 14)
	_label(rows, "Two places at the counter.\nArrivals wait when both are occupied.", 12)
	day_picker = OptionButton.new()
	day_picker.name = "DayPicker"
	for title in DAY_LABELS: day_picker.add_item(title)
	day_picker.add_theme_font_size_override("font_size", 12)
	day_picker.item_selected.connect(select_day)
	rows.add_child(day_picker)
	restart_button = _button(rows, "Restart this schedule", restart_schedule)
	dialogue_toggle = _toggle(rows, "Optional dialogue", func(enabled: bool):
		for actor in queue.get_active_customers(): actor.show_dialogue(enabled))
	motion_toggle = _toggle(rows, "Reduced motion on next restart", func(_enabled: bool): pass)
	status_label = _label(rows, "", 12)
	status_label.custom_minimum_size = Vector2(206, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for slot in range(2):
		var index := slot
		var button := _button(rows, "Preview %s departure" % ("left" if slot == 0 else "right"), func(): preview_departure(index))
		departure_buttons.append(button)
	event_label = _label(rows, "", 12)
	event_label.custom_minimum_size = Vector2(206, 48)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(rows, "Quick days use shorter patience.\nOpen the Khata: time keeps moving.\nDeparture buttons are review tools;\nthey do not serve or pay an order.\nRestart preserves supplies and cups.", 11)


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("443a2e"))
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _toggle(parent: Node, text: String, action: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 12)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(key, Color("443a2e"))
	toggle.toggled.connect(action)
	parent.add_child(toggle)
	return toggle


func _blocked() -> bool:
	return controller.has_active_action() or controller.is_dragging() or controller.is_world_input_blocked()


func select_day(index: int) -> void:
	if index < 0 or index >= DAY_PATHS.size() or _blocked():
		day_picker.select(selected_day)
		return
	selected_day = index
	day_picker.select(index)
	restart_schedule()


func restart_schedule() -> void:
	if _blocked(): return
	queue.reduced_motion = motion_toggle.button_pressed
	var config := load(DAY_PATHS[selected_day]) as Resource
	if not screen.start_customer_queue(config, preview_seed):
		event_label.text = "Schedule not started: " + "; ".join(queue.get_snapshot().errors)
		return
	event_label.text = "Schedule restarted. Supplies unchanged."


func preview_departure(slot: int) -> void:
	if _blocked(): return
	var actor := _actor_in_slot(slot)
	if actor == null or not actor.is_serve_enabled(): return
	actor.leave()
	event_label.text = "Preview departure only; no order was served."


func _actor_in_slot(slot: int) -> Customer:
	# Layout order is left to right, independently of arrival/instance order.
	var container := screen.get_node_or_null("WorldRoot/CustomerLayer/CustomerQueueSlots")
	if container == null or container.is_queued_for_deletion(): return null
	var markers: Array[Marker2D] = []
	for child in container.get_children():
		if child is Marker2D and not child.is_queued_for_deletion(): markers.append(child as Marker2D)
	if slot < 0 or slot >= markers.size(): return null
	var marker := markers[slot]
	for actor in queue.get_active_customers():
		if actor.global_position.distance_to(marker.global_position) < 1.0: return actor
	return null


func _process(_delta: float) -> void:
	if queue == null or status_label == null: return
	var blocked := _blocked()
	day_picker.disabled = blocked
	restart_button.disabled = blocked
	dialogue_toggle.disabled = blocked
	motion_toggle.disabled = blocked
	for slot in departure_buttons.size():
		var actor := _actor_in_slot(slot)
		departure_buttons[slot].disabled = blocked or actor == null or not actor.is_serve_enabled()
	var lines: Array[String] = []
	var snapshot := queue.get_snapshot()
	lines.append("Arrived %d / %d · still due %d" % [snapshot.get("spawned", 0), snapshot.get("total", 0), snapshot.get("pending", 0)])
	for slot in range(2):
		var actor := _actor_in_slot(slot)
		var text := "empty"
		if actor != null:
			var order := queue.get_order_for_customer(actor)
			text = String(order.request_id) if order != null else "arriving"
		lines.append("%s: %s" % ["Left" if slot == 0 else "Right", text])
	status_label.text = "\n".join(lines)


func _on_spawned(actor: Customer, _entry: Dictionary) -> void:
	actor.show_dialogue(dialogue_toggle.button_pressed)
	event_label.text = "A customer is walking up."


func _on_timed_out(_actor: Customer, _entry: Dictionary) -> void:
	event_label.text = "Patience ran out. No payment or bad review."


func _on_removed(_entry: Dictionary, _reason: StringName) -> void:
	event_label.text = "The place is free for the next arrival."


func _on_completed(_summary: Dictionary) -> void:
	event_label.text = "Schedule complete. No more arrivals."
