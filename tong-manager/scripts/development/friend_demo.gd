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
	for zone in bucket.get_drop_targets():
		zone.pointer_gate = _utility_pointer_allowed.bind(bucket)
	var waste := $WorldRoot/DropZoneRoot/DiscardArea as DiscardDropZone
	waste.pointer_gate = _utility_pointer_allowed.bind(waste)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var interaction := $InteractionController as InteractionController
	if hover_feedback == null or not interaction.can_start_world_action(): return
	# The basket accepts held vessels, but a bare click on its visible body
	# must not pick up the water bottle behind it through physics picking.
	if hover_feedback.get_utility_at(event.position) == $WorldRoot/DropZoneRoot/DiscardArea:
		get_viewport().set_input_as_handled()


func _layout_utilities() -> void:
	var water := $WorldRoot/ToolLayer/WaterDrum as Node2D
	# Upright silhouettes form a shallow fan beneath the notebook. Keep the
	# hover pop inside the 16:10 crop, with separate physical tabletop bases.
	water.position = Vector2(1748, 932)
	water.scale = Vector2.ONE * 1.2
	_set_utility_layer(water, 80)
	_fit_art(water.get_node("Icon"), WATER_ART, 138.0)
	var waste := $WorldRoot/DropZoneRoot/DiscardArea as Node2D
	waste.position = Vector2(1680, 959)
	_set_utility_layer(waste, 81)
	_fit_art(waste.get_node("Basket"), BASKET_ART, 140.0)
	var washing := $WorldRoot/ToolLayer/BucketStation as Node2D
	washing.position = Vector2(1600, 995)
	_set_utility_layer(washing, 82)
	$WorldRoot/DropZoneRoot/BucketDropZoneAnchor.position = Vector2(1600, 970)
	$WorldRoot/StatusBadgeAnchors/BucketStatus.position = Vector2(1600, 920)
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


func _utility_pointer_allowed(_payload: HeldItemPayload, point: Vector2, utility: Node2D) -> bool:
	# A full bucket must reject the cup rather than emptying it into the basket
	# behind it. Use the same visible silhouettes and resting layers as hover.
	return hover_feedback.get_utility_at(point) == utility


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
	var registered := table_surface.register_item(notebook, [footprint])
	assert(registered, "Notebook base must fit clear tabletop")
