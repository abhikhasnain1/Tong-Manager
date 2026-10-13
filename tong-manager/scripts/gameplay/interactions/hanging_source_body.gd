class_name HangingSourceBody
extends Node2D

# The source remains attached. Only its body is simulated; serving a piece uses
# the shared portion lifecycle bound to input_area by the workstation.
class SwingBody extends RigidBody2D:
	var speed_limit := 2.4
	var angle_limit := deg_to_rad(13.0)
	var pendulum_length := 100.0

	func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
		var speed := clampf(state.angular_velocity, -speed_limit, speed_limit)
		# Pin constraints can yield under a burst of impulses. Limit the next
		# physical angular step too, without animating or teleporting the body.
		var angle := wrapf(state.transform.get_rotation(), -PI, PI)
		if state.step > 0.0:
			speed = clampf(speed, (-angle_limit - angle) / state.step, (angle_limit - angle) / state.step)
		speed = clampf(speed, -speed_limit, speed_limit)
		if not is_equal_approx(speed, state.angular_velocity):
			# Keep the constrained center-of-mass velocity consistent too. The
			# joint must not turn leftover tangential speed back into rotation.
			var offset := Vector2(0.0, pendulum_length).rotated(angle)
			state.linear_velocity = Vector2(-offset.y, offset.x) * speed
		state.angular_velocity = speed

@export_range(1.0, 30.0, 0.5) var swing_limit_degrees := 13.0
@export_range(0.1, 10.0, 0.1) var swing_damping := 2.5

const MAX_POINTER_SPEED := 1600.0
const BRUSH_GAIN := 200.0
const MAX_IMPULSE := 11000.0

var controller: InteractionController
var body: RigidBody2D
var pin_joint: PinJoint2D
var input_area: Area2D
var sprite: Sprite2D
var anchor: StaticBody2D
var impulse_count := 0
var last_impulse := 0.0
var _body_shape: RectangleShape2D
var _input_shape: RectangleShape2D
var _input_collision: CollisionShape2D
var _texture: Texture2D
var _region := Rect2()
var _art_scale := 1.0
var _texture_pivot := Vector2.ZERO
var _layout := Transform2D.IDENTITY
var _configured := false
var _last_motion_usec := 0
var _world_scale := 1.0
var _rest_body_position := Vector2.ZERO

func _init() -> void:
	anchor = StaticBody2D.new()
	anchor.name = "FixedAnchor"
	anchor.top_level = true
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	add_child(anchor)
	body = SwingBody.new()
	body.name = "SwingBody"
	body.top_level = true
	body.z_as_relative = false
	body.collision_layer = 0
	body.collision_mask = 0
	body.input_pickable = false
	body.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	body.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.linear_damp = 0.5
	add_child(body)
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.region_enabled = true
	body.add_child(sprite)
	_body_shape = RectangleShape2D.new()
	var physical_shape := CollisionShape2D.new()
	physical_shape.name = "BodyShape"
	physical_shape.shape = _body_shape
	body.add_child(physical_shape)
	input_area = Area2D.new()
	input_area.name = "InputArea"
	input_area.collision_layer = 1
	input_area.collision_mask = 0
	input_area.monitoring = false
	input_area.monitorable = false
	body.add_child(input_area)
	_input_shape = RectangleShape2D.new()
	_input_collision = CollisionShape2D.new()
	_input_collision.name = "InputShape"
	_input_collision.shape = _input_shape
	input_area.add_child(_input_collision)
	pin_joint = PinJoint2D.new()
	pin_joint.name = "PinJoint"
	pin_joint.top_level = true
	pin_joint.angular_limit_enabled = true
	pin_joint.disable_collision = true
	add_child(pin_joint)

func _ready() -> void:
	add_to_group(&"hanging_sources")
	if _configured:
		sync_layout()

# Position this node at the original full texture's authored center. Region and
# pivot are in the original texture's pixel coordinates, including for crops.
func configure(interaction: InteractionController, texture: Texture2D, region: Rect2, authored_scale: float, texture_pivot: Vector2) -> void:
	assert(texture != null and region.size.x > 0.0 and region.size.y > 0.0 and authored_scale > 0.0)
	controller = interaction
	_texture = texture
	_region = region
	_art_scale = authored_scale
	_texture_pivot = texture_pivot
	sprite.texture = texture
	sprite.region_rect = region
	_configured = true
	if is_inside_tree():
		sync_layout()

func sync_layout() -> void:
	if not _configured or not is_inside_tree():
		return
	_layout = global_transform
	_world_scale = absf(_layout.get_scale().x)
	var scale_factor := _art_scale * _world_scale
	var full_center := _texture.get_size() * 0.5
	var pivot_position := _layout * ((_texture_pivot - full_center) * _art_scale)
	_rest_body_position = _layout * ((_region.get_center() - full_center) * _art_scale)
	# Physics bodies stay unscaled. Resize their unique shape resources and the
	# child artwork instead, then recreate the joint at its new world anchor.
	pin_joint.node_b = NodePath()
	body.freeze = true
	anchor.global_transform = Transform2D(0.0, pivot_position)
	pin_joint.global_transform = Transform2D(0.0, pivot_position)
	_body_shape.size = _region.size * scale_factor
	_input_shape.size = _body_shape.size
	sprite.scale = Vector2.ONE * scale_factor
	body.global_transform = Transform2D(0.0, _rest_body_position)
	body.z_index = _authored_z_index()
	body.center_of_mass = Vector2(pivot_position.x - _rest_body_position.x, 0.0)
	body.gravity_scale = _world_scale
	body.angular_damp = swing_damping
	(body as SwingBody).angle_limit = deg_to_rad(swing_limit_degrees)
	(body as SwingBody).pendulum_length = _rest_body_position.y - pivot_position.y
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	pin_joint.node_a = pin_joint.get_path_to(anchor)
	pin_joint.node_b = pin_joint.get_path_to(body)
	body.freeze = false
	pin_joint.angular_limit_lower = -deg_to_rad(swing_limit_degrees)
	pin_joint.angular_limit_upper = deg_to_rad(swing_limit_degrees)
	pin_joint.angular_limit_enabled = false
	pin_joint.angular_limit_enabled = true
	body.sleeping = false
	body.reset_physics_interpolation()
	_last_motion_usec = 0

func reset_sway() -> void:
	sync_layout()

func _physics_process(_delta: float) -> void:
	if _configured and not global_transform.is_equal_approx(_layout):
		sync_layout()
	if is_instance_valid(body):
		body.z_index = _authored_z_index()

func _authored_z_index() -> int:
	var result := 0
	var ancestor: CanvasItem = self
	while ancestor != null:
		result += ancestor.z_index
		if not ancestor.z_as_relative or ancestor.is_set_as_top_level():
			break
		ancestor = ancestor.get_parent() as CanvasItem
	return clampi(result, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var now := Time.get_ticks_usec()
	var elapsed := clampf(float(now - _last_motion_usec) / 1000000.0, 1.0 / 240.0, 1.0 / 15.0) if _last_motion_usec != 0 else 1.0 / 60.0
	_last_motion_usec = now
	if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		return
	brush_pointer(event.position, event.relative, elapsed)

func can_brush() -> bool:
	return (_configured and is_inside_tree() and not is_queued_for_deletion() and is_visible_in_tree()
		and is_instance_valid(controller) and controller.is_inside_tree() and not controller.is_queued_for_deletion()
		and not controller.is_world_input_blocked() and not controller.is_pointer_over_ui()
		and not controller.is_dragging() and not controller.has_active_action()
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

# One input motion produces at most one impulse. The pendulum moving beneath a
# stationary pointer cannot inject more energy; UI blocks only new brushing.
func brush_pointer(viewport_position: Vector2, motion: Vector2, elapsed: float) -> bool:
	if not can_brush() or motion.is_zero_approx() or elapsed <= 0.0:
		return false
	var hit := _motion_hit(viewport_position, motion)
	if not hit.is_finite():
		return false
	var viewport_scale := maxf(absf(get_global_transform_with_canvas().get_scale().x), 0.001)
	var authored_motion := motion / viewport_scale
	var capped_motion := authored_motion.limit_length(MAX_POINTER_SPEED * minf(elapsed, 0.1))
	var anchor_viewport := anchor.get_global_transform_with_canvas().origin
	var lever := hit - anchor_viewport
	if lever.length_squared() < 1.0:
		return false
	var tangential_motion := lever.normalized().cross(capped_motion)
	var impulse := clampf(tangential_motion * BRUSH_GAIN, -MAX_IMPULSE, MAX_IMPULSE) * _world_scale * _world_scale
	if is_zero_approx(impulse):
		return false
	body.sleeping = false
	body.apply_torque_impulse(impulse)
	last_impulse = impulse
	impulse_count += 1
	return true

func _motion_hit(point: Vector2, motion: Vector2) -> Vector2:
	var steps := clampi(int(ceil(motion.length() / 10.0)), 1, 64)
	for step in range(steps + 1):
		var candidate := point - motion * (float(step) / float(steps))
		if not contains_pointer(candidate) or not is_frontmost_at(candidate):
			continue
		if controller.is_pointer_over_ui_at(candidate):
			continue
		return candidate
	return Vector2(INF, INF)

func contains_pointer(viewport_position: Vector2) -> bool:
	if (not _configured or not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree()
		or not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion() or not body.is_visible_in_tree()
		or not is_instance_valid(sprite) or not sprite.is_inside_tree() or not sprite.is_visible_in_tree()
		or not is_instance_valid(input_area) or not input_area.is_inside_tree() or not input_area.is_visible_in_tree() or not input_area.input_pickable
		or not is_instance_valid(_input_collision) or _input_collision.disabled):
		return false
	var local := sprite.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return sprite.get_rect().has_point(local) and sprite.is_pixel_opaque(local)

func is_frontmost_at(viewport_position: Vector2) -> bool:
	if not contains_pointer(viewport_position):
		return false
	for node in get_tree().get_nodes_in_group(&"hanging_sources"):
		var other := node as HangingSourceBody
		if other == self or other.controller != controller or not other.contains_pointer(viewport_position):
			continue
		# Top-level physics bodies render outside the rail's Y sort. Their
		# explicit layer and tree order are also the extraction/brush order.
		if other.body.z_index > body.z_index or (other.body.z_index == body.z_index and other.body.is_greater_than(body)):
			return false
	return true
