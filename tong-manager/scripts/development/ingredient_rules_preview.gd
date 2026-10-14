extends "res://scripts/development/inventory_preview.gd"
## Explicit design sandbox. Opening it leaves the shipped rules unchanged.

const POLICIES: Array[IngredientPolicy] = [
	preload("res://data/balance/ingredient_policy.tres"),
	preload("res://data/examples/ingredient_rules/five_teabags.tres"),
	preload("res://data/examples/ingredient_rules/no_teabags.tres"),
	preload("res://data/examples/ingredient_rules/mixing_and_stages.tres"),
]
var policy_picker: OptionButton
var rule_note: Label
var contents_readout: Label


func _ready() -> void:
	super._ready()
	# This sandbox demonstrates vessel rules, not the separate snack fixture.
	controller.unregister_drop_zone(ready_item_zone)
	var no_extra_targets: Array[DropZone] = []
	screen.set_extra_portion_targets(no_extra_targets)
	ready_item_zone.hide()


func _build_controls() -> void:
	super._build_controls()
	var rows := get_node("PreviewUI/Root/Panel/Margin/Rows")
	var panel := get_node("PreviewUI/Root/Panel") as Control
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -172
	panel.offset_right = 172
	panel.offset_top = 136
	panel.offset_bottom = 136
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.12, 0.10, 0.08, 0.98)
	paper.border_color = Color(0.52, 0.43, 0.29, 1.0)
	paper.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", paper)
	rows.get_node("Title").text = "INGREDIENT RULES SANDBOX"
	rows.get_node("Title").add_theme_font_size_override("font_size", 14)
	# This panel reviews ingredient rules; the ordinary preview retains its
	# separate sample/reload controls. Keep the kettle and all sources reachable.
	rows.get_child(1).hide()
	next_sample_button.hide()
	reload_button.hide()
	policy_picker = OptionButton.new()
	policy_picker.focus_mode = Control.FOCUS_NONE
	for label in ["Current defaults", "Up to five teabags", "No teabags allowed", "Mixing and stage rules"]:
		policy_picker.add_item(label)
	policy_picker.item_selected.connect(_select_policy)
	rows.add_child(policy_picker)
	rule_note = Label.new()
	rule_note.custom_minimum_size.x = 275
	rule_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_note.add_theme_font_size_override("font_size", 13)
	rows.add_child(rule_note)
	contents_readout = Label.new()
	contents_readout.add_theme_font_size_override("font_size", 12)
	contents_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents_readout.max_lines_visible = 3
	contents_readout.mouse_filter = Control.MOUSE_FILTER_STOP
	rows.add_child(contents_readout)
	_update_rule_note(0)
	rows.get_node("FixtureNote").text = "Switching rules empties vessels and resets supplies.\nExamples never edit the default resource."


func _select_policy(index: int) -> void:
	if _blocked() or index < 0 or index >= POLICIES.size():
		return
	if screen.set_ingredient_policy(POLICIES[index]):
		reset_fixture()
		_update_rule_note(index)


func _update_rule_note(index: int) -> void:
	rule_note.text = [
		"One teabag after boiling. Sugar/milk in cups only, before or after tea.",
		"Up to five teabags in one batch. Water must still be boiling for each addition.",
		"Teabag limit is zero: every bag is rejected. Plain water does not become tea.",
		"Tea may start at 20°C. Sugar enters the kettle while steeping or ready; milk only when ready. Cup rules stay the same.",
	][index]


func _process(delta: float) -> void:
	super._process(delta)
	policy_picker.disabled = _blocked()
	var lines := PackedStringArray(["Kettle: " + str(kettle.get_ingredient_amounts())])
	for cup in screen.get_cups():
		if not cup.get_ingredient_amounts().is_empty():
			lines.append("%s: %s" % [cup.name, str(cup.get_ingredient_amounts())])
	contents_readout.text = "\n".join(lines)
	contents_readout.tooltip_text = contents_readout.text
