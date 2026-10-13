extends "res://scripts/development/brewing_preview.gd"

var reload_button: Button


func _ready() -> void:
	var game_state := get_node("/root/GameState")
	var initialized: bool = game_state.ensure_inventory(screen.day_config)
	if not initialized:
		push_error("Inventory seed must match catalog units")
		set_process(false)
		return
	portion_stock = game_state.inventory
	super._ready()
	# Only this review scene authorizes the existing narrow ingredient/handoff
	# fixtures. Production eligibility and commands remain separate work.
	var targets: Array[DropZone] = [kettle.get_node("IngredientTarget") as DropZone, ready_item_zone]
	for cup in screen.get_cups():
		targets.append(cup.get_node("IngredientTarget") as DropZone)
	screen.khata_modal.configure_export_targets(targets)


func _start_preview() -> void:
	# Reopening this scene keeps the run's supplies. Its vessels are fresh fixtures.
	_update_stock_label()


func _build_controls() -> void:
	super._build_controls()
	var rows := get_node("PreviewUI/Root/Panel/Margin/Rows")
	rows.get_node("Title").text = "SHARED INVENTORY REVIEW"
	rows.get_node("FixtureNote").text = "Live run stock · Khata pantry/export review.\nVessel and snack targets remain test fixtures."
	reload_button = _button("ReloadScene", "Reload scene · keep supplies", _reload_scene)
	rows.add_child(reload_button)


func _reset_supplies() -> void:
	get_node("/root/GameState").reset_demo_state(screen.day_config)


func _update_stock_label() -> void:
	if not is_instance_valid(stock_label):
		return
	var lines := PackedStringArray(["Available / remaining"])
	for pair in [[&"black_tea", "Teabags"], [&"sugar", "Sugar spoons"],
		[&"condensed_milk", "Milk spoons"], [&"banana", "Bananas"], [&"biscuits", "Biscuits"]]:
		lines.append("%s  %d / %d" % [pair[1], portion_stock.available(pair[0]), portion_stock.remaining(pair[0])])
	stock_label.text = "\n".join(lines)


func _reload_scene() -> void:
	if not _blocked():
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	super._process(delta)
	reload_button.disabled = _blocked()


func _exit_tree() -> void:
	# The run's provider outlives this view.
	if portion_stock.changed.is_connected(_update_stock_label):
		portion_stock.changed.disconnect(_update_stock_label)
