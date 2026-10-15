extends "res://scripts/gameplay/tong/tong_day_screen.gd"
## The playable demonstration opts into presentation without changing review scenes.

const WATER_ART: Texture2D = preload("res://assets/art/toolkit/water_jar_drawn.png")
const BASKET_ART: Texture2D = preload("res://assets/art/toolkit/wastebasket_drawn.png")

@export var utility_edge_margin := Vector2(16, 16)
@export_range(0.05, 0.3, 0.01) var khata_edge_crop_fraction := 0.12

var hover_feedback: DemoHoverFeedback
var presentation: FriendDemoPresentation
var _utility_items: Array[Dictionary] = []
var _utility_bases: Array[Dictionary] = []
var _dock_ready := false


func _ready() -> void:
	$InteractionController.configure_direct_mouse_gestures(true)
	_layout_utilities()
	$HUDLayer/RootUI/IntentControls.hide()
	$HUDLayer/RootUI/EndDayButton.hide()
	_hide_station_copy($WorldRoot/ToolLayer)
	_hide_station_copy($WorldRoot/DropZoneRoot)
	super._ready()
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
	_dock_ready = true
	_anchor_utilities()


func _fit_authored_world() -> void:
	# Cancel and restore any held water bottle before changing its home.
	super._fit_authored_world()
	if _dock_ready: _anchor_utilities()


func _anchor_utilities() -> void:
	var bounds := Rect2()
	var first := true
	for item in _utility_items:
		if item.owner == $WorldRoot/ToolLayer/KhataStation: continue
		var owner_node: Node2D = item.owner
		var sprite: Sprite2D = item.sprite
		var rect := sprite.get_rect()
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var relative: Vector2 = world_root.to_local(sprite.to_global(corner)) - owner_node.position
			var point: Vector2 = item.home + relative * hover_feedback.utility_pop_scale
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else: bounds = bounds.expand(point)
	var viewport_corner := get_viewport_rect().end - utility_edge_margin
	var corner_in_world := world_root.get_global_transform_with_canvas().affine_inverse() * viewport_corner
	var offset := corner_in_world - bounds.end
	for item in _utility_items:
		(item.owner as Node2D).position = item.home + offset
	_anchor_closed_khata()
	$WorldRoot/DropZoneRoot/BucketDropZoneAnchor.position = bucket.position + Vector2(0, -25)
	$WorldRoot/StatusBadgeAnchors/BucketStatus.position = bucket.position + Vector2(0, -75)
	_sync_utility_bases()


func _anchor_closed_khata() -> void:
	# Tuck actual painted cover pixels beyond the edge, not its transparent
	# texture padding. The utility dock is independent of movable table items.
	var notebook := $WorldRoot/ToolLayer/KhataStation as Node2D
	var cover := notebook.get_node("KhataHotspot/Sprite") as Sprite2D
	var painted := Rect2(cover.texture.get_image().get_used_rect())
	if cover.region_enabled:
		painted = painted.intersection(cover.region_rect)
		painted.position -= cover.region_rect.position
	painted.position += cover.get_rect().position
	var canvas := cover.get_global_transform_with_canvas()
	var left := canvas * painted.position
	var right := canvas * painted.end
	var target_right := get_viewport_rect().end.x + (right.x - left.x) * khata_edge_crop_fraction
	var inverse := world_root.get_global_transform_with_canvas().affine_inverse()
	notebook.position += inverse * Vector2(target_right, right.y) - inverse * right


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
	# These authored positions define the fan's relative spacing. Its actual
	# home is fitted to the visible screen edge after the world is laid out.
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
	for entry in [[water, water.get_node("Icon")], [waste, waste.get_node("Basket")],
		[washing, washing.get_node("Sprite")], [notebook, hotspot.get_node("Sprite")]]:
		_utility_items.append({"owner": entry[0], "sprite": entry[1], "home": entry[0].position})


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


func _register_station_bases() -> void:
	# Screen-anchored bases are live exclusions, not cached item reservations.
	# Relayout frees the previous home without moving or losing placed cups.
	var definitions := [
		[bucket, Vector2(0, 45), Vector2(57, 17)],
		[$WorldRoot/ToolLayer/WaterDrum, Vector2(0, 61), Vector2(36, 8)],
		[$WorldRoot/DropZoneRoot/DiscardArea, Vector2(0, 61), Vector2(45, 12)],
		[$WorldRoot/ToolLayer/KhataStation/KhataHotspot, Vector2(0, 98), Vector2(33, 6)],
	]
	for definition in definitions:
		var footprint := PackedVector2Array()
		for index in 24:
			var angle := TAU * index / 24.0
			footprint.append(definition[1] + Vector2(cos(angle), sin(angle)) * definition[2])
		var shape := Polygon2D.new()
		shape.name = String(definition[0].name) + "DockBase"
		shape.polygon = footprint
		shape.hide()
		table_surface.get_node("Exclusions").add_child(shape)
		_utility_bases.append({"owner": definition[0], "shape": shape})
	_sync_utility_bases()


func _sync_utility_bases() -> void:
	# Only relayout updates these homes: a dragged bottle keeps its resting
	# footprint reserved until it returns, just like the other fixed utilities.
	for entry in _utility_bases:
		(entry.shape as Polygon2D).global_transform = (entry.owner as Node2D).global_transform
