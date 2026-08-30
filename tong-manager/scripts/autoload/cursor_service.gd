extends Node

signal state_changed(state: StringName)

const STATE_DEFAULT := &"default"
const STATE_HOVER_INTERACTABLE := &"hover_interactable"
const STATE_HOVER_ACTIONABLE := &"hover_actionable"
const STATE_DRAGGING := &"dragging"
const STATE_INVALID := &"invalid"

const STATE_TO_SYSTEM_SHAPE := {
	STATE_DEFAULT: Input.CURSOR_ARROW,
	STATE_HOVER_INTERACTABLE: Input.CURSOR_POINTING_HAND,
	STATE_HOVER_ACTIONABLE: Input.CURSOR_CROSS,
	STATE_DRAGGING: Input.CURSOR_DRAG,
	STATE_INVALID: Input.CURSOR_FORBIDDEN,
}

var current_state: StringName = STATE_DEFAULT
var _bound_hover_states: Dictionary = {}


func _ready() -> void:
	reset()


func set_state(state: StringName) -> void:
	assert(STATE_TO_SYSTEM_SHAPE.has(state), "Unsupported cursor state: %s" % state)
	Input.set_default_cursor_shape(STATE_TO_SYSTEM_SHAPE[state])
	if current_state == state:
		return
	current_state = state
	state_changed.emit(current_state)


func reset() -> void:
	set_state(STATE_DEFAULT)


func modal_closed() -> void:
	reset()


func bind_hover_target(
	target: CollisionObject2D,
	hover_state: StringName = STATE_HOVER_INTERACTABLE
) -> void:
	assert(target != null, "CursorService cannot bind a missing hover target.")
	assert(
		hover_state == STATE_HOVER_INTERACTABLE or hover_state == STATE_HOVER_ACTIONABLE,
		"Hover targets require a hover cursor state."
	)
	var target_id := target.get_instance_id()
	if _bound_hover_states.has(target_id):
		return
	_bound_hover_states[target_id] = hover_state
	target.mouse_entered.connect(_on_bound_hover_entered.bind(target_id))
	target.mouse_exited.connect(_on_bound_hover_exited.bind(target_id))
	target.tree_exited.connect(_on_bound_hover_tree_exited.bind(target_id))


func _on_bound_hover_entered(target_id: int) -> void:
	if not _bound_hover_states.has(target_id):
		return
	if current_state == STATE_DEFAULT or current_state == STATE_HOVER_INTERACTABLE or current_state == STATE_HOVER_ACTIONABLE:
		set_state(_bound_hover_states[target_id])


func _on_bound_hover_exited(target_id: int) -> void:
	if _bound_hover_states.has(target_id) and current_state == _bound_hover_states[target_id]:
		reset()


func _on_bound_hover_tree_exited(target_id: int) -> void:
	if not _bound_hover_states.has(target_id):
		return
	var removed_state: StringName = _bound_hover_states[target_id]
	_bound_hover_states.erase(target_id)
	if current_state == removed_state:
		reset()


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
