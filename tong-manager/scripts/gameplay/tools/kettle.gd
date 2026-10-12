class_name Kettle
extends Area2D

signal contents_changed
signal pour_finished

enum BrewState { EMPTY, WATER, HEATING, BOILING, STEEPING, LIQUOR_READY, OVERSTEEPED }

const HELD_TILT := -0.18
const POUR_HEIGHT := 65.0

@export var tool_def: Resource = preload("res://data/balance/tool_level_1.tres")
@export var config: BrewingConfig = preload("res://data/balance/brewing_level_1.tres")

var state: BrewState = BrewState.EMPTY
var volume_ml := 0.0
var temperature := 20.0
var contains_tea := false
var steep_progress := 0.0
# Retained field name; this is elapsed ready time regardless of heat.
var ready_heat_seconds := 0.0
var is_pouring := false
var is_held := false
var pour_target: Cup
var current_burner: Node2D
var controller: InteractionController
var _origin_parent: Node
var _origin_transform := Transform2D.IDENTITY
var _hovered := false
var _lid_amount := 0.0
var _steam_time := 0.0
var _lid_rest := Vector2.ZERO
var _pour_zone: BrewingDropZone
var _pour_requires_release := false

@onready var lid: Node2D = $Lid
@onready var status: Label = $Status
@onready var spout: Marker2D = $Spout
@onready var grip_anchor: Marker2D = $GripAnchor
@onready var steam_anchor: Marker2D = $SteamAnchor

func _ready() -> void:
	_lid_rest = lid.position
	temperature = config.ambient_temperature
	input_event.connect(_on_input)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	steam_anchor.draw.connect(_draw_steam)
	add_to_group("kettles")
	_update_status()

func bind_controller(value: InteractionController) -> void:
	controller = value
	controller.drag_canceled.connect(_on_drag_canceled)
	controller.drag_moved.connect(_on_drag_moved)
	controller.mode_changed.connect(_on_mode_changed)

func add_water(amount_ml: float) -> float:
	if not is_finite(amount_ml) or amount_ml <= 0.0 or contains_tea or is_pouring:
		return 0.0
	var accepted := minf(amount_ml, maxf(0.0, float(tool_def.kettle_capacity_ml) - volume_ml))
	if accepted <= 0.0:
		return 0.0
	temperature = (temperature * volume_ml + config.ambient_temperature * accepted) / (volume_ml + accepted)
	volume_ml += accepted
	state = BrewState.WATER
	_changed()
	return accepted

func add_tea_leaves() -> bool:
	if contains_tea or volume_ml <= 0.0 or temperature < config.boiling_temperature or is_pouring:
		return false
	contains_tea = true
	steep_progress = 0.0
	state = BrewState.STEEPING
	_changed()
	return true

func apply_heat(delta: float, intensity: float) -> void:
	if delta <= 0.0 or not is_finite(delta) or not is_finite(intensity) or intensity <= 0.0:
		return
	if volume_ml <= 0.0 or is_held or is_pouring:
		return
	temperature = minf(config.boiling_temperature, temperature + config.heat_rate * intensity * delta)
	if not contains_tea:
		state = BrewState.BOILING if temperature >= config.boiling_temperature else BrewState.HEATING
	_changed()

func advance_brewing(delta: float) -> void:
	# One elapsed clock belongs to the kettle, independent of burner heat input.
	if not is_finite(delta) or delta <= 0.0 or volume_ml <= 0.0 or not contains_tea:
		return
	var remaining_time := delta
	if state == BrewState.STEEPING:
		var until_ready := maxf(0.0, config.steep_seconds - steep_progress)
		if remaining_time + 0.000000001 < until_ready:
			steep_progress += remaining_time
			_changed()
			return
		steep_progress = config.steep_seconds
		remaining_time = maxf(0.0, remaining_time - until_ready)
		state = BrewState.LIQUOR_READY
	if state == BrewState.LIQUOR_READY:
		ready_heat_seconds = minf(config.oversteep_seconds, ready_heat_seconds + remaining_time)
		if ready_heat_seconds + 0.000000001 >= config.oversteep_seconds:
			ready_heat_seconds = config.oversteep_seconds
			state = BrewState.OVERSTEEPED
			stop_pour()
	_changed()

func can_pour_into(cup: Cup) -> bool:
	return is_instance_valid(cup) and cup.is_inside_tree() and not cup.is_queued_for_deletion() and state == BrewState.LIQUOR_READY and volume_ml > 0.0 and cup.can_receive_liquid(&"black_tea")

func start_pour(cup: Cup) -> bool:
	if is_pouring or not can_pour_into(cup):
		return false
	if is_held and (_pour_requires_release or _held_cup_target() != cup):
		return false
	if controller != null and not is_held and not controller.lock_action(self):
		return false
	if not is_held:
		_remember_origin()
	is_pouring = true
	pour_target = cup
	_pour_zone = controller.hovered_drop_zone as BrewingDropZone if is_held else null
	pour_target.contents_discarded.connect(_on_target_discarded)
	rotation = HELD_TILT
	_changed()
	return true

func update_pour(delta: float) -> void:
	if not is_pouring:
		return
	if not is_instance_valid(pour_target) or not can_pour_into(pour_target) or (is_held and (not is_instance_valid(_pour_zone) or not _valid_pour_zone(_pour_zone, pour_target))):
		stop_pour()
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	var transferred := pour_target.receive_liquid(&"black_tea", minf(volume_ml, config.pour_rate_ml * delta), temperature)
	volume_ml = maxf(0.0, volume_ml - transferred)
	if volume_ml <= 0.0001:
		volume_ml = 0.0
		contains_tea = false
		steep_progress = 0.0
		ready_heat_seconds = 0.0
		state = BrewState.EMPTY
	_changed()
	if transferred <= 0.0 or not is_instance_valid(pour_target) or not can_pour_into(pour_target):
		stop_pour()

func stop_pour() -> void:
	if not is_pouring:
		return
	is_pouring = false
	if is_instance_valid(pour_target) and pour_target.contents_discarded.is_connected(_on_target_discarded):
		pour_target.contents_discarded.disconnect(_on_target_discarded)
	pour_target = null
	_pour_zone = null
	rotation = HELD_TILT if is_held else 0.0
	if not is_held:
		_restore_origin()
	if controller != null:
		controller.unlock_action(self)
	_changed()
	pour_finished.emit()

func cancel_action() -> void:
	stop_pour()

func discard_contents() -> float:
	stop_pour()
	var discarded := volume_ml
	volume_ml = 0.0
	contains_tea = false
	steep_progress = 0.0
	ready_heat_seconds = 0.0
	state = BrewState.EMPTY
	_changed()
	return discarded

func _on_target_discarded(_discarded_ml: float) -> void:
	_pour_requires_release = true
	stop_pour()

func _valid_pour_zone(zone: BrewingDropZone, cup: Cup) -> bool:
	return is_instance_valid(zone) and zone.is_inside_tree() and not zone.is_queued_for_deletion() and zone.is_cup_target and is_instance_valid(cup) and cup.is_inside_tree() and cup.is_ancestor_of(zone) and zone.target == cup

func _held_cup_target() -> Cup:
	if not is_instance_valid(controller) or not controller.is_dragging() or controller.current_drag_node != self:
		return null
	var zone := controller.hovered_drop_zone as BrewingDropZone if is_instance_valid(controller.hovered_drop_zone) else null
	if not is_instance_valid(zone) or not is_instance_valid(zone.target) or not zone.target is Cup:
		return null
	var cup := zone.target as Cup
	return cup if _valid_pour_zone(zone, cup) else null

func finish_cup_interaction() -> void:
	stop_pour()
	_restore_origin()

func update_held_pour(pour_pressed: bool) -> void:
	if not pour_pressed:
		_pour_requires_release = false
	if not is_held or controller == null:
		return
	var cup := _held_cup_target()
	if not pour_pressed or cup != pour_target:
		stop_pour()
	if pour_pressed and not _pour_requires_release and not is_pouring and can_pour_into(cup):
		start_pour(cup)

func get_pour_probe_viewport() -> Vector2:
	# Aim below the visible spout; the pointer stays at the handle.
	var parent := get_parent() as Node2D
	var canvas := parent.get_global_transform_with_canvas()
	return spout.get_global_transform_with_canvas().origin + canvas.basis_xform(Vector2(0, POUR_HEIGHT))

func _position_grip_at(viewport_position: Vector2) -> void:
	var parent := get_parent() as Node2D
	var pointer_local := parent.get_global_transform_with_canvas().affine_inverse() * viewport_position
	position += pointer_local - transform * grip_anchor.position

func _on_drag_moved(payload: HeldItemPayload, viewport_position: Vector2) -> void:
	if payload.world_node == self and is_held:
		# Keep a stable aiming pose so starting/stopping flow never shifts the spout.
		rotation = HELD_TILT
		_position_grip_at(viewport_position)

func begin_drag(viewport_position: Vector2) -> bool:
	if controller == null or controller.current_mode != InteractionController.MODE_INTERACT:
		return false
	if controller.is_dragging() or controller.has_active_action() or is_pouring:
		return false
	_remember_origin()
	is_held = true
	var payload := HeldItemPayload.new(&"workstation", &"kettle", 1, self, {"category": &"kettle"})
	if controller.start_drag(payload, self, viewport_position):
		return true
	is_held = false
	return false

func finish_seating() -> void:
	is_held = false
	rotation = 0.0
	_remember_origin()

func _remember_origin() -> void:
	_origin_parent = get_parent()
	_origin_transform = transform

func _restore_origin() -> void:
	if is_instance_valid(_origin_parent):
		if get_parent() != _origin_parent:
			reparent(_origin_parent, false)
		transform = _origin_transform
	is_held = false

func _process(delta: float) -> void:
	update_held_pour(Input.is_action_pressed(InteractionController.INPUT_POUR))
	var pour_delta := minf(delta, maxf(0.0, config.oversteep_seconds - ready_heat_seconds)) if state == BrewState.LIQUOR_READY else delta
	update_pour(pour_delta)
	advance_brewing(delta)
	var heated: bool = is_instance_valid(current_burner) and current_burner.get("heat_level") > 0 and not is_held and not is_pouring
	if not heated:
		temperature = maxf(config.ambient_temperature, temperature - config.cooling_rate * delta)
		if not contains_tea and volume_ml > 0.0 and temperature < config.boiling_temperature:
			state = BrewState.WATER
	_lid_amount = move_toward(_lid_amount, 1.0 if _hovered and not is_held and not is_pouring else 0.0, delta * 7.0)
	lid.position = _lid_rest + Vector2(0.0, -13.0 * _lid_amount)
	lid.rotation = -0.045 * _lid_amount
	_steam_time += delta
	_update_status()
	steam_anchor.queue_redraw()
	queue_redraw()

func _draw_steam() -> void:
	if volume_ml > 0.0 and temperature > 60.0:
		var strength := clampf((temperature - 60.0) / 40.0, 0.0, 1.0)
		for i in 3:
			var points := PackedVector2Array()
			for j in 13:
				points.append(Vector2((i - 1) * 12.0 + sin(_steam_time * 2.0 + j * .5 + i) * 5.0, -j * (5.0 + _lid_amount * 2.0)))
			steam_anchor.draw_polyline(points, Color(.85, .86, .93, strength * (.25 + _lid_amount * .35)), 2.5, true)

func _draw() -> void:
	if not is_node_ready():
		return
	if is_pouring and is_instance_valid(pour_target):
		draw_line(spout.position, to_local(pour_target.global_position + Vector2(0, -12)), Color(.58,.29,.10,.9), 4.0, true)

func _update_status() -> void:
	if not is_node_ready():
		return
	var state_text: String = ["Empty", "Water", "Heating", "Boiling", "Steeping", "Tea ready", "Oversteeped"][state]
	status.text = tr(state_text) + " · %d ml" % roundi(volume_ml)
	if volume_ml > 0.0:
		status.text += " · %d°C" % roundi(temperature)

func _changed() -> void:
	_update_status()
	contents_changed.emit()

func _on_input(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if begin_drag(event.position):
			get_viewport().set_input_as_handled()

func _on_hover(entered: bool) -> void:
	_hovered = entered
	if controller != null and not controller.is_dragging() and not controller.has_active_action():
		get_node("/root/CursorService").set_state(&"hover_actionable" if entered else &"default")

func _on_drag_canceled(payload: HeldItemPayload) -> void:
	if payload.world_node == self:
		is_held = false
		stop_pour()

func _on_mode_changed(_mode: StringName) -> void:
	stop_pour()

func _exit_tree() -> void:
	# Reparenting during drag also emits tree_exiting; do not clear ownership here.
	if controller != null and is_queued_for_deletion():
		controller.unlock_action(self)
