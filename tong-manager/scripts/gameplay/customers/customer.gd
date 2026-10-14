class_name Customer
extends Node2D
## Reusable presentation of supplied customer/order/result data; no handoff evaluator.

signal state_changed(state: State)
signal departure_finished
signal service_result_presented(snapshot: Dictionary)

enum State { ARRIVING, WAITING, ORDERING, SERVED, LEAVING }

const BODY_SHADER := preload("res://scripts/gameplay/customers/customer_body.gdshader")
const MALE_TURN := preload("res://assets/art/customers/customer_male_turnaway_provisional.png")
const FEMALE_TURN := preload("res://assets/art/customers/customer_female_turnaway_provisional.png")
const CUP_ICON := preload("res://assets/art/toolkit/cup_clean_provisional.png")
const MALE_REGIONS: Array[Rect2] = [Rect2(147, 7, 315, 492), Rect2(674, 9, 201, 490), Rect2(1110, 11, 269, 489), Rect2(132, 515, 340, 488)]
const FEMALE_REGIONS: Array[Rect2] = [Rect2(153, 13, 340, 476), Rect2(620, 14, 270, 476), Rect2(1068, 15, 323, 475), Rect2(136, 523, 338, 478)]

@export var customer_def: CustomerDef
@export var auto_arrive := false
@export var presentation: CustomerPresentation = CustomerPresentation.new()
@export var dialogue_enabled := false
@export var reduced_motion := false:
	set(value):
		reduced_motion = value
		if value and _moving and _initialized: _finish_motion()

var state: State:
	get: return _state
	set(_value): pass
var order: OrderState:
	get: return _order
	set(_value): pass

var _state := State.WAITING
var _order: OrderState
var _definition_id: StringName
var _presented_ids: Dictionary = {}
var _accepted: Dictionary = {}
var _emotion: StringName
var _review_reason: StringName
var _review_count := 0
var _dialogue := ""
var _feedback_text := "Waiting for an order"
var _front_image: Image
var _turn_image: Image
var _front_texture: Texture2D
var _turn_sheet: Texture2D
var _regions: Array[Rect2] = []
var _material: ShaderMaterial
var _settings: CustomerPresentation
var _initialized := false
var _moving := false
var _leaving := false
var _elapsed := 0.0
var _duration := 1.15
var _turn_duration := 0.0
var _turn_progress := 0.0
var _turn_frame := -1
var _travel_progress := 0.0
var _generation := 0
var _highlighted := false
var _pose_from := -1
var _pose_to := -1
var _pose_amount := 0.0

@onready var visual_root: Node2D = $VisualRoot
@onready var bob_root: Node2D = $VisualRoot/BobRoot
@onready var body_sprite: Sprite2D = $VisualRoot/BobRoot/BodySprite
@onready var emotion_icon: CustomerFeedback = $VisualRoot/BobRoot/EmotionIcon
@onready var bubble_anchor: Marker2D = $VisualRoot/BobRoot/BubbleAnchor
@onready var dialogue_panel: Panel = $VisualRoot/BobRoot/BubbleAnchor/Dialogue
@onready var dialogue_label: Label = $VisualRoot/BobRoot/BubbleAnchor/Dialogue/Text
@onready var serve_zone: Area2D = $ServeZone
@onready var serve_shape: CollisionShape2D = $ServeZone/CollisionShape2D


func _ready() -> void:
	_initialized = true
	visibility_changed.connect(_on_visibility_changed)
	_settings = presentation if presentation != null else CustomerPresentation.new()
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	body_sprite.texture = ImageTexture.create_from_image(image)
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	body_sprite.material = _material
	_apply_definition()
	_reset_visuals()
	_refresh_feedback()
	_refresh_target()
	if auto_arrive: arrive()


func _enter_tree() -> void:
	if _initialized: _restore_after_enter.call_deferred()


func _restore_after_enter() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	_reset_visuals()
	_refresh_feedback()
	_refresh_target()


func _exit_tree() -> void:
	_cancel_motion()
	if _initialized:
		_reset_visuals()
		_state = _resting_state() if visible else State.LEAVING
		serve_zone.input_pickable = false
		serve_shape.set_deferred("disabled", true)


func _process(delta: float) -> void:
	if not _moving or not is_finite(delta) or delta <= 0.0: return
	_elapsed = minf(_duration, _elapsed + delta)
	_update_motion()
	if _elapsed >= _duration: _finish_motion()


func set_customer_def(value: CustomerDef) -> void:
	_cancel_motion()
	var identity: StringName = value.id if value != null else &""
	if value != customer_def or identity != _definition_id:
		_order = null
		_clear_result_history()
	customer_def = value
	_definition_id = identity
	if not _initialized: return
	_apply_definition()
	reset_presentation()


func set_order(value: OrderState) -> bool:
	if value != null and (customer_def == null or value.customer_id != customer_def.id or value.get_snapshot().is_empty()):
		return false
	var replacing := value != _order and (_order != null or _state == State.LEAVING)
	if value != null and _order != null and value.order_id == _order.order_id:
		if value != _order: return false
	else:
		_clear_result_history()
	if value != _order: _generation += 1
	_order = value
	if _initialized:
		if replacing:
			_cancel_motion()
			_reset_visuals()
			var epoch := _generation
			show()
			if not _live() or epoch != _generation: return false
		_refresh_feedback()
		_refresh_target()
		if not _moving: _set_state(_resting_state())
	else:
		_state = _resting_state()
	return true


func arrive() -> void:
	if not _live() or _front_texture == null: return
	_start_motion(false)


func leave() -> void:
	if not _live() or not is_visible_in_tree() or _front_texture == null: return
	_start_motion(true)


func prepare_timeout_departure() -> bool:
	if not _live() or not is_visible_in_tree() or _moving or _state not in [State.WAITING, State.ORDERING] or (_order != null and _order.fulfilled):
		return false
	_emotion = &"unhappy"
	_feedback_text = "Waited too long"
	_refresh_feedback()
	var epoch := _generation
	_set_state(State.LEAVING)
	return _live() and epoch == _generation and _state == State.LEAVING


func reset_presentation() -> void:
	_cancel_motion()
	if not _initialized: return
	var epoch := _generation
	show()
	if not _live() or epoch != _generation: return
	_reset_visuals()
	_refresh_feedback()
	_refresh_target()
	_set_state(_resting_state())


func show_emotion(value: StringName) -> void:
	if value not in [&"", &"neutral", &"happy", &"unhappy", &"cold", &"wrong"]: return
	_emotion = &"" if value == &"neutral" else value
	if _initialized: _refresh_feedback()


func set_dialogue(value: String) -> void:
	_dialogue = value
	if _initialized: _refresh_dialogue()


func show_dialogue(enabled: bool) -> void:
	dialogue_enabled = enabled
	if _initialized: _refresh_dialogue()


func apply_service_result(result: ServiceResult) -> bool:
	if not _live() or not is_visible_in_tree() or _moving or _state not in [State.WAITING, State.ORDERING, State.SERVED] or _order == null or result == null or not _accepted.is_empty():
		return false
	var data := result.get_snapshot()
	if data.is_empty() or data.order_id != _order.order_id or data.customer_id != _definition_id or data.request_kind != _order.request_kind:
		return false
	if _presented_ids.has(data.handoff_id): return false
	if _order.fulfilled and _order.get_accepted_result() != data: return false
	var recorded := _order.get_result(data.handoff_id)
	if recorded.is_empty():
		if not _order.record_result(result): return false
	elif recorded != data:
		return false
	_presented_ids[data.handoff_id] = true
	if data.accepted:
		_accepted = data.duplicate(true)
		_emotion = &"cold" if data.bad_review else &"happy"
		_review_reason = data.reason
		if data.bad_review: _review_count += 1
		_feedback_text = "Cold tea accepted · unhappy · bad review" if data.bad_review else "Order accepted · happy"
	else:
		_emotion = &"wrong"
		_feedback_text = "Wrong item · still waiting · no review"
	_refresh_feedback()
	var epoch := _generation
	_set_state(State.SERVED if data.accepted else State.ORDERING)
	if _live() and epoch == _generation:
		service_result_presented.emit(data.duplicate(true))
	return true


func is_serve_enabled() -> bool:
	return (_live() and is_visible_in_tree() and not _moving and _front_texture != null
		and _state in [State.WAITING, State.ORDERING] and _order != null
		and not _order.fulfilled and _accepted.is_empty())


func contains_serve_point(global_point: Vector2) -> bool:
	return is_serve_enabled() and contains_visual_point(global_point)


func contains_visual_point(global_point: Vector2) -> bool:
	if not _live() or not is_visible_in_tree() or not body_sprite.visible or not global_point.is_finite() or _front_image == null: return false
	var transform := bob_root.global_transform
	if not transform.is_finite() or is_zero_approx(transform.determinant()): return false
	var point := bob_root.to_local(global_point)
	var canvas := _settings.safe_canvas_size()
	if not Rect2(Vector2(-canvas.x * 0.5, -canvas.y), canvas).has_point(point): return false
	var alpha := lerpf(_sample_pose_alpha(point, _pose_from), _sample_pose_alpha(point, _pose_to), _pose_amount)
	return alpha * visual_root.modulate.a * modulate.a > 0.08


func _sample_pose_alpha(point: Vector2, frame: int) -> float:
	var image: Image = _front_image if frame < 0 else _turn_image
	if image == null: return 0.0
	var region := Rect2(Vector2.ZERO, image.get_size()) if frame < 0 else _regions[frame]
	var factor := _settings.safe_canvas_size().y / region.size.y
	var pixel := Vector2(point.x / factor + region.size.x * 0.5, (point.y + _settings.safe_canvas_size().y) / factor)
	if not Rect2(Vector2.ZERO, region.size).has_point(pixel): return 0.0
	return image.get_pixelv(Vector2i(pixel + region.position)).a


func get_front_texture() -> Texture2D:
	return _front_texture if _initialized else (customer_def.sprite_texture if customer_def != null else null)


func get_front_rect() -> Rect2:
	var texture := get_front_texture()
	if texture == null: return Rect2()
	var height := _settings.safe_canvas_size().y if _settings != null else 360.0
	var size := texture.get_size() * (height / maxf(1.0, texture.get_height()))
	return Rect2(Vector2(-size.x * 0.5, -height), size)


func get_serve_bounds() -> Rect2:
	if not _initialized: return Rect2()
	var rect := get_front_rect()
	var corners := [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)]
	var result := Rect2(bob_root.to_global(corners[0]), Vector2.ZERO)
	for point: Vector2 in corners: result = result.expand(bob_root.to_global(point))
	return result


func set_drop_highlight(enabled: bool) -> void:
	_highlighted = enabled and is_serve_enabled()
	if _material != null:
		_material.set_shader_parameter("outline_width", _settings.outline_width if _highlighted else 0.0)


func get_presentation_text() -> String:
	return _feedback_text


func get_presentation_snapshot() -> Dictionary:
	return {
		"state": _state, "customer_id": _definition_id, "order_id": _order.order_id if _order != null else &"",
		"emotion": _emotion, "review_reason": _review_reason, "review_count": _review_count,
		"moving": _moving, "turn_progress": _turn_progress, "turn_frame": _turn_frame,
		"travel_progress": _travel_progress, "motion_elapsed": _elapsed, "serve_enabled": is_serve_enabled(),
		"depth_offset": visual_root.position if _initialized else Vector2.ZERO,
		"depth_scale": visual_root.scale if _initialized else Vector2.ONE,
		"bob_offset": bob_root.position if _initialized else Vector2.ZERO,
		"text": _feedback_text, "highlighted": _highlighted,
	}


func _live() -> bool:
	return _initialized and is_inside_tree() and not is_queued_for_deletion()


func _clear_result_history() -> void:
	_presented_ids.clear()
	_accepted.clear()
	_emotion = &""
	_review_reason = &""
	_review_count = 0
	_feedback_text = "Waiting for an order"


func _resting_state() -> State:
	if _order == null: return State.WAITING
	return State.SERVED if _order.fulfilled or not _accepted.is_empty() else State.ORDERING


func _set_state(value: State) -> void:
	var changed := _state != value
	_state = value
	_refresh_target()
	if changed and _live(): state_changed.emit(_state)


func _cancel_motion() -> void:
	_generation += 1
	_moving = false
	_elapsed = 0.0
	set_drop_highlight(false)


func _start_motion(leaving: bool) -> void:
	_cancel_motion()
	var epoch := _generation
	show()
	if not _live() or epoch != _generation: return
	_reset_visuals()
	_moving = true
	_leaving = leaving
	_duration = _settings.safe_duration()
	_turn_duration = minf(maxf(0.0, _settings.turn_max_seconds), _duration * clampf(_settings.turn_fraction, 0.0, 0.8)) if leaving and _regions.size() >= 4 else 0.0
	_update_motion()
	_refresh_feedback()
	_set_state(State.LEAVING if leaving else State.ARRIVING)
	if epoch == _generation and reduced_motion: _finish_motion()


func _update_motion() -> void:
	var walking := clampf((_elapsed - _turn_duration) / maxf(0.0001, _duration - _turn_duration), 0.0, 1.0) if _leaving else clampf(_elapsed / _duration, 0.0, 1.0)
	_travel_progress = walking
	if _leaving:
		_turn_progress = clampf(_elapsed / _turn_duration, 0.0, 1.0) if _turn_duration > 0.0 else 1.0
		_blend_turn(_turn_progress)
	var distance := _ease(walking) if _leaving else 1.0 - _ease(walking)
	var size := _settings.safe_canvas_size()
	visual_root.position = Vector2(0.0, -size.y * _settings.travel_distance_ratio * distance)
	visual_root.scale = Vector2.ONE * lerpf(1.0, clampf(_settings.far_scale, 0.1, 1.0), distance)
	visual_root.modulate.a = 1.0 - distance
	var bob := sin(PI * float(maxi(0, _settings.bob_cycles)) * walking)
	bob_root.position = Vector2(0.0, -maxf(0.0, _settings.bob_height_ratio) * size.y * bob * bob)


func _finish_motion() -> void:
	if not _moving: return
	var leaving := _leaving
	var epoch := _generation
	_moving = false
	_elapsed = _duration
	_reset_visuals()
	if leaving:
		_state = State.LEAVING
		hide()
		if not _live() or epoch != _generation: return
		_refresh_target()
		if _live() and epoch == _generation: departure_finished.emit()
	else:
		_refresh_feedback()
		_set_state(_resting_state())


func _reset_visuals() -> void:
	if not _initialized: return
	visual_root.position = Vector2.ZERO
	visual_root.scale = Vector2.ONE
	visual_root.modulate = Color.WHITE
	bob_root.position = Vector2.ZERO
	_turn_progress = 0.0
	_turn_frame = -1
	_travel_progress = 0.0
	if _material != null: _set_pose(-1, -1, 0.0)


static func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _blend_turn(progress: float) -> void:
	if _regions.size() < 4: return
	if progress >= 1.0:
		_turn_frame = 3
		_set_pose(3, 3, 0.0)
		return
	var position := _ease(progress) * 4.0
	var segment := int(floor(position))
	var amount := position - float(segment)
	_turn_frame = segment - 1 if amount < 0.5 else segment
	_set_pose(segment - 1, segment, amount)


func _set_pose(from: int, to: int, amount: float) -> void:
	_pose_from = from
	_pose_to = to
	_pose_amount = amount
	_material.set_shader_parameter("from_front", from < 0)
	_material.set_shader_parameter("to_front", to < 0)
	_material.set_shader_parameter("pose_mix", amount)
	if from >= 0:
		var rect := _regions[from]
		_material.set_shader_parameter("from_region", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	if to >= 0:
		var rect := _regions[to]
		_material.set_shader_parameter("to_region", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


func _apply_definition() -> void:
	_definition_id = customer_def.id if customer_def != null else &""
	_front_texture = customer_def.sprite_texture if customer_def != null else null
	_front_image = _front_texture.get_image() if _front_texture != null else null
	if _front_image != null and _front_image.is_compressed(): _front_image.decompress()
	var size := _settings.safe_canvas_size()
	body_sprite.scale = size
	body_sprite.position = Vector2(0.0, -size.y * 0.5)
	body_sprite.visible = _front_texture != null
	_material.set_shader_parameter("canvas_size", size)
	_material.set_shader_parameter("outline_color", _settings.outline_color)
	if _front_texture != null:
		_material.set_shader_parameter("front_art", _front_texture)
		_material.set_shader_parameter("front_size", _front_texture.get_size())
	_select_turn_art()
	var shape := RectangleShape2D.new()
	shape.size = get_front_rect().size.max(Vector2.ONE)
	serve_shape.shape = shape
	serve_shape.position = get_front_rect().get_center()
	emotion_icon.position = _settings.bubble_position
	bubble_anchor.position = _settings.dialogue_position


func _select_turn_art() -> void:
	_regions.clear()
	_turn_image = null
	_turn_sheet = _settings.turn_sheet
	if _turn_sheet != null:
		for rect in _settings.turn_regions:
			if rect.size.x <= 0.0 or rect.size.y <= 0.0 or not Rect2(Vector2.ZERO, _turn_sheet.get_size()).encloses(rect):
				_regions.clear()
				return
			_regions.append(rect)
	elif _front_texture != null:
		if _front_texture.resource_path.ends_with("customer_male_provisional.png"):
			_turn_sheet = MALE_TURN
			_regions.assign(MALE_REGIONS)
		elif _front_texture.resource_path.ends_with("customer_female_provisional.png"):
			_turn_sheet = FEMALE_TURN
			_regions.assign(FEMALE_REGIONS)
	if _regions.size() < 4: _regions.clear()
	if _turn_sheet != null:
		_turn_image = _turn_sheet.get_image()
		if _turn_image != null and _turn_image.is_compressed(): _turn_image.decompress()
		_material.set_shader_parameter("turn_art", _turn_sheet)
		_material.set_shader_parameter("sheet_size", _turn_sheet.get_size())


func _refresh_target() -> void:
	if not _initialized: return
	var enabled := is_serve_enabled()
	serve_zone.input_pickable = enabled
	serve_shape.set_deferred("disabled", not enabled)
	if not enabled: set_drop_highlight(false)


func _refresh_feedback() -> void:
	if not _initialized: return
	var icon: Texture2D
	var ready_item := false
	if _order != null:
		var request := _order.get_request()
		ready_item = _order.request_kind == &"ready_item"
		icon = request.get("icon") as Texture2D if ready_item else CUP_ICON
	emotion_icon.configure(_settings.bubble_size, _emotion, icon, ready_item)
	emotion_icon.visible = not _moving and (_order != null or not _emotion.is_empty())
	_refresh_dialogue()


func _refresh_dialogue() -> void:
	if not _initialized: return
	var text := _dialogue
	if text.is_empty() and _order != null:
		text = "One tea, please." if _order.request_kind == &"tea" else ("A banana, please." if _order.item_id == &"banana" else "A biscuit, please.")
	if not _emotion.is_empty(): text = _feedback_text
	dialogue_panel.visible = dialogue_enabled and not _moving and not text.is_empty()
	dialogue_label.text = text
	var font := _settings.font if _settings.font != null else ThemeDB.fallback_font
	dialogue_label.add_theme_font_override("font", font)
	dialogue_label.add_theme_font_size_override("font_size", _settings.dialogue_font_size)
	dialogue_label.add_theme_color_override("font_color", Color("51412d"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dcf0c7") if _order != null and _order.request_kind == &"ready_item" else Color("ffe9bd")
	style.border_color = Color("ac966e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0; style.content_margin_right = 10.0
	style.content_margin_top = 6.0; style.content_margin_bottom = 6.0
	dialogue_panel.add_theme_stylebox_override("panel", style)
	var width := minf(_settings.safe_canvas_size().x - 12.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _settings.dialogue_font_size).x + 24.0)
	width = maxf(44.0, width)
	var text_width := width - 20.0
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, text_width, _settings.dialogue_font_size)
	dialogue_label.custom_minimum_size = Vector2(text_width, 0.0)
	dialogue_label.position = Vector2(10.0, 6.0)
	dialogue_label.size = Vector2(text_width, text_size.y)
	dialogue_panel.custom_minimum_size = Vector2.ZERO
	dialogue_panel.size = Vector2(width, text_size.y + 12.0)
	dialogue_panel.position = Vector2(-dialogue_panel.size.x * 0.5, 0.0)


func _on_visibility_changed() -> void:
	if not _initialized: return
	if not is_visible_in_tree():
		if _moving:
			_cancel_motion()
			_reset_visuals()
			_state = _resting_state()
		set_drop_highlight(false)
	_refresh_target()
