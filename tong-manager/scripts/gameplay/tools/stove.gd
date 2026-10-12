class_name Stove
extends Node2D

@export var tool_def: Resource = preload("res://data/balance/tool_level_1.tres")
@onready var burners: Array[Burner] = [$BurnerA, $BurnerB]

func bind_controller(controller: InteractionController) -> void:
	for index in burners.size():
		var burner := burners[index]
		burner.visible = index < tool_def.burner_count
		var dial := get_node("DialA" if index == 0 else "DialB") as StoveDial
		dial.visible = burner.visible
		dial.input_pickable = burner.visible
		if not burner.visible:
			burner.set_process(false)
			continue
		burner.controller = controller
		if not controller.mode_changed.is_connected(dial.refresh_hover):
			controller.mode_changed.connect(dial.refresh_hover)
		var zone := BrewingDropZone.new()
		zone.name = "DropZone"
		zone.target = burner
		zone.controller = controller
		zone.snap_radius = 65.0
		zone.input_pickable = false
		burner.add_child(zone)
		controller.register_drop_zone(zone)
