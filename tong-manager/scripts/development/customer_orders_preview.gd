extends Control
## Isolated customer/order data review. Buttons simulate results, not live handoffs.

const INK := Color("393a31")
const MUTED := Color("696959")
const PAPER := Color("f2e8d2")
const GREEN := Color("285949")

var customer_picker: OptionButton
var request_picker: OptionButton
var portrait: TextureRect
var accept_button: Button
var cold_button: Button
var reject_button: Button
var replay_button: Button
var new_order_button: Button
var validate_button: Button
var status_label: Label
var history_label: Label
var details_label: Label
var validation_label: Label
var profile_label: Label
var request_icon: TextureRect
var order: OrderState
var last_result: ServiceResult
var catalog: Node
var _customers: Array[CustomerDef] = []
var _requests: Array[OrderRequestDef] = []
var _catalog_errors := PackedStringArray()
var _order_sequence := 0
var _handoff_sequence := 0


func _ready() -> void:
	catalog = get_node("/root/Catalog")
	_build_ui()
	_catalog_errors = catalog.validate_customer_orders()
	_customers = catalog.get_available_customers()
	for customer: CustomerDef in _customers:
		customer_picker.add_item(_display_name(customer.display_name_key, customer.id))
	if _customers.is_empty():
		status_label.text = "No valid customer profiles. Check the Catalog validation errors."
		validation_label.text = "\n".join(_catalog_errors)
		customer_picker.disabled = true
		request_picker.disabled = true
		new_order_button.disabled = true
		_set_controls_enabled(false)
		return
	select_customer(0)


func _build_ui() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 24
	ui_theme.set_color("font_color", "Label", INK)
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := _paper_box(Color("e5d8bd"), 10, 12)
			if state == "hover" or state == "focus":
				box.bg_color = Color("ecd097")
			elif state == "pressed":
				box.bg_color = Color("d1bc91")
			elif state == "disabled":
				box.bg_color = Color("e4dfd2")
			ui_theme.set_stylebox(state, type_name, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			ui_theme.set_color(state, type_name, INK)
		ui_theme.set_color("font_disabled_color", type_name, Color("898477"))
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("233d35")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	margin.add_child(rows)
	_label(rows, "DEVELOPMENT  /  CUSTOMER & ORDER DATA", 20, Color("dcbf83"))
	_label(rows, "One customer. One request.", 42, PAPER)
	_label(rows, "Review the editable profiles and simulate outcomes. These are data examples, not the customer gameplay scene.", 23, Color("d6dccf"))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	var profile := _card(columns)
	profile.custom_minimum_size.x = 420
	_label(profile, "01  /  CUSTOMER PROFILE", 21, GREEN)
	customer_picker = OptionButton.new()
	customer_picker.custom_minimum_size.y = 54
	profile.add_child(customer_picker)
	customer_picker.item_selected.connect(select_customer)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.y = 260
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile.add_child(portrait)
	profile_label = _label(profile, "", 23)
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(profile, "Patience is editable data here.\nNo timer or queue is running.", 20, MUTED)
	var review := _card(columns)
	review.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(review, "02  /  REQUEST & OUTCOME", 21, GREEN)
	var request_row := HBoxContainer.new()
	request_row.add_theme_constant_override("separation", 16)
	review.add_child(request_row)
	request_icon = TextureRect.new()
	request_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	request_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	request_icon.custom_minimum_size = Vector2(66, 66)
	request_row.add_child(request_icon)
	request_picker = OptionButton.new()
	request_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	request_row.add_child(request_picker)
	request_picker.item_selected.connect(select_request)
	new_order_button = _button(request_row, "New order", new_order)
	details_label = _label(review, "", 23)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.custom_minimum_size.y = 114
	_label(review, "SIMULATE A HANDOFF RESULT", 19, MUTED)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 10)
	review.add_child(buttons)
	accept_button = _button(buttons, "Accept warm tea", func(): simulate_result(true))
	cold_button = _button(buttons, "Accept cold tea", func(): simulate_result(true, true))
	reject_button = _button(buttons, "Reject wrong item", func(): simulate_result(false))
	replay_button = _button(buttons, "Replay last result", replay_last_result)
	status_label = _label(review, "", 29, GREEN)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 94
	var history_scroll := ScrollContainer.new()
	history_scroll.custom_minimum_size.y = 112
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	review.add_child(history_scroll)
	history_label = _label(history_scroll, "", 21, MUTED)
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var validation_row := HBoxContainer.new()
	validation_row.add_theme_constant_override("separation", 14)
	review.add_child(validation_row)
	validate_button = _button(validation_row, "Check invalid reference", demonstrate_invalid_reference)
	var validation_scroll := ScrollContainer.new()
	validation_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_scroll.custom_minimum_size.y = 52
	validation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	validation_row.add_child(validation_scroll)
	validation_label = _label(validation_scroll, "Catalog references are valid.", 20, MUTED)
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(rows, "SIMULATED RESULTS ONLY  ·  No stock, water, vessels or payments change. Customer movement, bubbles and real serving come later.", 20, Color("d6dccf"))


func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper_box(PAPER, 18, 24))
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	panel.add_child(rows)
	return rows


func _paper_box(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box


func _label(parent: Node, text_value: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 52
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func select_customer(index: int) -> void:
	if index < 0 or index >= _customers.size():
		return
	customer_picker.select(index)
	var customer := _customers[index]
	portrait.texture = customer.sprite_texture
	profile_label.text = "%s\nPatience: %s seconds\n%d permitted requests" % [customer.id, String.num(customer.patience_seconds, 2), customer.order_requests.size()]
	_requests.assign(customer.order_requests)
	request_picker.clear()
	for request: OrderRequestDef in _requests:
		var snapshot := request.snapshot(catalog)
		var identity: StringName = request.recipe_id if request.kind == &"tea" else request.item_id
		request_picker.add_item(_display_name(snapshot.get("display_name_key", ""), identity))
	if not _requests.is_empty():
		select_request(0)


func select_request(index: int) -> void:
	if index < 0 or index >= _requests.size():
		return
	request_picker.select(index)
	new_order()


func new_order() -> void:
	if _customers.is_empty() or request_picker.selected < 0:
		return
	_order_sequence += 1
	order = catalog.create_order(StringName("preview_order_%d" % _order_sequence),
		_customers[customer_picker.selected].id, _requests[request_picker.selected].id,
		Time.get_ticks_msec() / 1000.0)
	last_result = null
	if order == null:
		status_label.text = "Invalid definition: no order was created."
		_set_controls_enabled(false)
		return
	_set_controls_enabled(true)
	var request := order.get_request()
	var is_tea := order.request_kind == &"tea"
	accept_button.text = "Accept warm tea" if is_tea else "Accept item"
	cold_button.visible = is_tea
	request_icon.texture = request.get("icon") as Texture2D
	var identity: StringName = order.recipe_id if is_tea else order.item_id
	details_label.text = "%s  /  %s\nOne %s · catalog price %d\n" % [order.order_id, identity, request.unit, request.price]
	if is_tea:
		details_label.text += "Cup additions: %s. Minimum %s ml · target %s ml (review data)." % [_cup_additions(request), String.num(request.minimum_serving_volume_ml, 2), String.num(request.target_serving_volume_ml, 2)]
	else:
		details_label.text += "Same item identity as the pantry and hanging source."
	validation_label.text = "Catalog references are valid." if _catalog_errors.is_empty() else "\n".join(_catalog_errors)
	_update_outcome("A fresh order is ready for a simulated result.")


func simulate_result(accepted: bool, cold := false) -> void:
	if order == null:
		return
	_handoff_sequence += 1
	last_result = ServiceResult.create(StringName("preview_handoff_%d" % _handoff_sequence),
		order.order_id, order.customer_id, order.request_kind, accepted,
		cold if order.request_kind == &"tea" else false,
		&"wrong_request" if not accepted else &"")
	var recorded := order.record_result(last_result)
	_update_outcome("Result recorded." if recorded else "Ignored: this order was already fulfilled.")


func replay_last_result() -> void:
	if order == null or last_result == null:
		return
	var recorded := order.record_result(last_result)
	_update_outcome("Result recorded." if recorded else "Replay ignored. History and fulfillment stay unchanged.")


func demonstrate_invalid_reference() -> void:
	if request_picker.selected < 0 or _requests.is_empty():
		return
	var example := _requests[request_picker.selected].duplicate(true) as OrderRequestDef
	if example.kind == &"tea":
		example.recipe_id = &"missing_preview_reference"
	else:
		example.item_id = &"missing_preview_reference"
	var errors := example.validate(catalog)
	validation_label.text = "Isolated invalid copy rejected: " + " ".join(errors)
	validation_label.tooltip_text = validation_label.text


func _update_outcome(note: String) -> void:
	replay_button.disabled = last_result == null
	var accepted := order.get_accepted_result()
	var headline := "PENDING · not served"
	if not accepted.is_empty():
		headline = "SERVED · unhappy / bad review" if accepted.bad_review else "SERVED · no bad review"
	status_label.text = headline + "\n" + note
	status_label.add_theme_font_size_override("font_size", 25)
	var lines := PackedStringArray()
	for result: Dictionary in order.get_results():
		lines.append("%s  ·  %s  ·  %s" % [result.handoff_id,
			"accepted" if result.accepted else "rejected", String(result.reason).replace("_", " ")])
	history_label.text = "No recorded attempts.\nTry rejecting a wrong item, then accepting a correct one." if lines.is_empty() else "RECORDED ATTEMPTS\n" + "\n".join(lines)


func _set_controls_enabled(enabled: bool) -> void:
	for button: Button in [accept_button, cold_button, reject_button, replay_button, validate_button]:
		button.disabled = not enabled


func _cup_additions(request: Dictionary) -> String:
	var portions := PackedStringArray()
	for item_id: StringName in request.cup_portion_counts:
		var item: ItemDef = catalog.get_portion_item(item_id)
		var label := item.portion_label if item != null else String(item_id)
		portions.append("%d %s %s" % [request.cup_portion_counts[item_id], request.cup_portion_units[item_id], label.to_lower()])
	return ", ".join(portions) if not portions.is_empty() else "none"


func _display_name(key: String, fallback_id: StringName) -> String:
	var translated := tr(key) if not key.is_empty() else ""
	return translated if not translated.is_empty() and translated != key else String(fallback_id).replace("_", " ").capitalize()
