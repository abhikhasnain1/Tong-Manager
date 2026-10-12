class_name InteractionController
extends Node

signal drag_started(payload: HeldItemPayload, drag_node: Node2D)
signal drag_moved(payload: HeldItemPayload, viewport_position: Vector2)
signal drag_canceled(payload: HeldItemPayload)
signal drag_dropped(payload: HeldItemPayload, drop_zone: DropZone)
signal mode_changed(mode: StringName)
signal action_requested(action: StringName)
signal hint_changed(text: String)

const MODE_NEUTRAL := &"neutral"
const MODE_INTERACT := &"interact"
const MODE_USE := MODE_INTERACT
const MODE_ORGANIZE := &"organize"
const INPUT_ORGANIZE_TOGGLE := &"organize_toggle"
const INPUT_USE_TOGGLE := &"use_toggle"
const INPUT_ROTATE_ITEM := &"rotate_item"
const INPUT_POUR := &"pour"
const INPUT_QUICK_WASH := &"quick_wash"
const INPUT_CANCEL := &"cancel"
const CURSOR_STATE_DRAGGING := &"dragging"
const CURSOR_STATE_INVALID := &"invalid"
const FORWARDED_ACTIONS: Array[StringName] = [INPUT_ROTATE_ITEM, INPUT_POUR, INPUT_QUICK_WASH]

@export_node_path("Node2D") var drag_layer_path: NodePath
@export_node_path("Node2D") var drop_zone_root_path: NodePath

@onready var drag_layer := get_node_or_null(drag_layer_path) as Node2D
@onready var drop_zone_root := get_node_or_null(drop_zone_root_path) as Node2D
@onready var cursor_service: Node = get_node("/root/CursorService")

var current_payload: HeldItemPayload
var current_drag_node: Node2D
var hovered_drop_zone: DropZone
var current_mode: StringName = MODE_NEUTRAL
var action_owner: Node
var current_hint := "Neutral · select Organize or Use"
var _input_blockers: Dictionary = {}
var _last_pointer := Vector2.ZERO
var modal_root: Control
var _resolving_drag := false
var _queued_mode: StringName = &""
var _was_world_blocked := false
var _portion_mouse_mode := -1


func report_hint(text: String) -> void:
	if current_hint != text:
		current_hint = text
		hint_changed.emit(text)


func is_world_input_blocked() -> bool:
	for id in _input_blockers.keys():
		var owner_node: Node = (_input_blockers[id] as WeakRef).get_ref()
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree() or owner_node.is_queued_for_deletion():
			_input_blockers.erase(id)
	if is_instance_valid(modal_root) and modal_root.is_visible_in_tree():
		for child in modal_root.get_children():
			if child is CanvasItem and child.is_visible_in_tree():
				return true
	return not _input_blockers.is_empty()


func set_world_input_blocked(owner_node: Node, blocked: bool) -> void:
	if not is_instance_valid(owner_node):
		return
	if blocked:
		_input_blockers[owner_node.get_instance_id()] = weakref(owner_node)
		cancel_world_action()
		report_hint("Close the open panel to interact")
	else:
		_input_blockers.erase(owner_node.get_instance_id())
		_report_mode_hint()


func is_pointer_over_ui() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		control = control.get_parent_control()
	return false


func can_start_world_action() -> bool:
	return (current_mode != MODE_NEUTRAL and not is_world_input_blocked()
		and not _resolving_drag and not is_pointer_over_ui() and not is_dragging() and not has_active_action())


func cancel_world_action() -> void:
	if has_active_action():
		action_owner.call("cancel_action")
	if current_payload != null:
		cancel_drag()
	Input.action_release(INPUT_POUR)
	if is_instance_valid(cursor_service):
		cursor_service.reset()

func has_active_action() -> bool:
	return is_instance_valid(action_owner)

func lock_action(owner_node: Node) -> bool:
	if not is_instance_valid(owner_node) or _resolving_drag or is_dragging() or is_world_input_blocked() or current_mode != MODE_INTERACT:
		return false
	if has_active_action() and action_owner != owner_node:
		return false
	action_owner = owner_node
	return true

func unlock_action(owner_node: Node) -> void:
	if action_owner == owner_node:
		action_owner = null

var _drag_origin_parent: Node
var _drag_had_origin_parent := false
var _drag_origin_transform := Transform2D.IDENTITY
var _drag_start_pointer := Vector2.ZERO
var _drag_start_position := Vector2.ZERO
var _registered_drop_zones: Array[DropZone] = []


func _ready() -> void:
	assert(drag_layer != null, "InteractionController requires a DragLayer reference.")
	assert(drop_zone_root != null, "InteractionController requires a DropZoneRoot reference.")


func _exit_tree() -> void:
	# Scene teardown can run while its parents are busy removing children. Drop
	# interaction references without restoring/reparenting nodes or emitting drag
	# callbacks into a scene that is leaving the tree.
	action_owner = null
	_resolving_drag = true
	_dispose_transient_drag()
	_clear_drag_state()
	Input.action_release(INPUT_POUR)
	if is_instance_valid(cursor_service):
		cursor_service.reset()


func _input(event: InputEvent) -> void:
	# Cancellation and mode switches must work even when a GUI control has focus.
	if (is_dragging() or has_active_action()) and event.is_action_pressed(INPUT_CANCEL):
		cancel_world_action()
		_report_mode_hint()
		get_viewport().set_input_as_handled()
		return
	# Gameplay owns both edges of Space during a drag, before focused GUI buttons.
	if (is_dragging() or has_active_action()) and event.is_action(INPUT_POUR):
		if event.is_action_pressed(INPUT_POUR):
			action_requested.emit(INPUT_POUR)
		get_viewport().set_input_as_handled()
		return
	# A drag begun in the world must finish even over a GUI panel. Otherwise
	# the panel can swallow mouse release and leave a stuck kettle or cup.
	if is_dragging():
		if event is InputEventMouseMotion:
			update_drag(event.position)
			# Let GUI hover tracking see motion; release still belongs to this drag.
			# Otherwise gui_get_hovered_control retains the control from pickup.
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			release_drop(event.position)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		cancel_world_action()
		_report_mode_hint()


func _process(_delta: float) -> void:
	var blocked := is_world_input_blocked()
	if blocked and (not _was_world_blocked or has_active_action() or current_payload != null):
		cancel_world_action()
		report_hint("Close the open panel to interact")
	elif _was_world_blocked and not blocked:
		_report_mode_hint()
	_was_world_blocked = blocked
	if current_payload == null:
		return
	if (not is_instance_valid(current_drag_node) or not current_drag_node.is_inside_tree()
		or current_drag_node.is_queued_for_deletion() or is_world_input_blocked()):
		cancel_drag()
		return
	_update_hovered_drop_zone(_last_pointer)


func _unhandled_input(event: InputEvent) -> void:
	if is_world_input_blocked():
		return
	if event.is_action_pressed(INPUT_ORGANIZE_TOGGLE):
		toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(INPUT_USE_TOGGLE):
		select_mode(MODE_INTERACT)
		get_viewport().set_input_as_handled()
		return

	if has_active_action():
		if event.is_action_pressed(INPUT_CANCEL):
			action_owner.call("cancel_action")
			get_viewport().set_input_as_handled()
		return

	for action in FORWARDED_ACTIONS if current_mode == MODE_INTERACT else []:
		if event.is_action_pressed(action):
			action_requested.emit(action)

	if not is_dragging():
		return
	if event.is_action_pressed(INPUT_CANCEL):
		cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		update_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		release_drop(event.position)
		get_viewport().set_input_as_handled()


func is_dragging() -> bool:
	return current_payload != null and is_instance_valid(current_drag_node)


func register_drop_zone(drop_zone: DropZone) -> void:
	if drop_zone == null or _registered_drop_zones.has(drop_zone):
		return
	_registered_drop_zones.append(drop_zone)


func unregister_drop_zone(drop_zone: DropZone) -> void:
	_registered_drop_zones.erase(drop_zone)
	if is_instance_valid(hovered_drop_zone) and hovered_drop_zone == drop_zone:
		hovered_drop_zone.clear_highlight()
		hovered_drop_zone = null


func start_drag(payload: HeldItemPayload, drag_node: Node2D, viewport_position: Vector2) -> bool:
	if _resolving_drag or has_active_action() or is_world_input_blocked() or current_mode == MODE_NEUTRAL:
		return false
	if payload == null or not is_instance_valid(drag_node):
		return false
	if current_payload != null:
		cancel_drag()

	current_payload = payload
	current_drag_node = drag_node
	if payload.metadata.get("category") == &"ingredient_portion":
		_portion_mouse_mode = Input.mouse_mode
	_drag_origin_parent = drag_node.get_parent()
	_drag_had_origin_parent = _drag_origin_parent != null
	_drag_origin_transform = drag_node.transform
	if _drag_origin_parent == null:
		drag_layer.add_child(drag_node)
		drag_node.position = drag_layer.get_global_transform_with_canvas().affine_inverse() * viewport_position
	elif _drag_origin_parent != drag_layer:
		reparent_preserving_transform(drag_node, drag_layer)
	_drag_start_pointer = viewport_position
	_drag_start_position = drag_node.position

	cursor_service.set_state(CURSOR_STATE_DRAGGING)
	update_drag(viewport_position)
	drag_started.emit(current_payload, current_drag_node)
	return true


func update_drag(viewport_position: Vector2) -> void:
	if not is_dragging():
		return
	_last_pointer = viewport_position
	# Transform a displacement instead of round-tripping the large absolute
	# authored position through canvas coordinates. A stationary pickup or a
	# return to its starting pointer keeps an exact touching base unchanged.
	var displacement := viewport_position - _drag_start_pointer
	var canvas_inverse := drag_layer.get_global_transform_with_canvas().affine_inverse()
	current_drag_node.position = _drag_start_position + canvas_inverse.basis_xform(displacement)
	drag_moved.emit(current_payload, viewport_position)
	_update_hovered_drop_zone(viewport_position)


func reparent_preserving_transform(item: Node2D, parent: Node) -> void:
	if item.get_parent() == parent:
		return
	var relative := _relative_transform(item, parent)
	item.reparent(parent, false)
	item.transform = relative


func _relative_transform(item: Node2D, parent: Node) -> Transform2D:
	if item.is_set_as_top_level():
		return item.global_transform
	# Cancel shared world transforms before calculating the new local pose.
	# reparent(true) otherwise introduces viewport-scale rounding at exact edges.
	var ancestors: Dictionary = {}
	var ancestor := item
	var item_to_ancestor := Transform2D.IDENTITY
	while ancestor != null:
		ancestors[ancestor] = item_to_ancestor
		if ancestor.is_set_as_top_level():
			break
		item_to_ancestor = ancestor.transform * item_to_ancestor
		ancestor = ancestor.get_parent() as Node2D
	ancestor = parent as Node2D
	var parent_to_ancestor := Transform2D.IDENTITY
	while ancestor != null:
		if ancestors.has(ancestor):
			return parent_to_ancestor.affine_inverse() * (ancestors[ancestor] as Transform2D)
		if ancestor.is_set_as_top_level():
			break
		parent_to_ancestor = ancestor.transform * parent_to_ancestor
		ancestor = ancestor.get_parent() as Node2D
	if parent is CanvasItem:
		return parent.get_global_transform().affine_inverse() * item.global_transform
	return item.global_transform


func cancel_drag() -> void:
	if current_payload == null or _resolving_drag:
		return
	_resolving_drag = true
	var canceled_payload := current_payload
	if bool(current_payload.metadata.get("transient", false)):
		_dispose_transient_drag()
	else:
		_restore_drag_origin()
	_clear_drag_state()
	cursor_service.reset()
	drag_canceled.emit(canceled_payload)
	_finish_drag_resolution()


func release_drop(viewport_position: Vector2) -> void:
	if not is_dragging() or _resolving_drag:
		return
	if not current_drag_node.is_inside_tree() or current_drag_node.is_queued_for_deletion():
		cancel_drag()
		return
	if is_world_input_blocked() or is_pointer_over_ui():
		cancel_drag()
		return
	update_drag(viewport_position)
	if not is_instance_valid(hovered_drop_zone) or not hovered_drop_zone.accepts(current_payload).is_valid:
		cancel_drag()
		return

	var dropped_payload := current_payload
	var target_zone := hovered_drop_zone
	# Target/stock signals are synchronous. A command owns its gesture until all
	# observers finish, so a listener cannot replace the payload mid-commit.
	_resolving_drag = true
	var applied := target_zone.try_apply_drop(dropped_payload)
	if not applied:
		_resolving_drag = false
		cancel_drag()
		return
	_dispose_transient_drag()
	_clear_drag_state()
	cursor_service.reset()
	drag_dropped.emit(dropped_payload, target_zone)
	_finish_drag_resolution()


func _finish_drag_resolution() -> void:
	_resolving_drag = false
	if not _queued_mode.is_empty():
		var mode := _queued_mode
		_queued_mode = &""
		set_mode(mode)


func toggle_mode() -> void:
	select_mode(MODE_ORGANIZE)


func select_mode(mode: StringName) -> void:
	if not is_world_input_blocked():
		set_mode(MODE_NEUTRAL if current_mode == mode else mode)


func set_mode(mode: StringName) -> void:
	assert(mode in [MODE_NEUTRAL, MODE_INTERACT, MODE_ORGANIZE], "Unsupported interaction mode: %s" % mode)
	if _resolving_drag:
		_queued_mode = mode
		return
	if mode == current_mode:
		return
	cancel_world_action()
	current_mode = mode
	_report_mode_hint()
	mode_changed.emit(current_mode)


func _report_mode_hint() -> void:
	if current_mode == MODE_NEUTRAL:
		report_hint("Neutral · select Organize or Use")
	elif current_mode == MODE_ORGANIZE:
		report_hint("Organize · drag whole objects · select again for Neutral")
	else:
		report_hint("Use · drag a portion or use a tool · select again for Neutral")


func _dispose_transient_drag() -> void:
	if current_payload != null and bool(current_payload.metadata.get("transient", false)):
		var cleanup: Callable = current_payload.metadata.get("cleanup_callback", Callable())
		if cleanup.is_valid():
			cleanup.call()
		if is_instance_valid(current_drag_node) and not current_drag_node.is_queued_for_deletion():
			current_drag_node.queue_free()


func _drag_cursor() -> StringName:
	return StringName(current_payload.metadata.get("cursor_state", CURSOR_STATE_DRAGGING)) if current_payload != null else CURSOR_STATE_DRAGGING


func _apply_drag_cursor(state: StringName) -> void:
	cursor_service.set_state(state)
	if _portion_mouse_mode >= 0:
		# The held portion itself is the cursor. Keep the invalid system cue over
		# blocked targets/UI, but do not draw two teabags or spoons on valid space.
		Input.mouse_mode = _portion_mouse_mode if state == CURSOR_STATE_INVALID else Input.MOUSE_MODE_HIDDEN


func _update_hovered_drop_zone(viewport_position: Vector2) -> void:
	if is_pointer_over_ui() or is_world_input_blocked():
		if is_instance_valid(hovered_drop_zone):
			hovered_drop_zone.clear_highlight()
		hovered_drop_zone = null
		_apply_drag_cursor(CURSOR_STATE_INVALID)
		if current_payload.metadata.get("category") == &"ingredient_portion":
			report_hint("Move off the panel to a valid vessel · Esc cancels")
		return
	var best_valid: DropZone
	var best_valid_distance := INF
	var best_invalid: DropZone
	var best_invalid_distance := INF

	for zone in _get_available_drop_zones():
		if not zone.is_inside_tree() or zone.is_queued_for_deletion():
			continue
		if not zone.is_relevant_to(current_payload):
			continue
		var zone_viewport_position := zone.get_global_transform_with_canvas().origin
		var zone_belongs_to_drag_node := (
			current_drag_node == zone
			or current_drag_node.is_ancestor_of(zone)
		)
		var probe_position := zone.get_probe_position(current_payload, viewport_position)
		var distance := 0.0 if zone_belongs_to_drag_node else probe_position.distance_to(zone_viewport_position)
		var zone_scale := zone.get_global_transform_with_canvas().get_scale()
		var snap_radius_viewport := zone.snap_radius * maxf(absf(zone_scale.x), absf(zone_scale.y))
		if not zone_belongs_to_drag_node and distance > snap_radius_viewport:
			continue
		if zone.accepts(current_payload).is_valid:
			if distance < best_valid_distance:
				best_valid = zone
				best_valid_distance = distance
		elif distance < best_invalid_distance:
			best_invalid = zone
			best_invalid_distance = distance

	var next_zone := best_valid if best_valid != null else best_invalid
	# A portion aimed at an unavailable vessel must not jump to a valid neighbour.
	if (current_payload.metadata.get("category") == &"ingredient_portion"
		and best_invalid != null and best_invalid_distance <= best_valid_distance):
		next_zone = best_invalid
	if is_instance_valid(hovered_drop_zone) and hovered_drop_zone != next_zone:
		hovered_drop_zone.clear_highlight()
	hovered_drop_zone = next_zone
	if is_instance_valid(hovered_drop_zone):
		var validation := hovered_drop_zone.accepts(current_payload)
		var is_valid := validation.is_valid
		hovered_drop_zone.set_highlight(is_valid)
		_apply_drag_cursor(_drag_cursor() if is_valid else CURSOR_STATE_INVALID)
		if current_payload.metadata.get("category") == &"ingredient_portion":
			report_hint("Release to add this portion · Esc cancels" if is_valid else validation.reason_key)
	else:
		_apply_drag_cursor(_drag_cursor())
		if current_payload.metadata.get("category") == &"ingredient_portion":
			report_hint("Move this portion over a valid vessel · Esc cancels")


func _collect_drop_zones(parent: Node) -> Array[DropZone]:
	var zones: Array[DropZone] = []
	for child in parent.get_children():
		if child is DropZone:
			zones.append(child)
		zones.append_array(_collect_drop_zones(child))
	return zones


func _get_available_drop_zones() -> Array[DropZone]:
	var zones := _collect_drop_zones(drop_zone_root)
	for index in range(_registered_drop_zones.size() - 1, -1, -1):
		var registered_zone := _registered_drop_zones[index]
		if not is_instance_valid(registered_zone):
			_registered_drop_zones.remove_at(index)
			continue
		# Retain registrations across legitimate reparenting, but never target
		# a retained node while it is detached from the active scene.
		if not registered_zone.is_inside_tree() or registered_zone.is_queued_for_deletion():
			continue
		if not zones.has(registered_zone):
			zones.append(registered_zone)
	return zones


func restore_drag_origin() -> void:
	# Non-placement drops (water, discard, service) retain the source vessel.
	_restore_drag_origin()


func _restore_drag_origin() -> void:
	if not is_instance_valid(current_drag_node):
		return
	if is_instance_valid(_drag_origin_parent):
		if current_drag_node.get_parent() != _drag_origin_parent:
			current_drag_node.reparent(_drag_origin_parent, false)
		current_drag_node.transform = _drag_origin_transform
	elif _drag_had_origin_parent:
		# The original scene owner was destroyed while this node was held outside
		# it. Complete that removal instead of retaining an unreachable orphan.
		current_drag_node.queue_free()
	elif current_drag_node.get_parent() != null:
		current_drag_node.get_parent().remove_child(current_drag_node)
		current_drag_node.transform = _drag_origin_transform


func _clear_drag_state() -> void:
	if _portion_mouse_mode >= 0:
		Input.mouse_mode = _portion_mouse_mode
		_portion_mouse_mode = -1
	if is_instance_valid(hovered_drop_zone):
		hovered_drop_zone.clear_highlight()
	hovered_drop_zone = null
	current_payload = null
	current_drag_node = null
	_drag_origin_parent = null
	_drag_had_origin_parent = false
	_drag_origin_transform = Transform2D.IDENTITY
	_drag_start_pointer = Vector2.ZERO
	_drag_start_position = Vector2.ZERO
