class_name Kettle
extends Area2D

signal contents_changed
signal pour_finished

enum BrewState { EMPTY, WATER, HEATING, BOILING, STEEPING, LIQUOR_READY, OVERSTEEPED }

const HELD_TILT := -0.18
const POUR_HEIGHT := 65.0

@export var tool_def: Resource = preload("res://data/balance/tool_level_1.tres")
@export var config: BrewingConfig = preload("res://data/balance/brewing_level_1.tres")
@export var water_stream_color := Color(0.447, 0.725, 0.82, 0.9)

var state: BrewState = BrewState.EMPTY
var volume_ml := 0.0
var temperature := 20.0
var brewed_liquid_id: StringName = &""
var _infused_counts: Dictionary[StringName, int] = {}
var _mixed_amounts: Dictionary[StringName, float] = {}
var _used_boiling_water := false
var _batch_volume_ml := 0.0
# Compatibility for earlier fixtures. Live brewing uses counted batch contents.
var contains_tea: bool:
	get:
		return not _infused_counts.is_empty()
	set(value):
		if not value:
			_infused_counts.clear()
			brewed_liquid_id = &""
			steep_progress = 0.0
			ready_heat_seconds = 0.0
			_used_boiling_water = false
			_batch_volume_ml = 0.0
		elif _infused_counts.is_empty():
			_infused_counts[&"black_tea"] = 1
			brewed_liquid_id = &"black_tea"
			_used_boiling_water = config != null and temperature >= config.boiling_temperature
			_batch_volume_ml = volume_ml
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
	_batch_volume_ml = volume_ml
	state = BrewState.WATER
	_changed()
	return accepted

func add_tea_leaves() -> bool:
	# Legacy entry point uses the same configured permission and effect path.
	var policy: Resource = load("res://data/balance/ingredient_policy.tres")
	return bool(policy.apply(&"black_tea", &"teabag", 1, self))


func get_infused_counts() -> Dictionary[StringName, int]:
	return _infused_counts.duplicate()


func get_mixed_amounts() -> Dictionary[StringName, float]:
	return _mixed_amounts.duplicate()


func get_ingredient_amounts() -> Dictionary[StringName, float]:
	var amounts := _mixed_amounts.duplicate()
	for item_id in _infused_counts:
		amounts[item_id] = amounts.get(item_id, 0.0) + float(_infused_counts[item_id])
	return amounts


func get_ingredient_stage() -> StringName:
	return [&"empty", &"water", &"heating", &"boiling", &"steeping", &"liquor_ready", &"oversteeped"][state] if state >= 0 and state <= BrewState.OVERSTEEPED else &"invalid"


func has_contents() -> bool:
	return volume_ml > 0.0 or not _infused_counts.is_empty() or not _mixed_amounts.is_empty()


func can_apply_ingredient(item_id: StringName, quantity: int, effect: StringName, output_liquid_id: StringName = &"") -> bool:
	if (not is_inside_tree() or is_queued_for_deletion() or item_id.is_empty() or quantity <= 0
		or get_ingredient_stage() == &"invalid" or tool_def == null or config == null
		or not is_finite(volume_ml) or not is_finite(temperature) or volume_ml < 0.0
		or tool_def.kettle_capacity_ml <= 0 or volume_ml > float(tool_def.kettle_capacity_ml)):
		return false
	if effect == &"mix":
		return output_liquid_id.is_empty() and is_finite(_mixed_amounts.get(item_id, 0.0) + float(quantity))
	if effect != &"infuse" or output_liquid_id.is_empty() or volume_ml <= 0.0:
		return false
	return ((_infused_counts.is_empty() or brewed_liquid_id == output_liquid_id)
		and _infused_counts.get(item_id, 0) <= 9223372036854775807 - quantity)


func apply_ingredient(item_id: StringName, quantity: int, effect: StringName, output_liquid_id: StringName = &"", restart_steeping := false) -> bool:
	if not can_apply_ingredient(item_id, quantity, effect, output_liquid_id):
		return false
	if effect == &"mix":
		_mixed_amounts[item_id] = _mixed_amounts.get(item_id, 0.0) + float(quantity)
	else:
		var first_infusion := _infused_counts.is_empty()
		if first_infusion:
			_used_boiling_water = temperature >= config.boiling_temperature
			_batch_volume_ml = volume_ml
		_infused_counts[item_id] = _infused_counts.get(item_id, 0) + quantity
		brewed_liquid_id = output_liquid_id
		if first_infusion or restart_steeping:
			steep_progress = 0.0
			ready_heat_seconds = 0.0
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
	_changed()


func get_pour_liquid_id() -> StringName:
	return brewed_liquid_id if contains_tea else &"water"


func get_brew_batch_snapshot() -> Dictionary:
	var quality: StringName = &"water"
	if contains_tea:
		quality = &"ready" if state == BrewState.LIQUOR_READY else (&"oversteeped" if state == BrewState.OVERSTEEPED else &"underbrewed")
	var original_volume := _batch_volume_ml if contains_tea else volume_ml
	var mixed_counts: Dictionary[StringName, float] = {}
	if volume_ml > 0.0:
		for item_id in _mixed_amounts:
			if _mixed_amounts[item_id] > 0.0:
				mixed_counts[item_id] = _mixed_amounts[item_id] * original_volume / volume_ml
	return {"state": quality, "infused_counts": _infused_counts.duplicate(),
		"used_boiling_water": _used_boiling_water, "batch_volume": original_volume,
		"mixed_counts": mixed_counts}


func can_pour_into(cup: Cup) -> bool:
	return (is_instance_valid(cup) and cup.is_inside_tree() and not cup.is_queued_for_deletion()
		and state in [BrewState.WATER, BrewState.HEATING, BrewState.BOILING, BrewState.STEEPING, BrewState.LIQUOR_READY, BrewState.OVERSTEEPED]
		and is_finite(volume_ml) and volume_ml > 0.0 and is_finite(temperature)
		and not get_pour_liquid_id().is_empty() and cup.can_receive_liquid(get_pour_liquid_id()))

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
	var requested := minf(volume_ml, config.pour_rate_ml * delta)
	var previous_volume := volume_ml
	var carried: Dictionary[StringName, float] = {}
	for item_id in _mixed_amounts:
		carried[item_id] = _mixed_amounts[item_id] * requested / previous_volume
	var receiver := pour_target
	var self_ref: WeakRef = weakref(self)
	# Suppress cup notifications until both vessels contain the completed transfer.
	# Capture quality before an empty source clears its ingredients, and never
	# re-read this kettle when the resulting cup is later handed to a customer.
	var transferred := receiver.receive_liquid(get_pour_liquid_id(), requested, temperature, carried, false, get_brew_batch_snapshot())
	for item_id in _mixed_amounts:
		_mixed_amounts[item_id] = maxf(0.0, _mixed_amounts[item_id] - carried[item_id] * transferred / requested) if requested > 0.0 else _mixed_amounts[item_id]
	volume_ml = maxf(0.0, volume_ml - transferred)
	if volume_ml <= 0.0:
		volume_ml = 0.0
		_clear_ingredients()
		state = BrewState.EMPTY
	if transferred > 0.0:
		receiver.notify_contents_changed()
	if self_ref.get_ref() == null:
		return
	_changed()
	if self_ref.get_ref() == null:
		return
	if is_pouring and pour_target == receiver and (transferred <= 0.0 or not is_instance_valid(pour_target) or not can_pour_into(pour_target)):
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
	_clear_ingredients()
	state = BrewState.EMPTY
	_changed()
	return discarded


func _clear_ingredients() -> void:
	_infused_counts.clear()
	_mixed_amounts.clear()
	brewed_liquid_id = &""
	steep_progress = 0.0
	ready_heat_seconds = 0.0
	_used_boiling_water = false
	_batch_volume_ml = 0.0

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
	if controller == null or controller.current_mode != InteractionController.MODE_INTERACT or not controller.can_start_world_action():
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
	_advance_pour_and_brewing(delta)
	var heated: bool = is_instance_valid(current_burner) and current_burner.get("heat_level") > 0 and not is_held and not is_pouring
	if not heated:
		temperature = maxf(config.ambient_temperature, temperature - config.cooling_rate * delta)
		if not contains_tea and volume_ml > 0.0 and temperature < config.boiling_temperature:
			state = BrewState.WATER
	var passive_hover := _hovered and (controller == null or (not controller.is_world_input_blocked() and not controller.is_pointer_over_ui()))
	_lid_amount = move_toward(_lid_amount, 1.0 if passive_hover and not is_held and not is_pouring else 0.0, delta * 7.0)
	lid.position = _lid_rest + Vector2(0.0, -13.0 * _lid_amount)
	lid.rotation = -0.045 * _lid_amount
	_steam_time += delta
	_update_status()
	steam_anchor.queue_redraw()
	queue_redraw()

func _advance_pour_and_brewing(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# A long frame can transfer liquid on both sides of a quality transition.
	# Split only at those boundaries: flow stays continuous, each elapsed slice
	# advances the one brewing clock once, and the cup retains both histories.
	var remaining := delta
	var self_ref: WeakRef = weakref(self)
	while remaining > 0.0:
		var step := remaining
		if is_pouring and contains_tea:
			if state == BrewState.STEEPING:
				step = minf(step, maxf(0.0, config.steep_seconds - steep_progress))
			elif state == BrewState.LIQUOR_READY:
				step = minf(step, maxf(0.0, config.oversteep_seconds - ready_heat_seconds))
		if step <= 0.0:
			# An externally restored timer may sit exactly on its next boundary.
			step = minf(remaining, 0.000000001)
			advance_brewing(step)
			if self_ref.get_ref() == null: return
			update_pour(step)
		else:
			update_pour(step)
			if self_ref.get_ref() == null: return
			advance_brewing(step)
		if self_ref.get_ref() == null: return
		remaining = maxf(0.0, remaining - step)

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
		draw_line(spout.position, to_local(pour_target.global_position + Vector2(0, -12)), get_pour_color(), 4.0, true)

func get_pour_color() -> Color:
	return water_stream_color if get_pour_liquid_id() == &"water" else Color(.58, .29, .10, .9)

func _update_status() -> void:
	if not is_node_ready():
		return
	status.hide()
	status.text = ""

func is_status_hovered() -> bool:
	return _hovered and (not is_instance_valid(controller)
		or (not controller.is_world_input_blocked() and not controller.is_pointer_over_ui_at(get_viewport().get_mouse_position())))

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
		var actionable := entered and controller.current_mode == InteractionController.MODE_INTERACT and controller.can_start_world_action()
		get_node("/root/CursorService").set_state(&"hover_actionable" if actionable else &"default")
		if actionable:
			controller.report_hint("Use · drag kettle by handle · hold Space to pour · drop on Discard to empty")

func _on_drag_canceled(payload: HeldItemPayload) -> void:
	if payload.world_node == self:
		is_held = false
		stop_pour()

func _on_mode_changed(_mode: StringName) -> void:
	stop_pour()
	if _hovered:
		_on_hover(true)

func _exit_tree() -> void:
	# Reparenting during drag also emits tree_exiting; do not clear ownership here.
	if controller != null and is_queued_for_deletion():
		controller.unlock_action(self)
