class_name ObjectStatusBadgeLayer
extends Control
## One screen-space presentation per live vessel, independent of its world parent.

@export var config: StatusMarkerConfig = preload("res://data/balance/status_markers.tres")

var _scope: Node
var _entries: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if config == null:
		config = StatusMarkerConfig.new()


func bind_scope(value: Node) -> void:
	_scope = value
	refresh()


func get_vessels() -> Array[Node]:
	var vessels: Array[Node] = []
	if not is_inside_tree() or not is_instance_valid(_scope) or not _scope.is_inside_tree():
		return vessels
	for group in [&"cups", &"kettles"]:
		for vessel in get_tree().get_nodes_in_group(group):
			if (is_instance_valid(vessel) and not vessel.is_queued_for_deletion()
				and vessel is CanvasItem and vessel.get_viewport() == get_viewport()
				and (_scope == vessel or _scope.is_ancestor_of(vessel))):
				vessels.append(vessel)
	return vessels


func get_badge_for(vessel: Node) -> ObjectStatusBadge:
	if not is_instance_valid(vessel):
		return null
	return _entries.get(vessel.get_instance_id(), {}).get("badge") as ObjectStatusBadge


func get_anchor_position(vessel: Node) -> Vector2:
	var anchor := vessel.get_node_or_null("StatusBadgeAnchor") as CanvasItem
	if anchor == null:
		anchor = vessel as CanvasItem
	return get_global_transform_with_canvas().affine_inverse() * anchor.get_global_transform_with_canvas().origin


func get_vessel_bounds(vessel: Node) -> Rect2:
	var result := Rect2(get_anchor_position(vessel), Vector2.ZERO)
	var found := false
	for child in vessel.get_children():
		if not child is CollisionShape2D or child.disabled or child.shape == null:
			continue
		var shape_rect: Rect2 = child.shape.get_rect()
		var projection: Transform2D = get_global_transform_with_canvas().affine_inverse() * child.get_global_transform_with_canvas()
		for point in [shape_rect.position, Vector2(shape_rect.end.x, shape_rect.position.y), shape_rect.end, Vector2(shape_rect.position.x, shape_rect.end.y)]:
			var projected: Vector2 = projection * point
			if not found:
				result = Rect2(projected, Vector2.ZERO)
				found = true
			else:
				result = result.expand(projected)
	return result


func refresh() -> void:
	if not is_inside_tree():
		return
	var live: Dictionary = {}
	var catalog := get_node_or_null("/root/Catalog")
	for vessel in get_vessels():
		var id := vessel.get_instance_id()
		live[id] = true
		if not _entries.has(id):
			var badge := ObjectStatusBadge.new()
			badge.name = "Vessel_%d" % id
			badge.configure(config)
			add_child(badge)
			_entries[id] = {"owner": weakref(vessel), "badge": badge, "hover": 0.0}
		var badge: ObjectStatusBadge = _entries[id].badge
		badge.visible = vessel.is_visible_in_tree()
		if badge.visible:
			badge.set_tokens(VesselStatusPresenter.snapshot(vessel, catalog, config))
	for id in _entries.keys():
		if not live.has(id):
			var badge: ObjectStatusBadge = _entries[id].badge
			remove_child(badge)
			badge.queue_free()
			_entries.erase(id)
	_arrange()


func _process(delta: float) -> void:
	for entry in _entries.values():
		var vessel: Node = entry.owner.get_ref()
		var hovered: bool = (is_instance_valid(vessel) and vessel.is_visible_in_tree()
			and vessel.has_method("is_status_hovered") and vessel.is_status_hovered())
		var duration := config.hover_rise_seconds if hovered else config.hover_return_seconds
		entry.hover = move_toward(float(entry.hover), 1.0 if hovered else 0.0, delta / maxf(0.01, duration))
	refresh()


func _arrange() -> void:
	# Packing reserves the entire hover travel, so hovering does not push other
	# cups' markers around. Only live vessel motion or a changed token set reflows.
	var entries: Array[Dictionary] = []
	var occupied: Array[Rect2] = []
	for entry: Dictionary in _entries.values():
		var vessel: Node = entry.owner.get_ref()
		if is_instance_valid(vessel) and entry.badge.visible:
			entry.anchor = get_anchor_position(vessel)
			entry.bounds = get_vessel_bounds(vessel)
			occupied.append(entry.bounds)
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.anchor.y, b.anchor.y):
			return a.anchor.y < b.anchor.y
		if not is_equal_approx(a.anchor.x, b.anchor.x):
			return a.anchor.x < b.anchor.x
		return a.owner.get_ref().get_instance_id() < b.owner.get_ref().get_instance_id())
	var viewport_size := get_viewport_rect().size
	var margin := config.screen_margin
	for entry in entries:
		var badge: ObjectStatusBadge = entry.badge
		var dimensions := badge.get_badge_size()
		var reserved_size := dimensions + Vector2(0, config.hover_lift)
		var desired: Vector2 = entry.anchor - Vector2(dimensions.x * 0.5, reserved_size.y + config.anchor_gap)
		var below: Vector2 = Vector2(entry.anchor.x - dimensions.x * 0.5, entry.bounds.end.y + config.anchor_gap)
		var placed := _place_cluster(desired, reserved_size, viewport_size, margin, occupied, below)
		occupied.append(Rect2(placed, reserved_size).grow(config.cluster_gap * 0.5))
		var progress: float = entry.hover
		var eased := progress * progress * (3.0 - 2.0 * progress)
		badge.position = placed + Vector2(0, config.hover_lift * (1.0 - eased))


func _place_cluster(desired: Vector2, dimensions: Vector2, viewport_size: Vector2, margin: float, occupied: Array[Rect2], below := Vector2.INF) -> Vector2:
	var max_position := (viewport_size - dimensions - Vector2.ONE * margin).max(Vector2.ONE * margin)
	var origin := desired.clamp(Vector2.ONE * margin, max_position)
	var best := origin
	var best_score := INF
	# Prefer the nearest clear location above the owner. Two small horizontal
	# offsets make dense tray rows readable without stretching icons or labels.
	for row in range(occupied.size() + 2):
		for offset in [0.0, -0.5, 0.5, -1.0, 1.0]:
			var candidate: Vector2 = (origin + Vector2(offset * (dimensions.x + config.cluster_gap), -row * (dimensions.y + config.cluster_gap))).clamp(Vector2.ONE * margin, max_position)
			var rect := Rect2(candidate, dimensions).grow(config.cluster_gap * 0.5)
			var collision := false
			for previous in occupied:
				if rect.intersects(previous):
					collision = true
					break
			if not collision:
				var score := candidate.distance_squared_to(origin)
				if score < best_score:
					best_score = score
					best = candidate
	# Front-row cups may have another cup directly above them. Stay close to
	# their bases instead of moving their entire group over the rear row.
	if below.is_finite():
		for row in 2:
			for offset in [0.0, -0.5, 0.5, -1.0, 1.0]:
				var candidate: Vector2 = (below + Vector2(offset * (dimensions.x + config.cluster_gap), row * (dimensions.y + config.cluster_gap))).clamp(Vector2.ONE * margin, max_position)
				var rect := Rect2(candidate, dimensions).grow(config.cluster_gap * 0.5)
				var clear := true
				for previous in occupied:
					if rect.intersects(previous):
						clear = false
						break
				var score := candidate.distance_squared_to(below) + 625.0
				if clear and score < best_score:
					best_score = score
					best = candidate
	if is_inf(best_score):
		# A held vessel can reach the top edge. Search the remaining viewport
		# before accepting overlap; the normal tabletop path stays above owners.
		var step := dimensions + Vector2.ONE * maxf(1.0, config.cluster_gap)
		var columns := ceili(viewport_size.x / maxf(1.0, step.x))
		var rows := ceili(viewport_size.y / maxf(1.0, step.y))
		for row in range(-rows, rows + 1):
			for column in range(-columns, columns + 1):
				var candidate := (origin + Vector2(column, row) * step).clamp(Vector2.ONE * margin, max_position)
				var rect := Rect2(candidate, dimensions).grow(config.cluster_gap * 0.5)
				var clear := true
				for previous in occupied:
					if rect.intersects(previous):
						clear = false
						break
				if clear and candidate.distance_squared_to(origin) < best_score:
					best_score = candidate.distance_squared_to(origin)
					best = candidate
	return best
