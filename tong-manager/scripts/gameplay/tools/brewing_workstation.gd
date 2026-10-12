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
	# The screen configures initial and newly spawned cups on either surface.
	# Each cup owns its reusable pour target, independent of tray ownership.
