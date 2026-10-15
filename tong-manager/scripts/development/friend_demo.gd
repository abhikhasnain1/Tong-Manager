extends "res://scripts/gameplay/tong/tong_day_screen.gd"
## The playable demonstration opts into presentation without changing review scenes.

const WATER_ART: Texture2D = preload("res://assets/art/toolkit/water_jar_drawn.png")
const BASKET_ART: Texture2D = preload("res://assets/art/toolkit/wastebasket_drawn.png")

var hover_feedback: DemoHoverFeedback
var presentation: FriendDemoPresentation


func _ready() -> void:
	$InteractionController.configure_direct_mouse_gestures(true)
	_layout_utilities()
	$HUDLayer/RootUI/IntentControls.hide()
	$HUDLayer/RootUI/EndDayButton.hide()
	_hide_station_copy($WorldRoot/ToolLayer)
	_hide_station_copy($WorldRoot/DropZoneRoot)
	super._ready()
	_register_notebook_base()
	presentation = FriendDemoPresentation.new()
	presentation.name = "DemoPresentation"
	add_child(presentation)
	presentation.configure(self)
	hover_feedback = DemoHoverFeedback.new()
	hover_feedback.name = "DemoHoverFeedback"
	add_child(hover_feedback)
	hover_feedback.configure(self)


func _layout_utilities() -> void:
	var water := $WorldRoot/ToolLayer/WaterDrum as Node2D
	water.position = Vector2(1655, 853)
	water.scale = Vector2.ONE * 1.2
	_set_utility_layer(water, 80)
	_fit_art(water.get_node("Icon"), WATER_ART, 138.0)
	var waste := $WorldRoot/DropZoneRoot/DiscardArea as Node2D
	waste.position = Vector2(1548, 982)
	_set_utility_layer(waste, 82)
	_fit_art(waste.get_node("Basket"), BASKET_ART, 140.0)
	var washing := $WorldRoot/ToolLayer/BucketStation as Node2D
	washing.position = Vector2(1696, 992)
	_set_utility_layer(washing, 82)
	$WorldRoot/DropZoneRoot/BucketDropZoneAnchor.position = Vector2(1696, 967)
	$WorldRoot/StatusBadgeAnchors/BucketStatus.position = Vector2(1696, 917)
	var notebook := $WorldRoot/ToolLayer/KhataStation as Node2D
	notebook.position = Vector2(1770, 850)
	_set_utility_layer(notebook, 80)
	var hotspot := notebook.get_node("KhataHotspot") as Area2D
	hotspot.position = Vector2.ZERO
	(hotspot.get_node("Sprite") as Sprite2D).scale = Vector2.ONE * 0.2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(75, 208)
	(hotspot.get_node("CollisionShape2D") as CollisionShape2D).shape = shape
	(hotspot.get_node("InteractionAnchor") as Node2D).position = Vector2(-25, 0)


func _set_utility_layer(item: Node2D, layer: int) -> void:
	item.z_as_relative = false
	item.z_index = layer


func _fit_art(sprite: Sprite2D, texture: Texture2D, height: float) -> void:
	var used := texture.get_image().get_used_rect()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used)
	sprite.scale = Vector2.ONE * height / maxf(float(used.size.y), 1.0)


func _hide_station_copy(node: Node) -> void:
	if node is Label: node.hide()
	for child in node.get_children(): _hide_station_copy(child)


func _register_notebook_base() -> void:
	var notebook := $WorldRoot/ToolLayer/KhataStation/KhataHotspot as Area2D
	var footprint := PackedVector2Array()
	for index in 24:
		var angle := TAU * index / 24.0
		footprint.append(Vector2(0, 98) + Vector2(cos(angle), sin(angle)) * Vector2(33, 6))
	assert(table_surface.register_item(notebook, [footprint]), "Notebook base must fit clear tabletop")
