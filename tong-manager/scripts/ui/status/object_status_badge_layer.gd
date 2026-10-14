class_name ObjectStatusBadgeLayer
extends Control
## One screen-space presentation per live vessel, independent of its world parent.

@export var config: StatusMarkerConfig = preload("res://data/balance/status_markers.tres")

var _scope: Node
var _entries: Dictionary = {}
var _window_focused := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if config == null:
		config = StatusMarkerConfig.new()
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)


func bind_scope(value: Node) -> void:
	_scope = value
	refresh()


func get_vessels() -> Array[Node]:
	var vessels: Array[Node] = []
	if not is_inside_tree() or not is_instance_valid(_scope) or not _scope.is_inside_tree() or _scope.is_queued_for_deletion():
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
			badge.visible = false
			badge.modulate.a = 0.0
			add_child(badge)
			_entries[id] = {"owner": weakref(vessel), "badge": badge, "hover": 0.0, "fade": 0.0, "phase": 0.0, "has_slot": false, "recheck_pointer": not _window_focused}
		var badge: ObjectStatusBadge = _entries[id].badge
		if vessel.is_visible_in_tree():
			badge.set_tokens(VesselStatusPresenter.snapshot(vessel, catalog, config))
		else:
			_reset_entry(_entries[id], true)
		badge.visible = vessel.is_visible_in_tree() and float(_entries[id].fade) > 0.0
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
		if not is_visible_in_tree() or not is_instance_valid(vessel) or vessel.is_queued_for_deletion() or not vessel.is_inside_tree() or not vessel.is_visible_in_tree():
			_reset_entry(entry, true)
			continue
		var hovered: bool = _window_focused and vessel.has_method("is_status_hovered") and vessel.is_status_hovered()
		if _window_focused and bool(entry.recheck_pointer):
			if not hovered or _owner_contains_pointer(vessel):
				entry.recheck_pointer = false
			else:
				hovered = false
		if hovered:
			entry.hover = move_toward(float(entry.hover), 1.0, delta / maxf(0.01, config.hover_rise_seconds))
		var fade_duration := config.hover_fade_in_seconds if hovered else config.hover_fade_out_seconds
		entry.fade = move_toward(float(entry.fade), 1.0 if hovered else 0.0, delta / maxf(0.01, fade_duration))
		entry.badge.modulate.a = _ease(float(entry.fade))
		if float(entry.fade) > 0.0:
			# Both periodic terms return continuously at this shared wrap point.
			entry.phase = fposmod(float(entry.phase) + TAU * delta / maxf(0.1, config.hover_bob_period), TAU * 2.0)
		else:
			_reset_entry(entry)
	refresh()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
			_window_focused = false
			for entry in _entries.values():
				entry.recheck_pointer = true
		NOTIFICATION_WM_WINDOW_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
			_window_focused = true


func _owner_contains_pointer(vessel: Node) -> bool:
	# Focus changes may leave an Area2D's old mouse-entered flag set. Verify
	# the live shape once before accepting that flag again after window return.
	if vessel is CollisionObject2D and not vessel.input_pickable:
		return false
	var pointer := get_viewport().get_mouse_position()
	for child in vessel.get_children():
		if not child is CollisionShape2D or child.disabled or child.shape == null:
			continue
		var projection: Transform2D = child.get_global_transform_with_canvas()
		if is_zero_approx(projection.determinant()):
			continue
		var point: Vector2 = projection.affine_inverse() * pointer
		var shape: Shape2D = child.shape
		if shape is RectangleShape2D and shape.get_rect().has_point(point):
			return true
		if shape is CircleShape2D and point.length_squared() <= shape.radius * shape.radius:
			return true
		if shape is ConvexPolygonShape2D and Geometry2D.is_point_in_polygon(point, shape.points):
			return true
	return false


func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _reset_entry(entry: Dictionary, recheck_pointer := false) -> void:
	entry.hover = 0.0
	entry.fade = 0.0
	entry.phase = 0.0
	entry.has_slot = false
	if recheck_pointer:
		entry.recheck_pointer = true
	if is_instance_valid(entry.badge):
		entry.badge.visible = false
		entry.badge.modulate.a = 0.0


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		for entry in _entries.values():
			_reset_entry(entry, true)


func _exit_tree() -> void:
	for entry in _entries.values():
		_reset_entry(entry, true)


func _arrange() -> void:
	# Reserve the whole motion envelope, never the current sine-wave position.
	# Hidden groups take no space; vessel hit regions remain protected regardless.
	var entries: Array[Dictionary] = []
	var occupied: Array[Rect2] = []
	for entry: Dictionary in _entries.values():
		var vessel: Node = entry.owner.get_ref()
		if is_instance_valid(vessel) and vessel.is_visible_in_tree():
			entry.anchor = get_anchor_position(vessel)
			entry.bounds = get_vessel_bounds(vessel)
			occupied.append(entry.bounds)
			if entry.badge.visible:
				entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Keep already shown/fading groups stable when another owner is hovered.
		if bool(a.has_slot) != bool(b.has_slot):
			return bool(a.has_slot)
		if not is_equal_approx(a.anchor.y, b.anchor.y):
			return a.anchor.y < b.anchor.y
		if not is_equal_approx(a.anchor.x, b.anchor.x):
			return a.anchor.x < b.anchor.x
		return a.owner.get_ref().get_instance_id() < b.owner.get_ref().get_instance_id())
	var viewport_size := get_viewport_rect().size
	var margin := config.screen_margin
	var lift := maxf(0.0, config.hover_lift)
	var bob := maxf(0.0, config.hover_bob_amplitude)
	var sway := maxf(0.0, config.hover_sway_amplitude)
	for entry in entries:
		var badge: ObjectStatusBadge = entry.badge
		var dimensions := badge.get_badge_size()
		var reserved_size := dimensions + Vector2(sway * 2.0, lift + bob * 2.0)
		var desired: Vector2 = entry.anchor - Vector2(reserved_size.x * 0.5, reserved_size.y + config.anchor_gap)
		var below: Vector2 = Vector2(entry.anchor.x - reserved_size.x * 0.5, entry.bounds.end.y + config.anchor_gap)
		var placed := Vector2.INF
		if bool(entry.has_slot):
			var previous: Vector2 = entry.slot + (entry.anchor - entry.slot_anchor)
			if _slot_is_clear(previous, reserved_size, viewport_size, margin, occupied):
				placed = previous
		if not placed.is_finite():
			placed = _place_cluster(desired, reserved_size, viewport_size, margin, occupied, below)
		entry.slot = placed
		entry.slot_anchor = entry.anchor
		entry.has_slot = true
		occupied.append(Rect2(placed, reserved_size).grow(config.cluster_gap * 0.5))
		var opacity := _ease(float(entry.fade))
		var phase: float = entry.phase
		var floating := Vector2(sin(phase * 0.5) * sway, sin(phase) * bob) * opacity
		badge.position = placed + Vector2(sway, bob + lift * (1.0 - _ease(float(entry.hover)))) + floating


func _slot_is_clear(position: Vector2, dimensions: Vector2, viewport_size: Vector2, margin: float, occupied: Array[Rect2]) -> bool:
	var rect := Rect2(position, dimensions)
	var area := Rect2(Vector2.ONE * margin, (viewport_size - Vector2.ONE * margin * 2.0).max(Vector2.ZERO))
	if not area.encloses(rect):
		return false
	for previous in occupied:
		if rect.grow(config.cluster_gap * 0.5).intersects(previous):
			return false
	return true


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
