extends SceneTree

const RigScript = preload("res://scripts/gameplay/interactions/hanging_source_body.gd")

class TestController extends InteractionController:
	var ui_covered := false
	var covered_regions: Array[Rect2] = []

	func is_pointer_over_ui() -> bool:
		return ui_covered

	func is_pointer_over_ui_at(viewport_position: Vector2) -> bool:
		for region in covered_regions:
			if region.has_point(viewport_position):
				return true
		return ui_covered

var checks := 0
var failures: Array[String] = []
var fixture: Node2D
var world: Node2D
var controller: TestController
var rigs: Array[HangingSourceBody] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func point(rig: HangingSourceBody) -> Vector2:
	return rig.sprite.get_global_transform_with_canvas().origin

func setup() -> void:
	fixture = Node2D.new()
	fixture.name = "HangingFixture"
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.z_index = 30
	fixture.add_child(world)
	var drag := Node2D.new()
	drag.name = "DragLayer"
	world.add_child(drag)
	var zones := Node2D.new()
	zones.name = "DropZones"
	world.add_child(zones)
	controller = TestController.new()
	controller.name = "InteractionController"
	controller.drag_layer_path = NodePath("../World/DragLayer")
	controller.drop_zone_root_path = NodePath("../World/DropZones")
	fixture.add_child(controller)
	root.add_child(fixture)
	var banana := load("res://assets/art/icons/banana_ready_provisional.png") as Texture2D
	var biscuit := load("res://assets/art/icons/biscuits_ready_provisional.png") as Texture2D
	var definitions := [
		["BananasLeft", Vector2(436.72,289.77002), banana, Rect2(0,0,192,367), 0.62, Vector2(76,0)],
		["BananasRight", Vector2(436.72,289.77002), banana, Rect2(192,0,120,367), 0.62, Vector2(249,51)],
		["BiscuitBag", Vector2(1527.2272,208.15034), biscuit, Rect2(0,0,398,686), 0.33279985, Vector2(245,12)],
	]
	for definition in definitions:
		var rig := RigScript.new() as HangingSourceBody
		rig.name = definition[0]
		rig.position = definition[1]
		world.add_child(rig)
		rig.configure(controller,definition[2],definition[3],definition[4],definition[5])
		rigs.append(rig)

func verify_layout(rig: HangingSourceBody, scale_factor: float) -> void:
	check(rig.body is RigidBody2D and rig.pin_joint is PinJoint2D and rig.anchor is StaticBody2D,"%s uses a real rigid body, pin joint and fixed body" % rig.name)
	check(rig.pin_joint.get_node(rig.pin_joint.node_a) == rig.anchor and rig.pin_joint.get_node(rig.pin_joint.node_b) == rig.body,"%s joint connects both live physics bodies" % rig.name)
	check(rig.body.global_scale.is_equal_approx(Vector2.ONE) and rig.anchor.global_scale.is_equal_approx(Vector2.ONE),"%s physics bodies retain unit scale at viewport factor %.3f" % [rig.name,scale_factor])
	check(not rig.body.z_as_relative and rig.body.z_index == 30,"%s retains the original authored render layer independently of its top-level physics transform" % rig.name)
	var expected_anchor := rig.global_transform * ((rig._texture_pivot - rig._texture.get_size() * 0.5) * rig._art_scale)
	check(rig.pin_joint.global_position.distance_to(expected_anchor) < 0.001 and rig.anchor.global_position.distance_to(expected_anchor) < 0.001,"%s pin stays on its authored visible attachment" % rig.name)
	check(rig.sprite.scale.is_equal_approx(Vector2.ONE * rig._art_scale * scale_factor),"%s scales artwork without scaling a physics body" % rig.name)
	check(rig._body_shape.size.is_equal_approx(rig._region.size * rig._art_scale * scale_factor),"%s uses a unique resized body shape" % rig.name)
	check(rig.contains_pointer(point(rig)) and rig.is_frontmost_at(point(rig)),"%s moving region center remains an actionable visible pixel" % rig.name)
	check(rig.body.is_ancestor_of(rig.input_area) and rig.is_ancestor_of(rig.input_area),"%s moving input area remains beneath the fixed source owner" % rig.name)
	check(rig.pin_joint.angular_limit_enabled and is_equal_approx(rig.pin_joint.angular_limit_upper,deg_to_rad(rig.swing_limit_degrees)),"%s configures bounded joint rotation" % rig.name)

func run() -> void:
	root.size = Vector2i(1920,1080)
	setup()
	await frames(2)
	for rig in rigs:
		verify_layout(rig,1.0)
	check(rigs[0]._body_shape != rigs[1]._body_shape and rigs[0]._input_shape != rigs[1]._input_shape,"Both banana bodies own separate collision shapes")
	# A stationary pointer, a transparent gap and a covered world inject no energy.
	var left := rigs[0]
	var before := left.impulse_count
	check(not left.brush_pointer(point(left),Vector2.ZERO,1.0/60.0),"A stationary pointer supplies no impulse")
	check(not left.brush_pointer(Vector2(600,600),Vector2(10,0),1.0/60.0),"A motion away from the source supplies no impulse")
	check(not left.contains_pointer(Vector2(458,220)),"Transparent space between the banana crops is not a source hit")
	check(left.impulse_count == before,"Rejected brushing does not accumulate impulses")
	for hidden in [left.sprite,left.body,left.input_area]:
		hidden.hide()
		check(not left.contains_pointer(point(left)),"Hidden %s cannot be brushed or extracted through" % hidden.name)
		hidden.show()
	left._input_collision.disabled = true
	check(not left.contains_pointer(point(left)),"A disabled moving input shape cannot receive extraction")
	left._input_collision.disabled = false
	left.input_area.input_pickable = false
	check(not left.contains_pointer(point(left)),"A non-pickable source area cannot receive extraction")
	left.input_area.input_pickable = true
	var overlap := RigScript.new() as HangingSourceBody
	overlap.name = "OverlapSource"
	overlap.position = left.position + Vector2(0,-20)
	world.add_child(overlap)
	overlap.configure(controller,left._texture,left._region,left._art_scale,left._texture_pivot)
	await frames(2)
	check(overlap.contains_pointer(point(left)),"Overlap fixture covers the same visible body pixels")
	check(overlap.is_frontmost_at(point(left)) and not left.is_frontmost_at(point(left)),"Equal-Z top-level bodies choose the later drawn source despite its lower authored Y")
	left.z_index = 1
	await frames(2)
	check(left.is_frontmost_at(point(left)) and not overlap.is_frontmost_at(point(left)),"An explicit higher render layer wins source picking")
	left.z_index = 0
	var original_index := left.get_index()
	world.move_child(left,world.get_child_count()-1)
	await frames(2)
	check(left.is_frontmost_at(point(left)) and not overlap.is_frontmost_at(point(left)),"Reordering top-level sources changes picking with their actual draw order")
	world.move_child(left,original_index)
	overlap.free()
	controller.ui_covered = true
	check(not left.brush_pointer(point(left),Vector2(20,0),1.0/60.0),"A UI control occluding the pointer blocks brushing")
	controller.ui_covered = false
	controller.covered_regions = [Rect2(point(left)-Vector2(100,200),Vector2(200,400))]
	check(not left.brush_pointer(point(left)+Vector2(240,0),Vector2(240,0),0.1),"A sweep leaving an overlay cannot nudge the source hidden along its earlier path")
	controller.covered_regions.clear()
	check(left.brush_pointer(point(left)+Vector2(240,0),Vector2(240,0),0.1),"An unobscured fast sweep can cross the source even when its endpoint is outside")
	controller.set_world_input_blocked(fixture,true)
	check(not left.brush_pointer(point(left),Vector2(20,0),1.0/60.0),"An open modal blocks brushing")
	controller.set_world_input_blocked(fixture,false)
	# All approved modes nudge the same physical pendulum.
	for mode in [InteractionController.MODE_NEUTRAL,InteractionController.MODE_INTERACT,InteractionController.MODE_ORGANIZE]:
		controller.set_mode(mode)
		left.reset_sway()
		await frames(2)
		var attachment := left.body.to_local(left.anchor.global_position)
		var fixed_position := left.anchor.global_position
		check(left.brush_pointer(point(left),Vector2(22,0),1.0/60.0),"Rightward brushing is active in %s" % mode)
		check(left.last_impulse < 0.0,"Rightward brush supplies torque toward the pointer sweep")
		await frames(12)
		check(left.body.rotation < -0.001,"Real physics moves the hanging body right in %s" % mode)
		check(left.contains_pointer(point(left)),"The moving art and extraction hit target remain aligned in %s" % mode)
		check(left.anchor.global_position == fixed_position and left.body.to_global(attachment).distance_to(fixed_position) < 1.0,"%s keeps the visible hanging attachment pinned" % mode)
		var count_after := left.impulse_count
		await frames(4)
		check(left.impulse_count == count_after,"Swinging beneath a stationary cursor causes no repeated impulse")
	controller.set_mode(InteractionController.MODE_INTERACT)
	var visual := Node2D.new()
	var payload := HeldItemPayload.new(&"physical_source",&"banana",1,visual,{"transient":true})
	check(controller.start_drag(payload,visual,point(left)),"Fixture starts an active extracted piece")
	check(not left.brush_pointer(point(left),Vector2(20,0),1.0/60.0),"Active extraction takes priority over brushing")
	controller.cancel_drag()
	var action_owner := Node.new()
	fixture.add_child(action_owner)
	check(controller.lock_action(action_owner),"Fixture reserves an existing tool action")
	check(not left.brush_pointer(point(left),Vector2(20,0),1.0/60.0),"An active tool action does not also brush a hanging source")
	controller.unlock_action(action_owner)
	action_owner.free()
	for rig in rigs:
		rig.reset_sway()
		await frames(2)
		check(rig.brush_pointer(point(rig),Vector2(-20,0),1.0/60.0),"%s accepts a normal leftward sweep" % rig.name)
		await frames(18)
		check(rig.body.rotation > 0.001 and rig.body.rotation <= deg_to_rad(rig.swing_limit_degrees + 2.0),"%s visibly swings left within its configured stop" % rig.name)
		check(rig.contains_pointer(point(rig)),"%s retains its input area during physical motion" % rig.name)
	# Large repeated sweeps must hit a real angular stop rather than spin forever.
	left.reset_sway()
	await frames(2)
	var maximum_angle := 0.0
	var maximum_speed := 0.0
	for index in 150:
		var direction := 1.0 if index < 75 else -1.0
		left.brush_pointer(point(left),Vector2(3000 * direction,0),1.0/60.0)
		await frames(1)
		maximum_angle = maxf(maximum_angle,absf(left.body.rotation))
		maximum_speed = maxf(maximum_speed,absf(left.body.angular_velocity))
	check(maximum_angle > deg_to_rad(2.0),"Stress sweeps meaningfully exercise the pendulum")
	check(maximum_angle <= deg_to_rad(left.swing_limit_degrees + 2.0),"Rapid repeated sweeps stay within the physical angular stops")
	check(maximum_speed <= 3.0,"Rapid sweeps cannot build runaway angular velocity")
	check(absf(left.last_impulse) <= left.MAX_IMPULSE,"Individual motion impulses are capped")
	await frames(420)
	check(absf(left.body.rotation) < deg_to_rad(1.0) and absf(left.body.angular_velocity) < 0.03,"Damping settles the source after brushing ends")
	# Layout changes rebuild pixel extents and the fixed pin, with no scaled body.
	for dimensions in [Vector2(1600,900),Vector2(1366,768),Vector2(1280,800)]:
		var cover := maxf(dimensions.x/1920.0,dimensions.y/1080.0)
		world.scale = Vector2.ONE * cover
		world.position = (dimensions - Vector2(1920,1080) * cover) * 0.5
		for rig in rigs:
			rig.sync_layout()
		await frames(2)
		for rig in rigs:
			verify_layout(rig,cover)
		var body_origin := left.body.global_position
		check(left.brush_pointer(point(left),Vector2(-20,0)*cover,1.0/60.0),"A resized source still accepts a leftward brush")
		await frames(12)
		check(left.body.rotation > 0.001 and left.body.global_position.x < body_origin.x,"A resized pendulum responds left while preserving its anchored joint")
	world.position += Vector2(17,9)
	await frames(3)
	for rig in rigs:
		var expected := rig.global_transform * ((rig._texture_pivot - rig._texture.get_size() * 0.5) * rig._art_scale)
		check(rig.pin_joint.global_position.distance_to(expected) < 0.001,"%s automatically synchronizes when its parent layout changes" % rig.name)
	var held_parent := left.get_parent()
	held_parent.remove_child(left)
	check(not left.brush_pointer(Vector2.ZERO,Vector2(20,0),1.0/60.0) and not left.contains_pointer(Vector2.ZERO),"A detached source cannot brush or receive extraction input")
	held_parent.add_child(left)
	left.reset_sway()
	await frames(2)
	check(left.can_brush() and left.contains_pointer(point(left)),"Re-entered source restores a usable fixed attachment")
	fixture.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(left),"Scene exit destroys the source, physical body and joint together")
	print("HANGING_PHYSICS: %d checks; %d failures; stress angle %.3f deg; speed %.3f" % [checks,failures.size(),rad_to_deg(maximum_angle),maximum_speed])
	quit(0 if failures.is_empty() else 1)
