class_name TablePlaceable
extends Node2D

signal placement_committed

@export var footprint := PackedVector2Array()
@export_node_path("CollisionPolygon2D") var footprint_path: NodePath
@export_node_path("Area2D") var input_area_path: NodePath

var surface: PlacementSurface
var controller: InteractionController
var item: Node2D
var _home_parent: Node
var _zone: TablePlacementDropZone
var _input_area: Area2D
var _footprints: Array[PackedVector2Array] = []
var _available_surfaces: Array[PlacementSurface] = []
var candidate_surface: PlacementSurface
var _hovered := false


func _ready() -> void:
	item = get_parent() as Node2D
	assert(item != null, "A table placement handle needs a Node2D owner.")
	add_to_group(&"table_placeables")
	_zone = TablePlacementDropZone.new()
	_zone.handle = self
	add_child(_zone)
	_input_area = get_node_or_null(input_area_path) as Area2D
	if _input_area != null:
		_input_area.input_event.connect(_on_input_event)
		_input_area.mouse_entered.connect(_on_hover.bind(true))
		_input_area.mouse_exited.connect(_on_hover.bind(false))


func configure(value: PlacementSurface, interaction: InteractionController) -> bool:
	if not is_instance_valid(value) or not is_instance_valid(interaction):
		return false
	if surface == value and value.is_registered(item):
		return true
	surface = value
	if is_instance_valid(controller) and controller.mode_changed.is_connected(_refresh_hover):
		controller.mode_changed.disconnect(_refresh_hover)
	controller = interaction
	controller.mode_changed.connect(_refresh_hover)
	_home_parent = item.get_parent()
	var shape := footprint
	var authored := get_node_or_null(footprint_path) as CollisionPolygon2D
	if authored != null:
		shape = PackedVector2Array()
		for point in authored.polygon:
			shape.append(item.to_local(authored.to_global(point)))
	_footprints = [shape]
	if not surface.register_item(item, _footprints):
		return false
	_available_surfaces = [surface]
	controller.register_drop_zone(_zone)
	return true


func set_available_surfaces(values: Array[PlacementSurface]) -> void:
	_available_surfaces = values.duplicate()


func get_footprints() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon in _footprints:
		result.append(polygon.duplicate())
	return result


func adopt_surface(target: PlacementSurface) -> bool:
	# Cup recovery books the destination before releasing its custody source.
	if not is_instance_valid(target) or not target.is_registered(item):
		return false
	surface = target
	_home_parent = item.get_parent()
	if is_instance_valid(controller):
		controller.register_drop_zone(_zone)
	return true


func begin_drag(viewport_position: Vector2) -> bool:
	if (not is_instance_valid(controller) or not is_instance_valid(surface)
		or controller.current_mode != InteractionController.MODE_ORGANIZE
		or not controller.can_start_world_action()
		or controller.is_dragging() or controller.has_active_action()
		or not surface.is_registered(item)):
		return false
	var payload := HeldItemPayload.new(&"table_surface", StringName(item.name), 1, item, {
		"category": &"table_placeable", "placement_handle": self,
	})
	return controller.start_drag(payload, item, viewport_position)


func owns_payload(payload: HeldItemPayload) -> bool:
	return (payload != null and is_instance_valid(controller) and is_instance_valid(surface)
		and payload.world_node == item and payload.metadata.get("placement_handle") == self
		and controller.current_mode == InteractionController.MODE_ORGANIZE
		and controller.current_payload == payload and controller.current_drag_node == item)


func validate_placement() -> DropValidation:
	candidate_surface = null
	if not is_instance_valid(surface) or not surface.is_inside_tree() or not surface.is_registered(item):
		return DropValidation.invalid("placement.unavailable")
	var first_failure := DropValidation.invalid("placement.unavailable")
	for target in _available_surfaces:
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			continue
		# A movable surface cannot be placed onto itself or one of its children.
		if item == target or item.is_ancestor_of(target):
			continue
		var result := target.validate_candidate(item, _footprints)
		if result.is_valid:
			result = _validate_visible_base(target)
		if result.is_valid:
			candidate_surface = target
			return result
		first_failure = result
	return first_failure


func _validate_visible_base(target: PlacementSurface) -> DropValidation:
	# The authored table may be cropped by a narrow window. Never commit an
	# unreachable base beyond the visible screen; this adds no table blocker.
	var view := get_viewport().get_visible_rect()
	for polygon in target.project_footprints(item, _footprints):
		for point in polygon:
			var screen_point := target.get_global_transform_with_canvas() * point
			if (screen_point.x < view.position.x - 0.001 or screen_point.y < view.position.y - 0.001
				or screen_point.x > view.end.x + 0.001 or screen_point.y > view.end.y + 0.001):
				return DropValidation.invalid("placement.outside_view")
	return DropValidation.valid()


func commit(payload: HeldItemPayload) -> bool:
	if (not owns_payload(payload) or not is_instance_valid(_home_parent)
		or not _home_parent.is_inside_tree() or _home_parent.is_queued_for_deletion()
		or not validate_placement().is_valid):
		return false
	var target := candidate_surface
	var target_parent := _home_parent if target == surface else target.get_placement_parent()
	if not is_instance_valid(target_parent) or not target_parent.is_inside_tree() or target_parent.is_queued_for_deletion():
		return false
	if target == surface:
		if not surface.commit_item(item):
			return false
	else:
		# Book the validated destination before releasing the original reservation.
		# No signals or awaits can observe a half-completed ownership transfer.
		if not target.register_item(item, _footprints):
			return false
		surface.unregister_item(item)
		surface = target
		_home_parent = target_parent
	controller.reparent_preserving_transform(item, target_parent)
	placement_committed.emit()
	return true


func _on_input_event(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_frontmost_at(event.position) and begin_drag(event.position):
			get_viewport().set_input_as_handled()


func _is_frontmost_at(viewport_position: Vector2) -> bool:
	if not is_instance_valid(surface) or not surface.is_inside_tree():
		return false
	# Physics picking sorts tree order, whereas the table renders by Y. Match
	# that painter order so overlapping tall art selects the visible container.
	for node in get_tree().get_nodes_in_group(&"table_placeables"):
		var other := node as TablePlaceable
		if (other == self or other.controller != controller or not is_instance_valid(other.item)
			or not other.item.is_visible_in_tree()
			or not is_instance_valid(other.surface) or not other.surface.is_registered(other.item)
			or not other._contains_pointer(viewport_position)):
			continue
		var this_root := _render_root()
		var other_root := other._render_root()
		if this_root == other_root:
			# Contents render above the tray; siblings are Y-sorted within it.
			if item.is_ancestor_of(other.item):
				return false
			if other.item.is_ancestor_of(item):
				continue
			this_root = item
			other_root = other.item
		var this_y := this_root.global_position.y
		var other_y := other_root.global_position.y
		if other_y > this_y or (other_y == this_y and other_root.is_greater_than(this_root)):
			return false
	return true


func _render_root() -> Node2D:
	var result := item
	var ancestor := item.get_parent()
	while ancestor != null:
		var handle := ancestor.get_node_or_null("PlacementHandle") as TablePlaceable
		if handle != null and handle.controller == controller:
			result = ancestor as Node2D
		ancestor = ancestor.get_parent()
	return result


func _contains_pointer(viewport_position: Vector2) -> bool:
	if not is_instance_valid(_input_area) or not _input_area.input_pickable:
		return false
	for child in _input_area.get_children():
		if child is CollisionPolygon2D and not child.disabled:
			var point: Vector2 = child.get_global_transform_with_canvas().affine_inverse() * viewport_position
			if Geometry2D.is_point_in_polygon(point, child.polygon):
				return true
		elif child is CollisionShape2D and not child.disabled:
			var point: Vector2 = child.get_global_transform_with_canvas().affine_inverse() * viewport_position
			var shape: Shape2D = child.shape
			if shape is ConvexPolygonShape2D and Geometry2D.is_point_in_polygon(point, shape.points):
				return true
			if shape is RectangleShape2D and Rect2(-shape.size * 0.5, shape.size).has_point(point):
				return true
			if shape is CircleShape2D and point.length_squared() <= shape.radius * shape.radius:
				return true
	return false


func _on_hover(entered: bool) -> void:
	_hovered = entered
	if (not is_instance_valid(controller) or controller.is_dragging() or controller.has_active_action()
		or controller.current_mode != InteractionController.MODE_ORGANIZE
		or controller.is_world_input_blocked() or controller.is_pointer_over_ui()):
		return
	get_node("/root/CursorService").set_state(&"hover_actionable" if entered else &"default")
	if entered:
		controller.report_hint("Organize · drag %s to clear table or tray space" % item.name)


func _refresh_hover(_mode: StringName) -> void:
	if _hovered:
		_on_hover(true)
