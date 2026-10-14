extends Node
## Customer presentation review; synthetic tokens never consume stock or pay money.

const ZONE := preload("res://scripts/development/customer_scene_preview_zone.gd")
const SAMPLE_KINDS: Array[StringName] = [&"tea", &"cold", &"banana", &"biscuits", &"wrong"]
const SAMPLE_LABELS := ["Warm tea", "Cold tea", "Banana", "Biscuit", "Wrong item"]
const TEA_ICON := preload("res://assets/art/toolkit/cup_clean_provisional.png")
const BANANA_ICON := preload("res://assets/art/icons/banana_ready_provisional.png")
const BISCUIT_ICON := preload("res://assets/art/icons/biscuits_ready_provisional.png")

@onready var screen: Node2D = $TongDayScreen
@onready var controller: InteractionController = $TongDayScreen/InteractionController
var customers: Array[Customer] = []
var zones: Array[DropZone] = []
var sample_buttons: Dictionary = {}
var count_picker: OptionButton
var dialogue_toggle: CheckButton
var motion_toggle: CheckButton
var status_label: Label
var selected_count := 2
var _sequence := 0
var _handoff_sequence := 0
var _last_results: Dictionary = {}
var _action_buttons: Array[Button] = []
var _frame_image: Image


func _ready() -> void:
	_frame_image = (screen.get_node("WorldRoot/FrameFront") as Sprite2D).texture.get_image()
	customers.assign([
		screen.get_node("WorldRoot/CustomerLayer/CustomerA"),
		screen.get_node("WorldRoot/CustomerLayer/CustomerB"),
	])
	for index in customers.size():
		var zone := ZONE.new()
		zone.name = "CustomerSampleZone%d" % index
		customers[index].add_child(zone)
		zone.configure(self, customers[index], index, controller)
		zones.append(zone)
	_build_controls()
	controller.set_mode(InteractionController.MODE_INTERACT)
	reset_customers()


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
	panel.custom_minimum_size.x = 225
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
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 5)
	panel.add_child(rows)
	_label(rows, "CUSTOMER SCENE REVIEW", 14)
	_label(rows, "Drag a sample onto a customer.\nA wants tea · B wants a banana.", 12)
	count_picker = OptionButton.new()
	count_picker.add_item("One sample customer")
	count_picker.add_item("Two sample customers")
	count_picker.select(1)
	count_picker.item_selected.connect(func(index: int): set_customer_count(index + 1))
	rows.add_child(count_picker)
	dialogue_toggle = CheckButton.new()
	dialogue_toggle.text = "Optional dialogue"
	dialogue_toggle.add_theme_color_override("font_color", Color("443a2e"))
	dialogue_toggle.add_theme_color_override("font_hover_color", Color("443a2e"))
	dialogue_toggle.add_theme_color_override("font_pressed_color", Color("443a2e"))
	dialogue_toggle.toggled.connect(func(enabled: bool):
		for index in customers.size():
			if is_instance_valid(customers[index]): customers[index].show_dialogue(enabled))
	rows.add_child(dialogue_toggle)
	motion_toggle = CheckButton.new()
	motion_toggle.text = "Reduced motion"
	motion_toggle.add_theme_color_override("font_color", Color("443a2e"))
	motion_toggle.add_theme_color_override("font_hover_color", Color("443a2e"))
	motion_toggle.add_theme_color_override("font_pressed_color", Color("443a2e"))
	motion_toggle.toggled.connect(func(enabled: bool):
		for index in customers.size():
			if is_instance_valid(customers[index]): customers[index].reduced_motion = enabled
		reset_customers())
	rows.add_child(motion_toggle)
	for index in SAMPLE_KINDS.size():
		var kind := SAMPLE_KINDS[index]
		var button := Button.new()
		button.name = String(kind).capitalize().replace(" ", "")
		button.text = SAMPLE_LABELS[index] + "  ↗"
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if start_sample_drag(kind, button.get_global_mouse_position()): button.accept_event())
		rows.add_child(button)
		sample_buttons[kind] = button
	_button(rows, "Replay arrival / new samples", reset_customers)
	_button(rows, "Turn and leave", func():
		for index in customers.size():
			if is_instance_valid(customers[index]) and customers[index].is_inside_tree() and customers[index].visible: customers[index].leave())
	status_label = _label(rows, "", 12)
	status_label.custom_minimum_size = Vector2(201, 52)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(rows, "Sample results only.\nLive supplies and payments unchanged.\nEsc cancels a sample drag.", 11)


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("443a2e"))
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	parent.add_child(button)
	_action_buttons.append(button)


func _blocked() -> bool:
	return controller.has_active_action() or controller.is_world_input_blocked()


func _process(_delta: float) -> void:
	var blocked := _blocked() or controller.is_dragging()
	for button: Button in sample_buttons.values():
		button.disabled = blocked or controller.current_mode != InteractionController.MODE_INTERACT
	for button in _action_buttons: button.disabled = blocked
	count_picker.disabled = blocked
	dialogue_toggle.disabled = blocked
	motion_toggle.disabled = blocked


func set_customer_count(count: int) -> void:
	if count not in [1, 2] or _blocked() or controller.is_dragging(): return
	selected_count = count
	count_picker.select(count - 1)
	reset_customers()


func reset_customers() -> void:
	if _blocked() or controller.is_dragging(): return
	_sequence += 1
	_last_results.clear()
	var catalog := get_node("/root/Catalog")
	for index in customers.size():
		if not is_instance_valid(customers[index]): continue
		var customer := customers[index]
		if not is_instance_valid(customer) or not customer.is_inside_tree() or customer.is_queued_for_deletion(): continue
		customer.reset_presentation()
		customer.visible = index < selected_count
		customer.position.x = 960.0 if selected_count == 1 else (760.0 if index == 0 else 1160.0)
		var request_id := &"tea_cha_no_sugar" if index == 0 else &"ready_banana"
		var request := customer.customer_def.get_request(request_id)
		var order := OrderState.create(StringName("scene_sample_%d_%d" % [_sequence, index]),
			customer.customer_def.id, request.snapshot(catalog), 0.0)
		customer.set_order(order)
		customer.visible = index < selected_count
		customer.set_dialogue("One tea, please." if index == 0 else "A banana, please.")
		customer.show_dialogue(dialogue_toggle.button_pressed)
		if customer.visible: customer.arrive()
	status_label.text = "New sample orders.\nDrop anywhere on a customer's body."


func start_sample_drag(kind: StringName, viewport_position: Vector2) -> bool:
	if kind not in SAMPLE_KINDS or _blocked() or controller.is_dragging() or controller.current_mode != InteractionController.MODE_INTERACT:
		return false
	var visual := Node2D.new()
	visual.name = "SampleToken"
	var sprite := Sprite2D.new()
	sprite.texture = BANANA_ICON if kind == &"banana" else (BISCUIT_ICON if kind in [&"biscuits", &"wrong"] else TEA_ICON)
	sprite.scale = Vector2.ONE * (58.0 / maxf(sprite.texture.get_width(), sprite.texture.get_height()))
	visual.add_child(sprite)
	var label := Label.new()
	label.text = SAMPLE_LABELS[SAMPLE_KINDS.find(kind)]
	label.position = Vector2(-40, 32)
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(label)
	var payload := HeldItemPayload.new(&"customer_scene_fixture", kind, 1, visual, {
		"category": &"customer_scene_fixture", "transient": true,
		"preview_id": get_instance_id(), "sample_kind": kind,
	})
	if not controller.start_drag(payload, visual, viewport_position):
		visual.free()
		return false
	return true


func pick_customer_at(viewport_position: Vector2) -> int:
	if controller.is_world_input_blocked() or controller.is_pointer_over_ui_at(viewport_position): return -1
	# The roof, counter and swinging stock are in front of the customers.
	# A transparent sprite rectangle must not swallow the body behind it.
	var frame := screen.get_node("WorldRoot/FrameFront") as Sprite2D
	var frame_point := frame.get_global_transform_with_canvas().affine_inverse() * viewport_position
	if _frame_image != null and Rect2(Vector2.ZERO, _frame_image.get_size()).has_point(frame_point):
		if _frame_image.get_pixelv(Vector2i(frame_point)).a > 0.1: return -1
	for hanging: HangingSourceBody in screen.hanging_sources:
		if hanging.contains_pointer(viewport_position): return -1
	# Respect actual sibling draw order even after a retained actor is re-added.
	var front_index := -1
	for index in customers.size():
		if not is_instance_valid(customers[index]): continue
		var customer := customers[index]
		if not is_instance_valid(customer) or not customer.is_inside_tree() or customer.is_queued_for_deletion(): continue
		if not customer.visible: continue
		var world_point := customer.get_canvas_transform().affine_inverse() * viewport_position
		if not customer.contains_visual_point(world_point): continue
		if front_index < 0 or customer.z_index > customers[front_index].z_index or (
			customer.z_index == customers[front_index].z_index and customer.is_greater_than(customers[front_index])):
			front_index = index
	return front_index if front_index >= 0 and customers[front_index].is_serve_enabled() else -1


func simulate_result(index: int, kind: StringName) -> bool:
	if index < 0 or index >= selected_count or kind not in SAMPLE_KINDS or _blocked(): return false
	if not is_instance_valid(customers[index]): return false
	var customer := customers[index]
	if not is_instance_valid(customer) or not customer.is_inside_tree() or customer.is_queued_for_deletion(): return false
	if not customer.is_serve_enabled(): return false
	var order: OrderState = customer.order
	if order == null: return false
	var accepted := (order.request_kind == &"tea" and kind in [&"tea", &"cold"]
		or order.request_kind == &"ready_item" and order.item_id == kind)
	_handoff_sequence += 1
	var result := ServiceResult.create(StringName("scene_handoff_%d" % _handoff_sequence),
		order.order_id, order.customer_id, order.request_kind, accepted,
		accepted and kind == &"cold", &"" if accepted else &"wrong_item")
	if not customer.apply_service_result(result): return false
	_last_results[index] = result
	status_label.text = ("Sample accepted · cold tea, bad review." if accepted and kind == &"cold"
		else ("Sample accepted · happy customer." if accepted else "Wrong item · customer is still waiting."))
	return true


func replay_last_result(index: int) -> bool:
	if index < 0 or index >= customers.size() or not _last_results.has(index): return false
	if not is_instance_valid(customers[index]) or not customers[index].is_inside_tree() or customers[index].is_queued_for_deletion(): return false
	return customers[index].apply_service_result(_last_results[index])


func _exit_tree() -> void:
	if is_instance_valid(controller) and controller.is_dragging() and controller.current_payload.source == &"customer_scene_fixture":
		controller.cancel_drag()
