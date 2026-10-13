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
	# Ingredients use the normal scene's commands. Only snack handoff still
	# needs an explicitly authorized development target.
	var targets: Array[DropZone] = [ready_item_zone]
	screen.set_extra_portion_targets(targets)


func _start_preview() -> void:
	# Reopening this scene keeps the run's supplies. Its vessels are fresh fixtures.
	_update_stock_label()


func _build_controls() -> void:
	super._build_controls()
	var rows := get_node("PreviewUI/Root/Panel/Margin/Rows")
	rows.get_node("Title").text = "SHARED INVENTORY REVIEW"
	rows.get_node("FixtureNote").text = "Shared stock · ingredient commands.\nCustomer and snack targets remain test fixtures."
	reload_button = _button("ReloadScene", "Reload scene · keep supplies", _reload_scene)
	rows.add_child(reload_button)


func _reset_supplies() -> void:
	get_node("/root/GameState").reset_demo_state(screen.day_config)


func _update_stock_label() -> void:
	if not is_instance_valid(stock_label):
		return
	var lines := PackedStringArray(["Available / remaining"])
	for item: ItemDef in get_node("/root/Catalog").get_pantry_items():
		lines.append("%s  %d / %d" % [item.get_portion_label(), portion_stock.available(item.id), portion_stock.remaining(item.id)])
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
