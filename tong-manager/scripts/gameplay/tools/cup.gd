class_name Cup
extends Area2D

signal state_changed(previous_state: CupState, current_state: CupState)
signal liquid_changed(volume_ml: float)
signal temperature_changed(temperature: float)
signal contents_discarded(volume_ml: float)
signal contents_changed(
	contents_base_id: StringName,
	relish_item_ids: Array[StringName],
	assigned_order_id: StringName
)

enum CupState {
	CLEAN,
	IN_USE,
	FILLED,
	SERVED,
	DIRTY,
}

const ALLOWED_TRANSITIONS: Dictionary = {
	CupState.CLEAN: [CupState.IN_USE, CupState.FILLED],
	CupState.IN_USE: [CupState.FILLED],
	CupState.FILLED: [CupState.SERVED],
	CupState.SERVED: [CupState.DIRTY],
	CupState.DIRTY: [],
}

@export_group("Visuals")
@export var clean_texture: Texture2D
@export var dirty_texture: Texture2D
@export var water_color := Color("72b9d1")

@export_group("Runtime State")
@export var state: CupState = CupState.CLEAN
@export var contents_base_id: StringName = &""
@export var relish_item_ids: Array[StringName] = []
@export var assigned_order_id: StringName = &""
@export var capacity_ml := 250.0
@export var config: BrewingConfig = preload("res://data/balance/brewing_level_1.tres")
var volume_ml := 0.0
var liquid_type: StringName = &""
var temperature := 20.0
var controller: InteractionController
var _hovered := false
var _inherited_ingredient_amounts: Dictionary[StringName, float] = {}
var _brew_batches: Array[Dictionary] = []
var _brew_history_complete := true
var brew_batches: Array[Dictionary]:
	get: return _brew_batches.duplicate(true)
	set(_value): pass
var brew_history_complete: bool:
	get: return _brew_history_complete
	set(_value): pass
var _pending_state_from := -1
var _tea_contents_texture: Texture2D
var _water_contents_texture: GradientTexture2D

func can_receive_liquid(kind: StringName) -> bool:
	return (
		not kind.is_empty() and state in [CupState.CLEAN, CupState.IN_USE, CupState.FILLED]
		and is_finite(volume_ml) and is_finite(capacity_ml) and is_finite(temperature)
		and volume_ml >= 0.0 and capacity_ml > 0.0
		and volume_ml < capacity_ml - 0.0001
		and (liquid_type.is_empty() or liquid_type == kind)
	)

func receive_liquid(kind: StringName, amount_ml: float, liquid_temperature: float = 20.0, carried_amounts: Dictionary[StringName, float] = {}, notify := true, brew_batch: Dictionary = {}) -> float:
	if not is_finite(amount_ml) or not is_finite(liquid_temperature) or amount_ml <= 0.0 or not can_receive_liquid(kind):
		return 0.0
	if not _valid_brew_batch(brew_batch):
		return 0.0
	for item_id in carried_amounts:
		if item_id.is_empty() or not is_finite(carried_amounts[item_id]) or carried_amounts[item_id] < 0.0:
			return 0.0
	var accepted := minf(amount_ml, maxf(0.0, capacity_ml - volume_ml))
	var next_amounts := _inherited_ingredient_amounts.duplicate()
	for item_id in carried_amounts:
		var next: float = next_amounts.get(item_id, 0.0) + carried_amounts[item_id] * accepted / amount_ml
		if not is_finite(next):
			return 0.0
		next_amounts[item_id] = next
	_remember_state_change()
	temperature = (temperature * volume_ml + liquid_temperature * accepted) / (volume_ml + accepted)
	volume_ml += accepted
	liquid_type = kind
	contents_base_id = kind
	_inherited_ingredient_amounts = next_amounts
	if not brew_batch.is_empty() and not _brew_batches.has(brew_batch):
		_brew_batches.append(brew_batch.duplicate(true))
	elif brew_batch.is_empty() and kind != &"water":
		# Older/custom liquid callers can omit history, but later known tea must
		# never make that unrecorded contribution appear fully verified.
		_brew_history_complete = false
	state = CupState.FILLED
	if notify:
		notify_contents_changed()
	return accepted


func _valid_brew_batch(batch: Dictionary) -> bool:
	if batch.is_empty(): return true
	if (batch.get("state") not in [&"water", &"underbrewed", &"ready", &"oversteeped"]
		or typeof(batch.get("used_boiling_water")) != TYPE_BOOL
		or typeof(batch.get("infused_counts")) != TYPE_DICTIONARY):
		return false
	if batch.has("batch_volume") and (typeof(batch.batch_volume) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(batch.batch_volume)) or float(batch.batch_volume) <= 0.0):
		return false
	for item_id in batch.infused_counts:
		if (typeof(item_id) not in [TYPE_STRING, TYPE_STRING_NAME] or String(item_id).is_empty()
			or typeof(batch.infused_counts[item_id]) != TYPE_INT or batch.infused_counts[item_id] <= 0):
			return false
	var mixed: Variant = batch.get("mixed_counts", {})
	if typeof(mixed) != TYPE_DICTIONARY: return false
	for item_id in mixed:
		if (typeof(item_id) not in [TYPE_STRING, TYPE_STRING_NAME] or String(item_id).is_empty()
			or typeof(mixed[item_id]) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(mixed[item_id])) or float(mixed[item_id]) <= 0.0):
			return false
	return true


func get_service_snapshot() -> Dictionary:
	return {"kind": &"cup", "lifecycle": get_ingredient_stage(), "volume": volume_ml,
		"capacity": capacity_ml, "liquid_id": liquid_type, "temperature": temperature,
		"cold_threshold": config.cold_temperature if config != null else NAN,
		"ingredient_amounts": get_ingredient_amounts(), "brew_batches": brew_batches,
		"inherited_ingredient_amounts": get_inherited_ingredient_amounts(),
		"brew_history_complete": _brew_history_complete}


func commit_served(order_id: StringName) -> bool:
	# The handoff command stages all authorities before publishing any signals.
	if (not is_inside_tree() or is_queued_for_deletion() or not OrderRequestDef.valid_identity(order_id)
		or state not in [CupState.CLEAN, CupState.IN_USE, CupState.FILLED]
		or not assigned_order_id.is_empty() or not is_finite(volume_ml) or volume_ml < 0.0):
		return false
	var nonempty := volume_ml > 0.0
	for amount: float in get_ingredient_amounts().values():
		if not is_finite(amount) or amount < 0.0: return false
		nonempty = nonempty or amount > 0.0
	if not nonempty: return false
	_remember_state_change()
	assigned_order_id = order_id
	state = CupState.SERVED
	return true


func _remember_state_change() -> void:
	if _pending_state_from < 0:
		_pending_state_from = state


func notify_contents_changed(notify_liquid := true) -> void:
	# A kettle commits both vessels before publishing either side of a pour.
	var previous := _pending_state_from
	_pending_state_from = -1
	var self_ref: WeakRef = weakref(self)
	_apply_state_visuals()
	if self_ref.get_ref() == null:
		return
	if previous >= 0 and previous != state:
		state_changed.emit(previous, state)
	if self_ref.get_ref() == null:
		return
	if notify_liquid:
		liquid_changed.emit(volume_ml)
		if self_ref.get_ref() == null:
			return
		temperature_changed.emit(temperature)
	if self_ref.get_ref() != null:
		contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)

func is_cold() -> bool:
	return volume_ml > 0.0 and temperature <= config.cold_temperature

func advance_cooling(delta: float) -> void:
	if volume_ml <= 0.0 or not is_finite(delta) or delta <= 0.0:
		return
	var cooled := move_toward(temperature, config.ambient_temperature, config.cup_cooling_rate * delta)
	if cooled == temperature:
		return
	temperature = cooled
	_update_volume_marker(volume_ml)
	temperature_changed.emit(temperature)

func _process(delta: float) -> void:
	advance_cooling(delta)

func discard_contents() -> float:
	var discarded := volume_ml
	_remember_state_change()
	volume_ml = 0.0
	liquid_type = &""
	contents_base_id = &""
	relish_item_ids.clear()
	_inherited_ingredient_amounts.clear()
	_brew_batches.clear()
	_brew_history_complete = true
	temperature = config.ambient_temperature
	if state == CupState.FILLED:
		state = CupState.IN_USE
	var self_ref: WeakRef = weakref(self)
	# Contents are already coherent when the incoming kettle is told to stop.
	contents_discarded.emit(discarded)
	if self_ref.get_ref() != null:
		notify_contents_changed()
	return discarded

@onready var cup_sprite: Sprite2D = $Sprite2D
@onready var contents_overlay: Sprite2D = $ContentsOverlay
@onready var volume_marker: Label = $VolumeMarker


func _ready() -> void:
	assert(clean_texture != null, "Cup requires a clean texture.")
	assert(dirty_texture != null, "Cup requires a dirty texture.")
	if volume_ml <= 0.0:
		temperature = config.ambient_temperature
	_tea_contents_texture = contents_overlay.texture
	var gradient_texture := _tea_contents_texture as GradientTexture2D
	if gradient_texture != null and gradient_texture.gradient != null:
		# Each cup owns its water gradient; changing one cup must not recolor
		# every instance of the shared authored tea surface.
		_water_contents_texture = gradient_texture.duplicate() as GradientTexture2D
		_water_contents_texture.gradient = gradient_texture.gradient.duplicate() as Gradient
		var colors := gradient_texture.gradient.colors
		for index in colors.size():
			_water_contents_texture.gradient.set_color(index, Color(water_color, colors[index].a))
	liquid_changed.connect(_update_volume_marker)
	_update_volume_marker(volume_ml)
	_apply_state_visuals()
	input_event.connect(_on_input)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	add_to_group(&"cups")
	_configure_in_screen.call_deferred()


func bind_controller(value: InteractionController) -> void:
	if not is_instance_valid(value) or value.is_queued_for_deletion():
		return
	if is_instance_valid(controller) and controller.mode_changed.is_connected(_refresh_hover):
		controller.mode_changed.disconnect(_refresh_hover)
	var zone := get_node_or_null("PourTarget") as BrewingDropZone
	if zone != null and is_instance_valid(zone.controller) and zone.controller != value:
		zone.controller.unregister_drop_zone(zone)
	if zone != null and zone.is_queued_for_deletion():
		if is_instance_valid(zone.controller):
			zone.controller.unregister_drop_zone(zone)
		remove_child(zone)
		zone = null
	if zone == null:
		zone = BrewingDropZone.new()
		zone.name = "PourTarget"
		add_child(zone)
	controller = value
	controller.mode_changed.connect(_refresh_hover)
	zone.is_cup_target = true
	zone.target = self
	zone.controller = controller
	zone.snap_radius = 30.0
	zone.position = Vector2(0, -12)
	zone.input_pickable = false
	controller.register_drop_zone(zone)


func begin_interaction_drag(viewport_position: Vector2) -> bool:
	if not _can_interact():
		return false
	var payload := HeldItemPayload.new(&"cup", StringName(name), 1, self, {
		"category": &"cup",
	})
	return controller.start_drag(payload, self, viewport_position)


func _can_interact() -> bool:
	if (not is_inside_tree() or is_queued_for_deletion()
		or not is_instance_valid(controller) or not controller.is_inside_tree() or controller.is_queued_for_deletion()
		or controller.current_mode != InteractionController.MODE_INTERACT
		or not controller.can_start_world_action()
		or controller.is_dragging() or controller.has_active_action()):
		return false
	var handle := get_node_or_null("PlacementHandle") as TablePlaceable
	return (handle != null and not handle.is_queued_for_deletion() and handle.controller == controller
		and is_instance_valid(handle.surface) and handle.surface.is_inside_tree()
		and not handle.surface.is_queued_for_deletion() and handle.surface.is_registered(self))


func _on_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var handle := get_node_or_null("PlacementHandle") as TablePlaceable
		if handle != null and handle._is_frontmost_at(event.position) and begin_interaction_drag(event.position):
			get_viewport().set_input_as_handled()


func _on_hover(entered: bool) -> void:
	_hovered = entered
	if _can_interact():
		get_node("/root/CursorService").set_state(&"hover_actionable" if entered else &"default")
		if entered:
			controller.report_hint("Use · drag cup to serve or discard · Organize to rearrange")


func _refresh_hover(_mode: StringName) -> void:
	if _hovered:
		_on_hover(true)


func _configure_in_screen() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("configure_cup"):
			if ancestor.is_node_ready() and not ancestor.is_queued_for_deletion():
				ancestor.call("configure_cup", self)
			return
		ancestor = ancestor.get_parent()

func is_status_hovered() -> bool:
	if not _hovered:
		return false
	if not is_instance_valid(controller):
		return true
	if controller.is_world_input_blocked() or controller.is_pointer_over_ui_at(get_viewport().get_mouse_position()):
		return false
	var handle := get_node_or_null("PlacementHandle") as TablePlaceable
	return handle != null and handle._is_frontmost_at(get_viewport().get_mouse_position())


func _update_volume_marker(_amount: float) -> void:
	if not is_node_ready():
		return
	# Live presentation belongs to the screen-space status layer.
	volume_marker.hide()
	volume_marker.text = ""


func set_state(next_state: CupState) -> bool:
	# Lifecycle commands are idempotent: repeating the current state succeeds
	# without emitting another transition signal.
	if state == next_state:
		return true
	var valid_targets: Array = ALLOWED_TRANSITIONS.get(state, [])
	if not valid_targets.has(next_state):
		return false

	var previous_state := state
	state = next_state
	_apply_state_visuals()
	state_changed.emit(previous_state, state)
	return true


func can_accept_relish(item_id: StringName) -> bool:
	if item_id.is_empty():
		return false
	return state == CupState.CLEAN or state == CupState.IN_USE or state == CupState.FILLED


func get_relish_count(item_id: StringName) -> int:
	return 0 if item_id.is_empty() else relish_item_ids.count(item_id)


func get_relish_counts() -> Dictionary[StringName, int]:
	# Each entry is one committed spoon. Keep the existing list authoritative;
	# callers receive a fresh count snapshot rather than a second mutable store.
	var counts: Dictionary[StringName, int] = {}
	for item_id in relish_item_ids:
		if not item_id.is_empty():
			counts[item_id] = counts.get(item_id, 0) + 1
	return counts


func get_ingredient_amounts() -> Dictionary[StringName, float]:
	var amounts := _inherited_ingredient_amounts.duplicate()
	for item_id in relish_item_ids:
		if not item_id.is_empty():
			amounts[item_id] = amounts.get(item_id, 0.0) + 1.0
	return amounts


func get_inherited_ingredient_amounts() -> Dictionary[StringName, float]:
	return _inherited_ingredient_amounts.duplicate()


func get_ingredient_stage() -> StringName:
	return [&"clean", &"in_use", &"filled", &"served", &"dirty"][state] if state >= 0 and state <= CupState.DIRTY else &"invalid"


func can_apply_ingredient(item_id: StringName, quantity: int, effect: StringName, output_liquid_id: StringName = &"") -> bool:
	# The selected policy owns lifecycle permission, including any deliberate
	# served/dirty exception. It cannot bypass physical contents validation.
	return (is_inside_tree() and not is_queued_for_deletion() and not item_id.is_empty()
		and quantity > 0 and effect == &"mix" and output_liquid_id.is_empty()
		and get_ingredient_stage() != &"invalid" and is_finite(volume_ml)
		and is_finite(capacity_ml) and is_finite(temperature) and capacity_ml > 0.0
		and volume_ml >= 0.0 and volume_ml <= capacity_ml)


func apply_ingredient(item_id: StringName, quantity: int, effect: StringName, output_liquid_id: StringName = &"", _restart_steeping := false) -> bool:
	if not can_apply_ingredient(item_id, quantity, effect, output_liquid_id):
		return false
	_remember_state_change()
	for index in range(quantity):
		relish_item_ids.append(item_id)
	if state == CupState.CLEAN:
		state = CupState.IN_USE
	notify_contents_changed(false)
	return true


func has_contents() -> bool:
	return volume_ml > 0.0 or not contents_base_id.is_empty() or not relish_item_ids.is_empty() or not _inherited_ingredient_amounts.is_empty()


func add_relish(item_id: StringName) -> bool:
	if not can_accept_relish(item_id):
		return false
	return apply_ingredient(item_id, 1, &"mix")


func mark_served() -> bool:
	return set_state(CupState.SERVED)


func mark_dirty() -> bool:
	return set_state(CupState.DIRTY)


func reset_clean() -> void:
	_remember_state_change()
	contents_base_id = &""
	volume_ml = 0.0
	liquid_type = &""
	temperature = config.ambient_temperature
	relish_item_ids.clear()
	_inherited_ingredient_amounts.clear()
	_brew_batches.clear()
	_brew_history_complete = true
	assigned_order_id = &""
	state = CupState.CLEAN
	notify_contents_changed()


func _apply_state_visuals() -> void:
	if not is_node_ready():
		return
	cup_sprite.texture = dirty_texture if state == CupState.DIRTY else clean_texture
	contents_overlay.texture = _water_contents_texture if liquid_type == &"water" and _water_contents_texture != null else _tea_contents_texture
	contents_overlay.visible = (state == CupState.FILLED or state == CupState.SERVED) and (volume_ml > 0.0 or not contents_base_id.is_empty())
