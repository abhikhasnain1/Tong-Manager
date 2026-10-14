class_name CustomerOrderOverlay
extends Control
## Live order presentation only. The queue and OrderState retain all authority.

const BUBBLE := preload("res://scenes/ui/CustomerOrderBubble.tscn")

@export_range(0.0, 40.0, 1.0) var screen_margin := 12.0
@export_range(0.0, 24.0, 1.0) var separation := 8.0

var _queue: CustomerQueueManager
var _catalog: Node
var _entries: Dictionary = {}
var _extra_exclusions: Array[WeakRef] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func bind_queue(queue: CustomerQueueManager, catalog: Node) -> void:
	_clear()
	_queue = queue
	_catalog = catalog
	refresh()


func add_exclusion(control: Control) -> void:
	if not is_instance_valid(control): return
	for reference in _extra_exclusions:
		if reference.get_ref() == control: return
	_extra_exclusions.append(weakref(control))


func get_bubble_for(actor: Customer) -> CustomerOrderBubble:
	if not is_instance_valid(actor): return null
	return _entries.get(actor.get_instance_id(), {}).get("bubble") as CustomerOrderBubble


func get_anchor_position(actor: Customer) -> Vector2:
	if not _live(actor) or not _live(actor.order_anchor): return Vector2.INF
	var transform := get_global_transform_with_canvas()
	if not transform.is_finite() or is_zero_approx(transform.determinant()): return Vector2.INF
	return transform.affine_inverse() * actor.order_anchor.get_global_transform_with_canvas().origin


func get_exclusion_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	for path in ["../TopHud", "../IntentControls", "../EndDayButton", "../KhataPeek"]:
		_append_exclusion(get_node_or_null(path) as Control, rectangles)
	for index in range(_extra_exclusions.size() - 1, -1, -1):
		var control := _extra_exclusions[index].get_ref() as Control
		if not is_instance_valid(control):
			_extra_exclusions.remove_at(index)
		else:
			_append_exclusion(control, rectangles)
	return rectangles


func refresh() -> void:
	if not is_inside_tree(): return
	if not _live(_queue) or _queue.get_viewport() != get_viewport() or not _live(_catalog):
		_clear()
		return
	var live_ids: Dictionary = {}
	var arranged: Array[Dictionary] = []
	for actor in _queue.get_active_customers():
		if not _live(actor) or actor.get_viewport() != get_viewport(): continue
		var id := actor.get_instance_id()
		live_ids[id] = true
		if not _entries.has(id):
			var bubble := BUBBLE.instantiate() as CustomerOrderBubble
			bubble.name = "Order_%d" % id
			bubble.hide()
			add_child(bubble)
			_entries[id] = {"actor": weakref(actor), "bubble": bubble}
		var entry: Dictionary = _entries[id]
		var bubble: CustomerOrderBubble = entry.bubble
		actor.set_external_order_bubble(is_visible_in_tree())
		if bubble.order != actor.order:
			bubble.set_order(actor.order, _catalog)
		var display := actor.get_presentation_snapshot()
		bubble.visible = (is_visible_in_tree() and actor.is_serve_enabled()
			and display.emotion in [&"", &"wrong"] and bubble.get_display_snapshot().get("valid", false))
		if bubble.visible:
			entry.anchor = get_anchor_position(actor)
			if (entry.anchor as Vector2).is_finite():
				arranged.append(entry)
			else:
				bubble.hide()
	for id in _entries.keys():
		if not live_ids.has(id): _remove(id)
	_arrange(arranged)


func _process(_delta: float) -> void:
	# At most a handful of live visits: polling also observes direct fulfillment,
	# order replacement and removed nodes without keeping stale signal bindings.
	refresh()


func _exit_tree() -> void:
	_clear()


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _remove(id: int) -> void:
	var entry: Dictionary = _entries[id]
	var actor := entry.actor.get_ref() as Customer
	if is_instance_valid(actor): actor.set_external_order_bubble(false)
	var bubble := entry.bubble as CustomerOrderBubble
	if is_instance_valid(bubble):
		bubble.hide()
		bubble.queue_free()
	_entries.erase(id)


func _clear() -> void:
	for id in _entries.keys(): _remove(id)


func _append_exclusion(control: Control, rectangles: Array[Rect2]) -> void:
	if not _live(control) or not control.is_visible_in_tree(): return
	var projection := get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas()
	var rect := Rect2(projection * Vector2.ZERO, Vector2.ZERO)
	for point in [Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
		rect = rect.expand(projection * point)
	if rect.has_area(): rectangles.append(rect.grow(separation))


func _arrange(entries: Array[Dictionary]) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.anchor.x, b.anchor.x): return a.anchor.x < b.anchor.x
		return a.bubble.get_instance_id() < b.bubble.get_instance_id())
	var occupied := get_exclusion_rects()
	for entry in _entries.values():
		var actor := entry.actor.get_ref() as Customer
		if not _live(actor) or not actor.emotion_icon.is_visible_in_tree(): continue
		var icon := actor.emotion_icon
		var projection := get_global_transform_with_canvas().affine_inverse() * icon.get_global_transform_with_canvas()
		var radius := icon.size * 0.5
		var rect := Rect2(projection * Vector2(-radius, -radius), Vector2.ZERO)
		for point in [Vector2(radius, -radius), Vector2(radius, radius), Vector2(-radius, radius)]:
			rect = rect.expand(projection * point)
		occupied.append(rect.grow(separation))
	var safe := Rect2(Vector2.ONE * screen_margin, (size - Vector2.ONE * screen_margin * 2.0).max(Vector2.ZERO))
	for entry in entries:
		var bubble: CustomerOrderBubble = entry.bubble
		var dimensions := bubble.size
		var anchor: Vector2 = entry.anchor
		# Begin at the accepted head-corner cue, extending into the clear space
		# beside it. Try nearby rows/sides before moving farther from the owner.
		var desired := anchor - Vector2(22.0, dimensions.y * 0.5)
		var candidates: Array[Vector2] = [desired]
		for row in [-1, 1, -2, 2, -3, 3]:
			candidates.append(desired + Vector2(0, row * (dimensions.y + separation)))
		candidates.append(anchor - Vector2(dimensions.x + 24.0, dimensions.y * 0.5))
		for rect in occupied:
			candidates.append(Vector2(desired.x, rect.end.y + separation))
			candidates.append(Vector2(desired.x, rect.position.y - dimensions.y - separation))
		var chosen := Vector2.INF
		var best_distance := INF
		for candidate in candidates:
			candidate = candidate.clamp(safe.position, (safe.end - dimensions).max(safe.position))
			var rect := Rect2(candidate, dimensions)
			if not safe.encloses(rect): continue
			var fits := true
			for obstacle in occupied:
				if obstacle.intersects(rect):
					fits = false
					break
			if fits and candidate.distance_squared_to(desired) < best_distance:
				chosen = candidate
				best_distance = candidate.distance_squared_to(desired)
		if chosen.is_finite():
			bubble.position = chosen.round()
			occupied.append(Rect2(bubble.position, dimensions).grow(separation))
		else:
			# No misleading overlay over notebook/HUD controls in impossible layouts.
			bubble.hide()
