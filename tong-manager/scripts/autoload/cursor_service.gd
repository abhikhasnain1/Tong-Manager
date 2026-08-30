extends Node

signal state_changed(state: StringName)

const STATE_DEFAULT := &"default"
const STATE_HOVER_INTERACTABLE := &"hover_interactable"
const STATE_HOVER_ACTIONABLE := &"hover_actionable"
const STATE_DRAGGING := &"dragging"
const STATE_INVALID := &"invalid"

const CURSOR_NORMAL: Texture2D = preload("res://assets/art/cursors/cursor_normal.png")
const CURSOR_HOVER: Texture2D = preload("res://assets/art/cursors/cursor_hover.png")
const CURSOR_GRABBABLE: Texture2D = preload("res://assets/art/cursors/cursor_grabbable.png")
const CURSOR_GRABBED: Texture2D = preload("res://assets/art/cursors/cursor_grabbed.png")

const STATE_TO_SYSTEM_SHAPE := {
	STATE_DEFAULT: Input.CURSOR_ARROW,
	STATE_HOVER_INTERACTABLE: Input.CURSOR_POINTING_HAND,
	STATE_HOVER_ACTIONABLE: Input.CURSOR_CROSS,
	STATE_DRAGGING: Input.CURSOR_DRAG,
	STATE_INVALID: Input.CURSOR_FORBIDDEN,
}

const STATE_TO_CUSTOM_CURSOR := {
	STATE_DEFAULT: {
		"texture": CURSOR_NORMAL,
		"hotspot": Vector2(14.0, 7.0),
	},
	STATE_HOVER_INTERACTABLE: {
		"texture": CURSOR_HOVER,
		"hotspot": Vector2(12.0, 9.0),
	},
	STATE_HOVER_ACTIONABLE: {
		"texture": CURSOR_GRABBABLE,
		"hotspot": Vector2(32.0, 32.0),
	},
	STATE_DRAGGING: {
		"texture": CURSOR_GRABBED,
		"hotspot": Vector2(32.0, 32.0),
	},
}

var current_state: StringName = STATE_DEFAULT
var _bound_hover_states: Dictionary = {}


func _ready() -> void:
	_install_custom_cursors()
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


func _install_custom_cursors() -> void:
	for state: StringName in STATE_TO_CUSTOM_CURSOR:
		var cursor_data: Dictionary = STATE_TO_CUSTOM_CURSOR[state]
		Input.set_custom_mouse_cursor(
			cursor_data["texture"],
			STATE_TO_SYSTEM_SHAPE[state],
			cursor_data["hotspot"]
		)


func _exit_tree() -> void:
	for state: StringName in STATE_TO_CUSTOM_CURSOR:
		Input.set_custom_mouse_cursor(null, STATE_TO_SYSTEM_SHAPE[state])
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
