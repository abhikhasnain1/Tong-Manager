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
@export var direct_mouse_gestures := false

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
var _modal_export_owner: Control
var _modal_export_payload: HeldItemPayload
var _modal_export_targets: Array[DropZone] = []
var _modal_export_ignored_ui: Array[Control] = []
var _active_drag_layer: Node2D
var _starting_modal_export := false
var _direct_press_button := 0
var _drag_button := MOUSE_BUTTON_LEFT
var _direct_mode_change := false


func configure_direct_mouse_gestures(enabled: bool) -> void:
	cancel_world_action()
	direct_mouse_gestures = enabled
	_direct_press_button = 0
	if enabled:
		_set_direct_mode(MODE_INTERACT)


func is_move_drag() -> bool:
	return direct_mouse_gestures and is_dragging() and _drag_button == MOUSE_BUTTON_RIGHT


func _set_direct_mode(mode: StringName) -> void:
	_direct_mode_change = true
	set_mode(mode)
	_direct_mode_change = false


func _restore_direct_idle() -> void:
	if not direct_mouse_gestures or _direct_mode_change or current_mode == MODE_INTERACT:
		return
	current_mode = MODE_INTERACT
	_report_mode_hint()
	mode_changed.emit(current_mode)


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
			if _modal_child_blocks_input(child):
				return true
	return not _input_blockers.is_empty()


func _modal_child_blocks_input(child: Node) -> bool:
	if not child is CanvasItem or not child.is_visible_in_tree():
		return false
	# A shared presentation can remain visible in a nonmodal pose. Ordinary
	# dialogs retain the default blocking policy; explicit locks still apply.
	if child.has_method("is_modal_input_active"):
		var active: Variant = child.call("is_modal_input_active")
		if active is bool:
			return active
	return true


func set_world_input_blocked(owner_node: Node, blocked: bool) -> void:
	if not is_instance_valid(owner_node):
		return
	if blocked:
		_input_blockers[owner_node.get_instance_id()] = weakref(owner_node)
		cancel_world_action()
		report_hint("Close the open panel to interact")
	else:
		end_modal_export(owner_node)
		_input_blockers.erase(owner_node.get_instance_id())
		_report_mode_hint()


func begin_modal_export(owner_node: Control, payload: HeldItemPayload, visual: Node2D, point: Vector2,
		export_layer: Node2D, allowed_targets: Array[DropZone], ignored_ui: Array[Control], allow_empty_targets := false) -> bool:
	# A modal lends one exact portion access to an explicit set of targets. Its
	# ordinary world-input lock remains held throughout the export.
	if (_resolving_drag or _starting_modal_export or current_payload != null or has_active_action()
		or not point.is_finite() or not _export_owner_has_exclusive_input(owner_node)
		or not _live_node(export_layer) or not owner_node.is_ancestor_of(export_layer)
		or not export_layer.is_visible_in_tree() or is_zero_approx(export_layer.get_global_transform_with_canvas().determinant())
		or not is_instance_valid(visual) or visual.is_queued_for_deletion()
		or visual == export_layer or visual.is_ancestor_of(export_layer)
		or payload == null or payload.world_node != visual or not bool(payload.metadata.get("transient", false))):
		return false
	var portion := payload.metadata.get("portion") as IngredientPortion
	if (portion == null or not portion.is_available() or payload.item_id != portion.item_id
		or payload.quantity != portion.quantity or payload.metadata.get("unit") != portion.unit
		or payload.metadata.get("item_id") != portion.item_id or payload.metadata.get("quantity") != portion.quantity
		or payload.metadata.get("source_id") != portion.source_id
		or payload.metadata.get("cleanup_callback") != Callable(portion, "cancel")):
		return false
	for control in ignored_ui:
		if not _live_node(control) or (control != owner_node and not owner_node.is_ancestor_of(control)):
			return false
	var targets: Array[DropZone] = []
	for zone in allowed_targets:
		if not _live_node(zone):
			return false
		if not targets.has(zone):
			targets.append(zone)
	if targets.is_empty() and not allow_empty_targets:
		return false
	_starting_modal_export = true
	_modal_export_owner = owner_node
	_modal_export_payload = payload
	_modal_export_targets = targets
	_modal_export_ignored_ui = ignored_ui.duplicate()
	_start_drag_in_layer(payload, visual, point, export_layer)
	_starting_modal_export = false
	var active := is_modal_export_active(owner_node)
	if not active and current_payload == payload:
		cancel_drag()
	return active


func end_modal_export(owner_node: Node) -> void:
	if _modal_export_payload == null or owner_node != _modal_export_owner:
		return
	# A synchronous target/stock callback cannot interrupt its own commit. Every
	# resolution clears the session before its final drag signal is delivered.
	if not _resolving_drag:
		cancel_drag()


func is_modal_export_active(owner_node: Control = null) -> bool:
	return (_modal_export_payload != null and current_payload == _modal_export_payload
		and (owner_node == null or owner_node == _modal_export_owner)
		and _export_owner_has_exclusive_input(_modal_export_owner))


func can_address_drop_zone(payload: HeldItemPayload, zone: DropZone) -> bool:
	if (payload == null or payload != current_payload or not _live_node(zone)
		or not _live_node(current_drag_node) or payload.world_node != current_drag_node):
		return false
	if _modal_export_payload != null:
		return is_modal_export_active() and payload == _modal_export_payload and _modal_export_targets.has(zone) and zone.is_visible_in_tree()
	if is_move_drag():
		# Moving an object cannot also serve it, discard its contents or pour.
		if payload.metadata.get("category") == &"table_placeable":
			return zone is TablePlacementDropZone and not is_world_input_blocked()
		return (bool(payload.metadata.get("kettle_move", false)) and zone is BrewingDropZone
			and not zone.is_cup_target and not is_world_input_blocked())
	return current_mode != MODE_NEUTRAL and not is_world_input_blocked()


func _live_node(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


func _export_owner_has_exclusive_input(owner_node: Control) -> bool:
	if (not _live_node(owner_node) or not owner_node.is_visible_in_tree()
		or not _live_node(modal_root) or not modal_root.is_visible_in_tree()
		or not modal_root.is_ancestor_of(owner_node)):
		return false
	# Reuse blocker cleanup, but never use its boolean to unblock ordinary input.
	is_world_input_blocked()
	if _input_blockers.size() != 1 or not _input_blockers.has(owner_node.get_instance_id()):
		return false
	for child in modal_root.get_children():
		if _modal_child_blocks_input(child) and child != owner_node and not child.is_ancestor_of(owner_node):
			return false
	return true


func _drag_input_allowed() -> bool:
	if _modal_export_payload == null:
		return not is_world_input_blocked()
	var portion := _modal_export_payload.metadata.get("portion") as IngredientPortion
	return is_modal_export_active() and portion != null and portion.is_available()


func _drag_pointer_over_ui(point: Vector2) -> bool:
	if _modal_export_payload != null:
		return _ui_branch_covers_point(get_viewport(), point, _modal_export_ignored_ui)
	return is_pointer_over_ui()


func is_pointer_over_ui() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		control = control.get_parent_control()
	return false


func is_pointer_over_ui_at(viewport_position: Vector2) -> bool:
	# GUI hover describes only the latest endpoint. A swept world interaction
	# must also reject earlier points that are covered by HUD/preview controls.
	if not is_inside_tree() or not viewport_position.is_finite():
		return false
	return _ui_branch_covers_point(get_viewport(), viewport_position)


func _ui_branch_covers_point(node: Node, viewport_position: Vector2, ignored: Array[Control] = []) -> bool:
	if node.is_queued_for_deletion() or (node is Viewport and node != get_viewport()):
		return false
	if node is Control and not ignored.has(node) and _control_covers_point(node as Control, viewport_position):
		return true
	for child in node.get_children():
		if _ui_branch_covers_point(child, viewport_position, ignored):
			return true
	return false


func _control_covers_point(control: Control, viewport_position: Vector2) -> bool:
	if not control.is_visible_in_tree() or control.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE:
		return false
	var transform := control.get_global_transform_with_canvas()
	if is_zero_approx(transform.determinant()):
		return false
	var local_point := transform.affine_inverse() * viewport_position
	var hit := bool(control.call("_has_point", local_point)) if control.has_method("_has_point") else Rect2(Vector2.ZERO, control.size).has_point(local_point)
	if not hit:
		return false
	# Clip rectangles are tested in each ancestor's own coordinate system.
	# Top-level items and CanvasLayers break this CanvasItem ancestry just as
	# they do for GUI rendering and input.
	var ancestor: CanvasItem = control.get_parent() as CanvasItem if not control.is_set_as_top_level() else null
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			var clip_transform: Transform2D = ancestor.get_global_transform_with_canvas()
			if is_zero_approx(clip_transform.determinant()) or not Rect2(Vector2.ZERO, ancestor.size).has_point(clip_transform.affine_inverse() * viewport_position):
				return false
		if ancestor.is_set_as_top_level():
			break
		ancestor = ancestor.get_parent() as CanvasItem
	return true


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
	_restore_direct_idle()

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


func _enter_tree() -> void:
	# A retained screen can leave the tree and return without _ready running again.
	_resolving_drag = false
	_queued_mode = &""
	_was_world_blocked = false
	_direct_press_button = 0
	if direct_mouse_gestures:
		current_mode = MODE_INTERACT


func _ready() -> void:
	assert(drag_layer != null, "InteractionController requires a DragLayer reference.")
	assert(drop_zone_root != null, "InteractionController requires a DropZoneRoot reference.")
	get_viewport().size_changed.connect(_on_export_viewport_resized)
	if direct_mouse_gestures:
		_set_direct_mode(MODE_INTERACT)
		_report_mode_hint()


func _on_export_viewport_resized() -> void:
	if _modal_export_payload != null:
		cancel_world_action()


func _exit_tree() -> void:
	# Scene teardown can run while its parents are busy removing children. Drop
	# interaction references without restoring/reparenting nodes or emitting drag
	# callbacks into a scene that is leaving the tree.
	action_owner = null
	_resolving_drag = true
	_dispose_transient_drag()
	_clear_drag_state()
	Input.action_release(INPUT_POUR)
	_direct_press_button = 0
	if is_instance_valid(cursor_service):
		cursor_service.reset()


func _input(event: InputEvent) -> void:
	if direct_mouse_gestures:
		if event.is_action_pressed(INPUT_ORGANIZE_TOGGLE) or event.is_action_pressed(INPUT_USE_TOGGLE):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and _handle_direct_mouse_button(event):
			get_viewport().set_input_as_handled()
			return
	# Cancellation and mode switches must work even when a GUI control has focus.
	if (is_dragging() or has_active_action()) and event.is_action_pressed(INPUT_CANCEL):
		cancel_world_action()
		_report_mode_hint()
		get_viewport().set_input_as_handled()
		return
	# Gameplay owns both edges of Space during a drag, before focused GUI buttons.
	if (is_dragging() or has_active_action()) and event.is_action(INPUT_POUR):
		if _modal_export_payload == null and not is_move_drag() and event.is_action_pressed(INPUT_POUR):
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
		elif event is InputEventMouseButton and event.button_index == _drag_button and not event.pressed:
			var viewport := get_viewport()
			release_drop(event.position)
			if is_instance_valid(viewport): viewport.set_input_as_handled()


func _handle_direct_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return false
	if event.pressed:
		if _resolving_drag:
			return true
		if is_dragging() or has_active_action():
			var owned_button: int = _drag_button if is_dragging() else MOUSE_BUTTON_LEFT
			return event.button_index != owned_button
		# Esc can finish an action before its mouse button is released. Do not
		# reinterpret the second button as a fresh gesture during that press.
		if _direct_press_button != 0:
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_world_input_blocked() or is_pointer_over_ui_at(event.position):
				return false
			_direct_press_button = MOUSE_BUTTON_RIGHT
			_set_direct_mode(MODE_ORGANIZE)
		else:
			_direct_press_button = MOUSE_BUTTON_LEFT
			_set_direct_mode(MODE_INTERACT)
		return false
	if is_dragging() and event.button_index != _drag_button:
		return true
	if event.button_index == _direct_press_button:
		_direct_press_button = 0
		if not is_dragging():
			_restore_direct_idle()
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		cancel_world_action()
		_direct_press_button = 0
		_report_mode_hint()


func _process(_delta: float) -> void:
	# A modal may consume a release before it reaches this node's input hook.
	# Forget that completed press without resolving a drag at an invented point.
	if direct_mouse_gestures and _direct_press_button != 0 and not Input.is_mouse_button_pressed(_direct_press_button):
		_direct_press_button = 0
		if not is_dragging() and not has_active_action():
			_restore_direct_idle()
	var blocked := is_world_input_blocked()
	var valid_export := _modal_export_payload != null and _drag_input_allowed()
	if blocked and not valid_export and (not _was_world_blocked or has_active_action() or current_payload != null):
		cancel_world_action()
		report_hint("Close the open panel to interact")
	elif _was_world_blocked and not blocked:
		_report_mode_hint()
	_was_world_blocked = blocked
	if current_payload == null:
		return
	if (not is_instance_valid(current_drag_node) or not current_drag_node.is_inside_tree()
		or current_drag_node.is_queued_for_deletion() or not _live_node(_active_drag_layer) or not _drag_input_allowed()):
		cancel_drag()
		return
	_update_hovered_drop_zone(_last_pointer)


func _unhandled_input(event: InputEvent) -> void:
	if is_world_input_blocked():
		return
	if direct_mouse_gestures and (event.is_action_pressed(INPUT_ORGANIZE_TOGGLE) or event.is_action_pressed(INPUT_USE_TOGGLE)):
		get_viewport().set_input_as_handled()
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
	elif event is InputEventMouseButton and event.button_index == _drag_button and not event.pressed:
		var viewport := get_viewport()
		release_drop(event.position)
		if is_instance_valid(viewport): viewport.set_input_as_handled()


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
	_start_drag_in_layer(payload, drag_node, viewport_position, drag_layer)
	return true


func _start_drag_in_layer(payload: HeldItemPayload, drag_node: Node2D, viewport_position: Vector2, layer: Node2D) -> void:

	_drag_button = MOUSE_BUTTON_RIGHT if direct_mouse_gestures and _direct_press_button == MOUSE_BUTTON_RIGHT and _modal_export_payload == null else MOUSE_BUTTON_LEFT
	current_payload = payload
	current_drag_node = drag_node
	_active_drag_layer = layer
	if is_portion_drag():
		_portion_mouse_mode = Input.mouse_mode
	_drag_origin_parent = drag_node.get_parent()
	_drag_had_origin_parent = _drag_origin_parent != null
	_drag_origin_transform = drag_node.transform
	if _drag_origin_parent == null:
		layer.add_child(drag_node)
		drag_node.position = layer.get_global_transform_with_canvas().affine_inverse() * viewport_position
	elif _drag_origin_parent != layer:
		reparent_preserving_transform(drag_node, layer)
	_drag_start_pointer = viewport_position
	_drag_start_position = drag_node.position

	cursor_service.set_state(CURSOR_STATE_DRAGGING)
	update_drag(viewport_position)
	if current_payload == payload:
		drag_started.emit(current_payload, current_drag_node)


func update_drag(viewport_position: Vector2) -> void:
	if not is_dragging():
		return
	if not _live_node(_active_drag_layer) or not _drag_input_allowed():
		cancel_drag()
		return
	_last_pointer = viewport_position
	# Transform a displacement instead of round-tripping the large absolute
	# authored position through canvas coordinates. A stationary pickup or a
	# return to its starting pointer keeps an exact touching base unchanged.
	var displacement := viewport_position - _drag_start_pointer
	var canvas_inverse := _active_drag_layer.get_global_transform_with_canvas().affine_inverse()
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
	_cancel_drag_resolution()


func _cancel_drag_resolution() -> void:
	# Also used after a rejection callback while the same resolution guard is
	# still held. Observers cannot replace a payload between feedback and rollback.
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
	if not _drag_input_allowed() or _drag_pointer_over_ui(viewport_position):
		cancel_drag()
		return
	update_drag(viewport_position)
	if (not is_instance_valid(hovered_drop_zone) or not can_address_drop_zone(current_payload, hovered_drop_zone)
		or not hovered_drop_zone.is_relevant_to(current_payload)):
		cancel_drag()
		return

	var dropped_payload := current_payload
	var target_zone := hovered_drop_zone
	var validation := target_zone.accepts(dropped_payload)
	if not can_address_drop_zone(dropped_payload, target_zone):
		cancel_drag()
		return
	if not validation.is_valid:
		_resolving_drag = true
		var self_ref: WeakRef = weakref(self)
		target_zone.on_rejected_release(dropped_payload, validation)
		# The callback may remove this controller/scene. Teardown already clears
		# its gesture without restoring nodes into a disappearing hierarchy.
		if self_ref.get_ref() != null and current_payload == dropped_payload and is_inside_tree():
			_cancel_drag_resolution()
		return
	# Target/stock signals are synchronous. A command owns its gesture until all
	# observers finish, so a listener cannot replace the payload mid-commit.
	_resolving_drag = true
	var owner_ref: WeakRef = weakref(self)
	var applied := target_zone.try_apply_drop(dropped_payload)
	if owner_ref.get_ref() == null or not is_inside_tree() or is_queued_for_deletion() or current_payload != dropped_payload:
		return
	if not applied:
		_resolving_drag = false
		cancel_drag()
		return
	_dispose_transient_drag()
	_clear_drag_state()
	cursor_service.reset()
	drag_dropped.emit(dropped_payload, target_zone if is_instance_valid(target_zone) else null)
	if owner_ref.get_ref() != null and is_inside_tree(): _finish_drag_resolution()


func _finish_drag_resolution() -> void:
	_resolving_drag = false
	if direct_mouse_gestures:
		_queued_mode = &""
		_restore_direct_idle()
		return
	if not _queued_mode.is_empty():
		var mode := _queued_mode
		_queued_mode = &""
		set_mode(mode)


func toggle_mode() -> void:
	select_mode(MODE_ORGANIZE)


func select_mode(mode: StringName) -> void:
	if direct_mouse_gestures:
		return
	if not is_world_input_blocked():
		set_mode(MODE_NEUTRAL if current_mode == mode else mode)


func set_mode(mode: StringName) -> void:
	assert(mode in [MODE_NEUTRAL, MODE_INTERACT, MODE_ORGANIZE], "Unsupported interaction mode: %s" % mode)
	if direct_mouse_gestures and not _direct_mode_change:
		mode = MODE_INTERACT
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
	if direct_mouse_gestures:
		report_hint("Left click or drag to use · right drag to move · Esc cancels")
	elif current_mode == MODE_NEUTRAL:
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


func is_portion_drag() -> bool:
	return current_payload != null and current_payload.metadata.get("portion") is IngredientPortion


func _portion_target_name() -> String:
	return "target" if current_payload.metadata.get("category") == &"ready_item" else "vessel"


func _apply_drag_cursor(state: StringName) -> void:
	cursor_service.set_state(state)
	if _portion_mouse_mode >= 0:
		# The held portion itself is the cursor. Keep the invalid system cue over
		# blocked targets/UI, but do not draw a second cursor over the held piece.
		Input.mouse_mode = _portion_mouse_mode if state == CURSOR_STATE_INVALID else Input.MOUSE_MODE_HIDDEN


func _update_hovered_drop_zone(viewport_position: Vector2) -> void:
	if _drag_pointer_over_ui(viewport_position) or not _drag_input_allowed():
		if is_instance_valid(hovered_drop_zone):
			hovered_drop_zone.clear_highlight()
		hovered_drop_zone = null
		_apply_drag_cursor(CURSOR_STATE_INVALID)
		if is_portion_drag():
			report_hint("Move off the panel to a valid %s · Esc cancels" % _portion_target_name())
		return
	var best_valid: DropZone
	var best_valid_distance := INF
	var best_invalid: DropZone
	var best_invalid_distance := INF
	var cup_placement: DropZone
	var owner_ref: WeakRef = weakref(self)
	var selection_payload := current_payload

	for zone in _get_available_drop_zones():
		if not is_instance_valid(zone) or not zone.is_inside_tree() or zone.is_queued_for_deletion():
			continue
		if not can_address_drop_zone(current_payload, zone):
			continue
		if not zone.is_relevant_to(current_payload):
			continue
		var pointer_allowed := zone.allows_pointer(selection_payload, viewport_position)
		if owner_ref.get_ref() == null or not is_inside_tree() or current_payload != selection_payload:
			return
		if not pointer_allowed or not is_instance_valid(zone) or not zone.is_inside_tree() or zone.is_queued_for_deletion():
			continue
		# Returning cups can be parked in Use, but a deliberate station drop
		# (including a full bucket) takes precedence over surface placement.
		if zone is CupTransferDropZone:
			cup_placement = zone
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
	if next_zone == null: next_zone = cup_placement
	# A portion aimed at an unavailable target must not jump to a valid neighbour.
	if (is_portion_drag()
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
		if is_portion_drag():
			var adding_ingredient := hovered_drop_zone.zone_id == &"ingredient_portion"
			var accepted_hint := "Release to add this portion · Esc cancels" if adding_ingredient else "Release to hand over this item · Esc cancels"
			report_hint(accepted_hint if is_valid else validation.reason_key)
	else:
		_apply_drag_cursor(_drag_cursor())
		if is_portion_drag():
			report_hint("Move this portion over a valid %s · Esc cancels" % _portion_target_name())


func _collect_drop_zones(parent: Node) -> Array[DropZone]:
	var zones: Array[DropZone] = []
	for child in parent.get_children():
		if child is DropZone:
			zones.append(child)
		zones.append_array(_collect_drop_zones(child))
	return zones


func _get_available_drop_zones() -> Array[DropZone]:
	if _modal_export_payload != null:
		# The modal's explicit target contract does not require registering these
		# temporary adapters as ordinary world targets.
		return _modal_export_targets.duplicate()
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
	if current_payload != null:
		var transfers: Variant = current_payload.metadata.get("cup_transfer")
		if transfers is CupTransfer and is_instance_valid(transfers) and transfers.restore_transfer_origin(current_payload):
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
	_active_drag_layer = null
	_drag_button = MOUSE_BUTTON_LEFT
	_modal_export_owner = null
	_modal_export_payload = null
	_modal_export_targets.clear()
	_modal_export_ignored_ui.clear()
