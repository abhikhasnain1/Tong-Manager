class_name Cup
extends Area2D

signal state_changed(previous_state: CupState, current_state: CupState)
signal liquid_changed(volume_ml: float)
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
var volume_ml := 0.0
var liquid_type: StringName = &""

func can_receive_liquid(kind: StringName) -> bool:
	return (
		not kind.is_empty() and state in [CupState.CLEAN, CupState.IN_USE, CupState.FILLED]
		and volume_ml < capacity_ml - 0.0001
		and (liquid_type.is_empty() or liquid_type == kind)
	)

func receive_liquid(kind: StringName, amount_ml: float) -> float:
	if not is_finite(amount_ml) or amount_ml <= 0.0 or not can_receive_liquid(kind):
		return 0.0
	var accepted := minf(amount_ml, maxf(0.0, capacity_ml - volume_ml))
	volume_ml += accepted
	liquid_type = kind
	contents_base_id = kind
	set_state(CupState.FILLED)
	liquid_changed.emit(volume_ml)
	contents_changed.emit(contents_base_id, relish_item_ids.duplicate(), assigned_order_id)
	return accepted

@onready var cup_sprite: Sprite2D = $Sprite2D
@onready var contents_overlay: Sprite2D = $ContentsOverlay
@onready var volume_marker: Label = $VolumeMarker


func _ready() -> void:
	assert(clean_texture != null, "Cup requires a clean texture.")
	assert(dirty_texture != null, "Cup requires a dirty texture.")
	liquid_changed.connect(_update_volume_marker)
	_update_volume_marker(volume_ml)
	_apply_state_visuals()

func _update_volume_marker(amount: float) -> void:
	volume_marker.visible = amount > 0.0
	volume_marker.text = "%d ml" % roundi(amount)


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
	liquid_changed.emit(volume_ml)
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
	contents_overlay.visible = state == CupState.FILLED or state == CupState.SERVED
