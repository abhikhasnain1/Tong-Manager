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

const MAX_RELISH_ITEMS := 3
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

func can_receive_liquid(kind: StringName) -> bool:
	return (
		not kind.is_empty() and state in [CupState.CLEAN, CupState.IN_USE, CupState.FILLED]
		and volume_ml < capacity_ml - 0.0001
		and (liquid_type.is_empty() or liquid_type == kind)
	)

func receive_liquid(kind: StringName, amount_ml: float, liquid_temperature: float = 20.0) -> float:
	if not is_finite(amount_ml) or not is_finite(liquid_temperature) or amount_ml <= 0.0 or not can_receive_liquid(kind):
		return 0.0
	var accepted := minf(amount_ml, maxf(0.0, capacity_ml - volume_ml))
	temperature = (temperature * volume_ml + liquid_temperature * accepted) / (volume_ml + accepted)
	volume_ml += accepted
	liquid_type = kind
	contents_base_id = kind
	set_state(CupState.FILLED)
	liquid_changed.emit(volume_ml)
	temperature_changed.emit(temperature)
	contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)
	return accepted

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
	# Notify any incoming transfer before clearing; disposal never washes a cup.
	var discarded := volume_ml
	contents_discarded.emit(discarded)
	var previous_state := state
	volume_ml = 0.0
	liquid_type = &""
	contents_base_id = &""
	relish_item_ids.clear()
	temperature = config.ambient_temperature
	if state == CupState.FILLED:
		state = CupState.IN_USE
	_apply_state_visuals()
	if previous_state != state:
		state_changed.emit(previous_state, state)
	liquid_changed.emit(volume_ml)
	temperature_changed.emit(temperature)
	contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)
	return discarded

@onready var cup_sprite: Sprite2D = $Sprite2D
@onready var contents_overlay: Sprite2D = $ContentsOverlay
@onready var volume_marker: Label = $VolumeMarker


func _ready() -> void:
	assert(clean_texture != null, "Cup requires a clean texture.")
	assert(dirty_texture != null, "Cup requires a dirty texture.")
	if volume_ml <= 0.0:
		temperature = config.ambient_temperature
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

func _update_volume_marker(amount: float) -> void:
	if not is_node_ready():
		return
	volume_marker.visible = amount > 0.0
	volume_marker.text = "%dml %d°C" % [roundi(amount), roundi(temperature)]


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
	if item_id.is_empty() or relish_item_ids.size() >= MAX_RELISH_ITEMS:
		return false
	return state == CupState.CLEAN or state == CupState.IN_USE or state == CupState.FILLED


func add_relish(item_id: StringName) -> bool:
	if not can_accept_relish(item_id):
		return false

	relish_item_ids.append(item_id)
	if state == CupState.CLEAN and not set_state(CupState.IN_USE):
		relish_item_ids.pop_back()
		return false
	contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)
	return true


func mark_served() -> bool:
	return set_state(CupState.SERVED)


func mark_dirty() -> bool:
	return set_state(CupState.DIRTY)


func reset_clean() -> void:
	var previous_state := state
	contents_base_id = &""
	volume_ml = 0.0
	liquid_type = &""
	temperature = config.ambient_temperature
	liquid_changed.emit(volume_ml)
	temperature_changed.emit(temperature)
	relish_item_ids.clear()
	assigned_order_id = &""
	state = CupState.CLEAN
	_apply_state_visuals()
	if previous_state != CupState.CLEAN:
		state_changed.emit(previous_state, state)
	contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)


func _apply_state_visuals() -> void:
	if not is_node_ready():
		return
	cup_sprite.texture = dirty_texture if state == CupState.DIRTY else clean_texture
	contents_overlay.visible = (state == CupState.FILLED or state == CupState.SERVED) and (volume_ml > 0.0 or not contents_base_id.is_empty())
