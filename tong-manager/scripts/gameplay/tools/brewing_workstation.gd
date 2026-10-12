extends Node

func _ready() -> void:
	var screen := get_parent()
	var controller := screen.get_node("InteractionController") as InteractionController
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var stove := screen.get_node("WorldRoot/ToolLayer/StoveStation") as Stove
	kettle.bind_controller(controller)
	stove.bind_controller(controller)
	# Preserve the authored initial kettle position while associating it with the left seat.
	stove.burners[0].seated_kettle = kettle
	kettle.current_burner = stove.burners[0]
	var drum := screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	drum.bind_controller(controller)
	var fill_zone := WaterFillDropZone.new()
	fill_zone.name = "WaterFillTarget"
	fill_zone.target = kettle
	fill_zone.controller = controller
	fill_zone.position = Vector2(26, -70)
	kettle.add_child(fill_zone)
	controller.register_drop_zone(fill_zone)
	var discard := screen.get_node("WorldRoot/DropZoneRoot/DiscardArea") as DiscardDropZone
	discard.controller = controller
	controller.register_drop_zone(discard)
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	for child in tray.cups.get_children():
		if child is Cup:
			var cup := child as Cup
			cup.capacity_ml = float(tray.tool_def.cup_volume_ml)
			var zone := BrewingDropZone.new()
			zone.name = "PourTarget"
			zone.is_cup_target = true
			zone.target = cup
			zone.controller = controller
			zone.snap_radius = 30.0
			zone.position = Vector2(0, -12)
			zone.input_pickable = false
			cup.add_child(zone)
			controller.register_drop_zone(zone)
