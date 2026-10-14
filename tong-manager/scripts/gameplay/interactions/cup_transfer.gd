class_name CupTransfer
extends Node
## Moves the original cup out of customer/bucket custody only after a valid drop.

var screen: Node2D
var controller: InteractionController
var _active: Dictionary = {}
var _zone: CupTransferDropZone
var _committing := false
var _recovery: Node2D
var _orphans: Array[Cup] = []
var _retry := 0.0


func _enter_tree() -> void:
	# The controller intentionally drops interaction references during detach.
	# Restore the same cup once the retained screen is safely back in the tree.
	_recover_interrupted.call_deferred()


func _recover_interrupted() -> void:
	if not _active.is_empty() and _live(controller) and not owns_payload(controller.current_payload):
		restore_transfer_origin(_active.payload)
		_restore_presentation()
		_active.clear()


func _process(delta: float) -> void:
	_recover_interrupted()
	_retry -= delta
	if _retry > 0.0 or not _live(screen): return
	_retry = 0.4
	for cup in _orphans.duplicate():
		if not _live(cup): _orphans.erase(cup)
		elif try_place_on_free_surface(cup): _orphans.erase(cup)


func configure(owner_screen: Node2D, interaction: InteractionController) -> void:
	screen = owner_screen
	controller = interaction
	_recovery = Node2D.new()
	_recovery.name = "RecoveredCups"
	add_child(_recovery)
	_zone = CupTransferDropZone.new()
	_zone.transfers = self
	add_child(_zone)
	controller.register_drop_zone(_zone)
	controller.drag_canceled.connect(_on_canceled)
	controller.drag_dropped.connect(_on_dropped)


func begin_transfer(cup: Cup, point: Vector2, source: Node, validate_callback: Callable, commit_callback: Callable) -> bool:
	if (not _live(cup) or not _live(source) or not _live(controller) or not _active.is_empty()
		or not screen.is_ancestor_of(cup) or not screen.is_ancestor_of(source)
		or controller.current_mode != InteractionController.MODE_INTERACT
		or not controller.can_start_world_action() or not point.is_finite()
		or not validate_callback.is_valid() or not commit_callback.is_valid()
		or not bool(validate_callback.call(cup))):
		return false
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle == null or handle.get_footprints().is_empty(): return false
	if _live(handle.surface) and handle.surface.is_registered(cup): return false
	var payload := HeldItemPayload.new(&"cup_transfer", StringName(cup.name), 1, cup, {
		"category": &"cup_transfer", "cup_transfer": self,
	})
	_active = {"cup": cup, "payload": payload, "source": weakref(source),
		"validate": validate_callback, "commit": commit_callback,
		"parent": weakref(cup.get_parent()), "transform": cup.transform,
		"visible": cup.visible, "process_mode": cup.process_mode, "pickable": cup.input_pickable}
	# Extraction starts at the pickup, not at the hidden cup's old table pose.
	var canvas := cup.get_canvas_transform()
	cup.global_position = canvas.affine_inverse() * point
	cup.show()
	cup.process_mode = Node.PROCESS_MODE_DISABLED
	cup.input_pickable = false
	if not controller.start_drag(payload, cup, point):
		restore_transfer_origin(payload)
		_restore_presentation()
		_active.clear()
		return false
	controller.report_hint("Place this cup on clear table or tray space · Esc returns it")
	return true


func is_transferring(cup: Cup) -> bool:
	return not _active.is_empty() and _active.get("cup") == cup


func owns_payload(payload: HeldItemPayload) -> bool:
	return (not _active.is_empty() and _active.get("payload") == payload
		and payload != null and payload.metadata.get("cup_transfer") == self)


func restore_transfer_origin(payload: HeldItemPayload) -> bool:
	if not owns_payload(payload): return false
	var cup: Variant = _active.cup
	if not _live(cup): return true
	var parent: Variant = (_active.parent as WeakRef).get_ref()
	if _restorable_parent(parent):
		if cup.get_parent() != parent: cup.reparent(parent, false)
		cup.transform = _active.transform
	elif _live(_recovery):
		# If a source node was removed, retain the physical cup and retry a free
		# surface. Source removal must never silently delete reusable inventory.
		controller.reparent_preserving_transform(cup, _recovery)
		cup.hide()
		if cup not in _orphans: _orphans.append(cup)
	return true


func _restorable_parent(parent: Variant) -> bool:
	if not is_instance_valid(parent) or not parent is Node: return false
	if parent.is_inside_tree() and not screen.is_ancestor_of(parent): return false
	var ancestor: Node = parent
	while ancestor != null:
		if ancestor.is_queued_for_deletion(): return false
		ancestor = ancestor.get_parent()
	return true


func can_commit(payload: HeldItemPayload) -> bool:
	if (not _live(self) or not _live(screen) or not _live(controller) or payload == null
		or controller.current_payload != payload or controller.current_drag_node != payload.world_node
		or controller.current_mode != InteractionController.MODE_INTERACT
		or not _live(payload.world_node) or not screen.is_ancestor_of(payload.world_node)
		or payload.quantity != 1 or payload.item_id != StringName(payload.world_node.name)
		or not payload.world_node is Cup or bool(payload.metadata.get("transient", false))):
		return false
	var cup := payload.world_node as Cup
	if owns_payload(payload):
		var source: Variant = (_active.source as WeakRef).get_ref()
		var validate: Callable = _active.validate
		return _live(source) and validate.is_valid() and bool(validate.call(cup))
	if payload.source != &"cup" or payload.metadata.get("category") != &"cup": return false
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	return handle != null and _live(handle.surface) and handle.surface.is_registered(cup)


func commit_to_holder(payload: HeldItemPayload, holder: Node2D, on_accept: Callable) -> bool:
	if (_committing or not can_commit(payload) or not _live(holder)
		or not screen.is_ancestor_of(holder) or not on_accept.is_valid()): return false
	_committing = true
	var cup := payload.world_node as Cup
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	if _live(handle.surface): handle.surface.unregister_item(cup)
	for node in cup.find_children("*", "", true, false):
		if node is DropZone: controller.unregister_drop_zone(node)
	controller.reparent_preserving_transform(cup, holder)
	cup.hide()
	cup.input_pickable = false
	cup.process_mode = Node.PROCESS_MODE_DISABLED
	# Destination bookkeeping cannot emit callbacks until both owners agree.
	on_accept.call(cup)
	_finish_source(payload, cup)
	_committing = false
	return true


func validate_surface(payload: HeldItemPayload) -> DropValidation:
	if not owns_payload(payload) or not can_commit(payload):
		return DropValidation.invalid("This cup is no longer available")
	if _find_surface(payload.world_node as Cup) == null:
		return DropValidation.invalid("Find clear table or tray space · Esc returns the cup")
	return DropValidation.valid()


func commit_to_surface(payload: HeldItemPayload) -> bool:
	if _committing or not owns_payload(payload) or not can_commit(payload): return false
	var cup := payload.world_node as Cup
	var target := _find_surface(cup)
	if target == null: return false
	_committing = true
	if not _place(cup, target):
		_committing = false
		return false
	_finish_source(payload, cup)
	_committing = false
	return true


func _finish_source(payload: HeldItemPayload, cup: Cup) -> void:
	if not owns_payload(payload): return
	var callback: Callable = _active.commit
	_active.clear()
	if callback.is_valid(): callback.call(cup)


func _find_surface(cup: Cup) -> PlacementSurface:
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle == null: return null
	for target: PlacementSurface in screen.get_placement_surfaces():
		if (_live(target) and _live(target.get_placement_parent())
			and target.validate_candidate(cup, handle.get_footprints()).is_valid
			and handle._validate_visible_base(target).is_valid):
			return target
	return null


func _place(cup: Cup, target: PlacementSurface) -> bool:
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	if not target.register_item(cup, handle.get_footprints()): return false
	var old_surface := handle.surface
	if _live(old_surface) and old_surface != target: old_surface.unregister_item(cup)
	controller.reparent_preserving_transform(cup, target.get_placement_parent())
	handle.adopt_surface(target)
	cup.process_mode = Node.PROCESS_MODE_INHERIT
	cup.input_pickable = true
	cup.show()
	screen.configure_cup(cup)
	return true


func try_place_on_free_surface(cup: Cup) -> bool:
	if (not _live(cup) or not _live(screen) or not _live(controller) or _committing
		or is_transferring(cup) or controller.current_drag_node == cup): return false
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle == null or handle.get_footprints().is_empty(): return false
	if _live(handle.surface) and handle.surface.is_registered(cup): return false
	var original := cup.global_transform
	# Search in actual free polygons. This is a return-position search only;
	# manual placement remains continuous and never snaps to these samples.
	for target: PlacementSurface in screen.get_placement_surfaces():
		if not _live(target) or not _live(target.get_placement_parent()): continue
		for candidate in target.get_vacated_positions():
			if _try_position(cup, handle, target, candidate): return true
		var regions := target.get_free_regions()
		for region: PackedVector2Array in regions:
			if region.size() < 3: continue
			var bounds := Rect2(region[0], Vector2.ZERO)
			var center := Vector2.ZERO
			for vertex in region:
				bounds = bounds.expand(vertex)
				center += vertex
			center /= region.size()
			var candidates: Array[Vector2] = [center]
			for vertex in region: candidates.append(vertex.lerp(center, 0.12))
			for candidate in candidates:
				if _try_position(cup, handle, target, candidate): return true
			for step in [16.0, 4.0]:
				var y := bounds.position.y
				while y <= bounds.end.y:
					var x := bounds.position.x
					while x <= bounds.end.x:
						var candidate := Vector2(x, y)
						if Geometry2D.is_point_in_polygon(candidate, region) and _try_position(cup, handle, target, candidate): return true
						x += step
					y += step
	cup.global_transform = original
	return false


func _try_position(cup: Cup, handle: TablePlaceable, target: PlacementSurface, base: Vector2) -> bool:
	var footprints := handle.get_footprints()
	var center := Vector2.ZERO
	for point in footprints[0]: center += point
	center /= footprints[0].size()
	cup.global_position = target.to_global(base) - cup.global_transform.basis_xform(center)
	if not target.validate_candidate(cup, footprints).is_valid or not handle._validate_visible_base(target).is_valid: return false
	return _place(cup, target)


func _restore_presentation() -> void:
	var cup: Variant = _active.get("cup")
	if not is_instance_valid(cup) or cup.is_queued_for_deletion(): return
	if cup in _orphans:
		cup.hide()
		cup.process_mode = Node.PROCESS_MODE_DISABLED
		cup.input_pickable = false
		return
	cup.visible = _active.visible
	cup.process_mode = _active.process_mode
	cup.input_pickable = _active.pickable


func _on_canceled(payload: HeldItemPayload) -> void:
	if owns_payload(payload):
		_restore_presentation()
		_active.clear()


func _on_dropped(payload: HeldItemPayload, _target: DropZone) -> void:
	# A future target that fails to consume custody must not strand its cup.
	if owns_payload(payload):
		restore_transfer_origin(payload)
		_restore_presentation()
		_active.clear()


static func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
