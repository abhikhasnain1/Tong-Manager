class_name InteractionController
extends Node

signal drag_started(payload: HeldItemPayload, drag_node: Node2D)
signal drag_moved(payload: HeldItemPayload, viewport_position: Vector2)
signal drag_canceled(payload: HeldItemPayload)
signal drag_dropped(payload: HeldItemPayload, drop_zone: DropZone)
signal mode_changed(mode: StringName)
signal action_requested(action: StringName)

const MODE_INTERACT := &"interact"
const MODE_ORGANIZE := &"organize"
const INPUT_ORGANIZE_TOGGLE := &"organize_toggle"
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
var current_mode: StringName = MODE_INTERACT

var _drag_origin_parent: Node
var _drag_origin_transform := Transform2D.IDENTITY


func _ready() -> void:
	assert(drag_layer != null, "InteractionController requires a DragLayer reference.")
	assert(drop_zone_root != null, "InteractionController requires a DropZoneRoot reference.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(INPUT_ORGANIZE_TOGGLE):
		toggle_mode()
		get_viewport().set_input_as_handled()
		return

	for action in FORWARDED_ACTIONS:
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


func start_drag(payload: HeldItemPayload, drag_node: Node2D, viewport_position: Vector2) -> bool:
	if payload == null or not is_instance_valid(drag_node):
		return false
	if is_dragging():
		cancel_drag()

	current_payload = payload
	current_drag_node = drag_node
	_drag_origin_parent = drag_node.get_parent()
	_drag_origin_transform = drag_node.transform
	if _drag_origin_parent == null:
		drag_layer.add_child(drag_node)
	elif _drag_origin_parent != drag_layer:
		drag_node.reparent(drag_layer, true)

	cursor_service.set_state(CURSOR_STATE_DRAGGING)
	update_drag(viewport_position)
	drag_started.emit(current_payload, current_drag_node)
	return true


func update_drag(viewport_position: Vector2) -> void:
	if not is_dragging():
		return
	current_drag_node.position = drag_layer.get_global_transform_with_canvas().affine_inverse() * viewport_position
	_update_hovered_drop_zone(viewport_position)
	drag_moved.emit(current_payload, viewport_position)


func cancel_drag() -> void:
	if not is_dragging():
		return
	var canceled_payload := current_payload
	_restore_drag_origin()
	_clear_drag_state()
	cursor_service.reset()
	drag_canceled.emit(canceled_payload)


func release_drop(viewport_position: Vector2) -> void:
	if not is_dragging():
		return
	update_drag(viewport_position)
	if hovered_drop_zone == null or not hovered_drop_zone.accepts(current_payload).is_valid:
		cancel_drag()
		return

	var dropped_payload := current_payload
	var target_zone := hovered_drop_zone
	target_zone.apply_drop(dropped_payload)
	_clear_drag_state()
	cursor_service.reset()
	drag_dropped.emit(dropped_payload, target_zone)


func toggle_mode() -> void:
	set_mode(MODE_ORGANIZE if current_mode == MODE_INTERACT else MODE_INTERACT)


func set_mode(mode: StringName) -> void:
	assert(mode == MODE_INTERACT or mode == MODE_ORGANIZE, "Unsupported interaction mode: %s" % mode)
	if mode == current_mode:
		return
	if is_dragging():
		cancel_drag()
	current_mode = mode
	mode_changed.emit(current_mode)


func _update_hovered_drop_zone(viewport_position: Vector2) -> void:
	var best_valid: DropZone
	var best_valid_distance := INF
	var best_invalid: DropZone
	var best_invalid_distance := INF

	for zone in _collect_drop_zones(drop_zone_root):
		var zone_viewport_position := zone.get_global_transform_with_canvas().origin
		var distance := viewport_position.distance_to(zone_viewport_position)
		var zone_scale := zone.get_global_transform_with_canvas().get_scale()
		var snap_radius_viewport := zone.snap_radius * maxf(absf(zone_scale.x), absf(zone_scale.y))
		if distance > snap_radius_viewport:
			continue
		if zone.accepts(current_payload).is_valid:
			if distance < best_valid_distance:
				best_valid = zone
				best_valid_distance = distance
		elif distance < best_invalid_distance:
			best_invalid = zone
			best_invalid_distance = distance

	var next_zone := best_valid if best_valid != null else best_invalid
	if hovered_drop_zone != null and hovered_drop_zone != next_zone:
		hovered_drop_zone.clear_highlight()
	hovered_drop_zone = next_zone
	if hovered_drop_zone != null:
		var is_valid := hovered_drop_zone.accepts(current_payload).is_valid
		hovered_drop_zone.set_highlight(is_valid)
		cursor_service.set_state(CURSOR_STATE_DRAGGING if is_valid else CURSOR_STATE_INVALID)
	else:
		cursor_service.set_state(CURSOR_STATE_DRAGGING)


func _collect_drop_zones(parent: Node) -> Array[DropZone]:
	var zones: Array[DropZone] = []
	for child in parent.get_children():
		if child is DropZone:
			zones.append(child)
		zones.append_array(_collect_drop_zones(child))
	return zones


func _restore_drag_origin() -> void:
	if not is_instance_valid(current_drag_node):
		return
	if is_instance_valid(_drag_origin_parent):
		if current_drag_node.get_parent() != _drag_origin_parent:
			current_drag_node.reparent(_drag_origin_parent, false)
		current_drag_node.transform = _drag_origin_transform
	elif current_drag_node.get_parent() != null:
		current_drag_node.get_parent().remove_child(current_drag_node)
		current_drag_node.transform = _drag_origin_transform


func _clear_drag_state() -> void:
	if hovered_drop_zone != null:
		hovered_drop_zone.clear_highlight()
	hovered_drop_zone = null
	current_payload = null
	current_drag_node = null
	_drag_origin_parent = null
	_drag_origin_transform = Transform2D.IDENTITY
