extends SceneTree

const Surface := preload("res://scripts/gameplay/interactions/placement_surface.gd")
var checks := 0
var failures: Array[String] = []
var world: Node2D
var drag_drops := 0
var drag_cancels := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func rect(x: float, y: float, width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x,y), Vector2(x+width,y), Vector2(x+width,y+height), Vector2(x,y+height)])

func polygons(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	return [polygon]

func item_at(position: Vector2, parent: Node = null) -> Node2D:
	var item := Node2D.new()
	(parent if parent != null else world).add_child(item)
	item.position = position
	return item

func new_surface(polygon: PackedVector2Array) -> Surface:
	var surface := Surface.new()
	world.add_child(surface)
	surface.usable_polygon = polygon
	return surface

func exclusion(surface: Surface, polygon: PackedVector2Array) -> Polygon2D:
	var container := surface.get_node_or_null("Exclusions")
	if container == null:
		container = Node2D.new()
		container.name = "Exclusions"
		surface.add_child(container)
	var shape := Polygon2D.new()
	shape.polygon = polygon
	shape.visible = false
	container.add_child(shape)
	return shape

func reset_world() -> void:
	if is_instance_valid(world):
		world.free()
	world = Node2D.new()
	root.add_child(world)

func equal_polygons(first: Array[PackedVector2Array], second: Array[PackedVector2Array]) -> bool:
	if first.size() != second.size():
		return false
	for i in first.size():
		if first[i].size() != second[i].size():
			return false
		for j in first[i].size():
			if first[i][j].distance_to(second[i][j]) > .001:
				return false
	return true

func check_controller_contact(size: Vector2i) -> void:
	reset_world()
	root.size = size
	var factor := maxf(size.x / 1920.0, size.y / 1080.0)
	world.scale = Vector2(factor, factor)
	world.position = Vector2(-37.25, 81.5)
	var home := item_at(Vector2.ZERO)
	var layer := item_at(Vector2.ZERO)
	layer.name = "DragLayer"
	var zones := item_at(Vector2.ZERO)
	zones.name = "DropZoneRoot"
	var interaction := InteractionController.new()
	interaction.drag_layer_path = NodePath("../DragLayer")
	interaction.drop_zone_root_path = NodePath("../DropZoneRoot")
	world.add_child(interaction)
	interaction.set_mode(InteractionController.MODE_ORGANIZE)
	interaction.drag_dropped.connect(func(_payload: HeldItemPayload, _zone: DropZone) -> void: drag_drops += 1)
	interaction.drag_canceled.connect(func(_payload: HeldItemPayload) -> void: drag_cancels += 1)
	var surface := new_surface(rect(0,0,1920,1080))
	var a := item_at(Vector2(1680,850), home)
	var b := item_at(Vector2(1700,850), home)
	var handle := TablePlaceable.new()
	handle.footprint = rect(0,0,20,20)
	a.add_child(handle)
	check(handle.configure(surface, interaction) and surface.register_item(b, polygons(rect(0,0,20,20))), "Actual controller contact fixture registers at %s" % size)
	var original := a.transform
	var pointer := a.get_global_transform_with_canvas().origin + Vector2(7,-11)
	var drops_before := drag_drops
	var cancels_before := drag_cancels
	check(handle.begin_drag(pointer), "Actual contact pickup starts at %s" % size)
	check(a.transform == original and surface.validate_item(a).is_valid, "Pickup preserves exact contacting base at %s" % size)
	interaction.update_drag(pointer + Vector2(-80,0))
	check(surface.validate_item(a).is_valid, "Contacting item can move away at %s" % size)
	interaction.update_drag(pointer)
	check(a.transform == original and surface.validate_item(a).is_valid, "Returning pointer restores exact contact at %s" % size)
	interaction.release_drop(pointer)
	check(drag_drops == drops_before + 1 and drag_cancels == cancels_before, "Exact contact release commits instead of canceling at %s" % size)
	check(a.get_parent() == home and a.transform == original and surface.validate_item(a).is_valid, "Successful reparent preserves exact committed contact at %s" % size)
	check(surface.get_candidate_polygons(a) == surface.get_committed_polygons(a), "Successful reparent does not move committed base at %s" % size)
	a.position.x = 1580
	check(surface.commit_item(a), "Fresh-contact move starts from disjoint base at %s" % size)
	pointer = a.get_global_transform_with_canvas().origin + Vector2(7,-11)
	check(handle.begin_drag(pointer), "Fresh-contact drag starts at %s" % size)
	var contact_pointer := home.get_global_transform_with_canvas() * original.origin + Vector2(7,-11)
	interaction.update_drag(contact_pointer)
	check(surface.validate_item(a).is_valid, "Moving to a fresh exact peer contact is valid at %s" % size)
	drops_before = drag_drops
	interaction.release_drop(contact_pointer)
	# A newly sampled viewport endpoint has float32 coordinate quantization;
	# it must stay geometrically valid and within subpixel authored precision.
	check(drag_drops == drops_before + 1 and a.position.distance_to(original.origin) < 0.001
		and a.transform.x == original.x and a.transform.y == original.y,
		"Fresh contact commits at the requested subpixel position at %s" % size)
	check(surface.get_candidate_polygons(a) == surface.get_committed_polygons(a), "Fresh exact contact reservation matches live base at %s" % size)

	# Non-identity parents exercise the same real path without relying on the
	# production scene's currently identity home/drag layers.
	surface.unregister_item(b)
	home.position = Vector2(15,5)
	home.rotation = 0.03
	home.scale = Vector2(0.8,0.7)
	layer.position = Vector2(-20,10)
	layer.rotation = -0.04
	layer.scale = Vector2(0.9,1.1)
	a.position = Vector2(500,500)
	check(surface.commit_item(a), "Transformed-parent starting reservation commits at %s" % size)
	var before := a.get_global_transform_with_canvas()
	pointer = before.origin + Vector2(7,-11)
	check(handle.begin_drag(pointer), "Transformed-parent drag starts at %s" % size)
	check(a.get_global_transform_with_canvas().is_equal_approx(before), "Pickup preserves transformed-parent world pose at %s" % size)
	var displacement := Vector2(21.5,-13.25)
	interaction.update_drag(pointer + displacement)
	check(a.get_global_transform_with_canvas().origin.distance_to(before.origin + displacement) < 0.001, "Drag follows viewport displacement through transformed parents at %s" % size)
	var expected := a.get_global_transform_with_canvas()
	interaction.release_drop(pointer + displacement)
	check(a.get_parent() == home and a.get_global_transform_with_canvas().is_equal_approx(expected), "Drop preserves transformed-parent moved pose at %s" % size)
	check(equal_polygons(surface.get_candidate_polygons(a), surface.get_committed_polygons(a)), "Transformed-parent drop reservation matches live base at %s" % size)

func run() -> void:
	reset_world()
	var surface := new_surface(rect(0,0,100,100))
	var a := item_at(Vector2(10,10))
	var footprint := rect(0,0,10,10)
	var original_input := polygons(footprint)
	check(surface.register_item(a, original_input), "A valid item registers")
	check(surface.is_registered(a) and surface.validate_item(a).is_valid, "Registered item ignores its own reservation")
	original_input[0][0] = Vector2(-999,-999)
	check(surface.validate_item(a).is_valid, "Caller mutation cannot change stored local footprints")
	footprint = rect(0,0,10,10)
	var exposed := surface.get_committed_polygons(a)
	exposed[0][0] = Vector2(-999,-999)
	check(surface.get_committed_polygons(a)[0][0] == Vector2(10,10), "Committed polygon getters return copies")
	var origin := surface.get_committed_polygons(a)
	a.position = Vector2(60.25,10.75)
	check(surface.validate_item(a).is_valid, "Arbitrary between-cell candidate is valid")
	check(equal_polygons(surface.get_committed_polygons(a), origin), "Candidate movement retains origin reservation")
	var b := item_at(Vector2(10,10))
	check(not surface.register_item(b, polygons(footprint)), "Other item cannot take a dragged item's reserved origin")
	b.position = Vector2(80,10)
	check(surface.register_item(b, polygons(footprint)), "A disjoint peer registers")
	a.position = Vector2(85,10)
	check(surface.validate_item(a).reason_key == "placement.overlap", "Peer area overlap is rejected")
	check(not surface.commit_item(a) and equal_polygons(surface.get_committed_polygons(a), origin), "Failed commit preserves old reservation")
	check(not surface.register_item(a, polygons(rect(0,0,40,40))) and equal_polygons(surface.get_committed_polygons(a), origin), "Failed re-registration preserves old geometry")
	a.position = Vector2(10,10)
	check(surface.commit_item(a), "Caller rollback can recommit the exact origin")
	a.position = Vector2(40.5,15.25)
	check(surface.commit_item(a), "Successful free placement updates reservation")
	var c := item_at(Vector2(10,10))
	check(surface.register_item(c, polygons(footprint)), "Successful commit releases the previous origin")
	surface.unregister_item(c)
	check(not surface.is_registered(c) and surface.get_committed_polygons(c).is_empty(), "Unregister releases identity and geometry")
	check(surface.validate_item(c).reason_key == "placement.unregistered" and not surface.commit_item(c), "Unknown items cannot commit")
	a.position = Vector2(90,10)
	check(surface.validate_item(a).is_valid, "Exact surface and peer edge contact is allowed")
	a.position.x = 90.001
	check(surface.validate_item(a).reason_key == "placement.outside_surface", "A 0.001-unit boundary crossing is rejected")
	a.position = Vector2(89.999,10)
	check(surface.validate_item(a).reason_key == "placement.overlap", "A 0.001-unit peer overlap is rejected")
	a.position = Vector2(90,10.0000001)
	check(surface.validate_item(a).is_valid, "Subprecision edge movement adds no gameplay padding")
	surface.unregister_item(b)
	var block := exclusion(surface, rect(40,40,20,20))
	a.position = Vector2(30,40)
	check(surface.validate_item(a).is_valid, "Exact hidden exclusion edge contact is allowed")
	a.position.x = 30.001
	check(surface.validate_item(a).reason_key == "placement.blocked", "Tiny positive exclusion overlap is rejected")
	a.position = Vector2(0,0)
	check(surface.validate_item(a).is_valid, "Multiple boundary edges can touch")
	block.position = Vector2(-30,-30)
	check(surface.validate_item(a).is_valid, "Transformed exclusion allows shared corner")
	a.position = Vector2(5,5)
	check(surface.validate_item(a).reason_key == "placement.blocked", "Exclusion child transforms affect occupied space")
	block.position = Vector2.ZERO
	block.offset = Vector2(-30,-30)
	check(surface.validate_item(a).reason_key == "placement.blocked", "Polygon2D per-vertex offset affects exclusion geometry")
	block.offset = Vector2.ZERO
	a.position = Vector2(30,40)
	check(surface.commit_item(a), "Boundary candidate commits before resize")
	b.position = Vector2(20,40)
	check(surface.register_item(b, polygons(footprint)), "Peer commits against same exact edge")
	for factor in [1600.0/1920.0, 1366.0/1920.0, 1280.0/1920.0, 800.0/1080.0, 1.3, 1.375]:
		world.scale = Vector2(factor,factor)
		world.position = Vector2(-37.25,81.5)
		check(surface.validate_item(a).is_valid and surface.validate_item(b).is_valid, "Shared exclusion and peer edges remain valid after resize %f" % factor)
	reset_world()
	surface = new_surface(rect(0,0,1920,1080))
	a = item_at(Vector2(1680,900))
	b = item_at(Vector2(1700,900))
	check(surface.register_item(a, polygons(rect(0,0,20,20))) and surface.register_item(b, polygons(rect(0,0,20,20))), "Exact peer edge at full authored coordinates registers")
	exclusion(surface, rect(1720,900,20,20))
	for factor in [1600.0/1920.0, 1366.0/1920.0, 1280.0/1920.0, 800.0/1080.0, 1.3, 1.375]:
		world.scale = Vector2(factor,factor)
		world.position = Vector2(-37.25,81.5)
		check(surface.validate_item(a).is_valid and surface.validate_item(b).is_valid, "Full-size authored edge contacts survive resize %f" % factor)

	reset_world()
	var concave := PackedVector2Array([Vector2(0,0),Vector2(100,0),Vector2(100,100),Vector2(70,100),Vector2(70,30),Vector2(30,30),Vector2(30,100),Vector2(0,100)])
	surface = new_surface(concave)
	a = item_at(Vector2(10,40))
	check(not surface.register_item(a, polygons(rect(0,0,80,10))), "Edges bridging a concave gap fail despite all vertices lying inside")
	var compound: Array[PackedVector2Array] = [rect(0,0,10,10), rect(80,0,10,10)]
	a.position = Vector2(5,40)
	check(surface.register_item(a, compound), "Disjoint compound bases can fit separate concave arms")
	check(surface.get_candidate_polygons(a).size() == 2, "Compound components are retained independently")
	a.position.x = 25
	check(not surface.commit_item(a), "One invalid compound component rejects the entire commit")
	a.position = Vector2(5,40)
	var reversed := concave.duplicate()
	reversed.reverse()
	surface.usable_polygon = reversed
	check(surface.validate_item(a).is_valid, "Usable winding does not change containment")
	var hole_contours := Geometry2D.clip_polygons(rect(0,0,100,100), rect(20,20,20,20))
	check(hole_contours.size() == 2 and is_equal_approx(surface._filled_area(hole_contours), 9600.0), "Boolean contour area subtracts holes instead of adding them")
	var reverse_subject := rect(0,0,100,100)
	reverse_subject.reverse()
	check(is_equal_approx(surface._filled_area(Geometry2D.clip_polygons(reverse_subject, rect(20,20,20,20))), 9600.0), "Boolean area respects winding independent of subject orientation")
	surface.usable_polygon = rect(0,0,100,100)
	block = exclusion(surface, PackedVector2Array([Vector2(40,40),Vector2(70,40),Vector2(70,50),Vector2(50,50),Vector2(50,70),Vector2(40,70)]))
	c = item_at(Vector2(55,55))
	check(surface.register_item(c, polygons(footprint)), "Concave blocker leaves its open corner usable")
	c.position = Vector2(45,45)
	check(surface.validate_item(c).reason_key == "placement.blocked", "Crossing either concave blocker arm is rejected")

	reset_world()
	surface = new_surface(rect(0,0,1000,1000))
	var nested := item_at(Vector2(100,100))
	nested.rotation = .17
	nested.scale = Vector2(1.3,.7)
	a = item_at(Vector2(20,30), nested)
	a.rotation = -.11
	a.scale = Vector2(2,.5)
	check(surface.register_item(a, polygons(footprint)), "Nested rotation and nonuniform scaling register through global transforms")
	origin = surface.get_committed_polygons(a)
	for factor in [1.0, 1600.0/1920.0, 1366.0/1920.0, 1280.0/1920.0, 1.375]:
		world.scale = Vector2(factor,factor)
		world.position = Vector2(-37.25,81.5)
		check(equal_polygons(surface.get_candidate_polygons(a), origin) and surface.validate_item(a).is_valid, "World resize %f keeps authored coordinates and reservations" % factor)
	var drag_layer := item_at(Vector2(20,10))
	a.reparent(drag_layer, true)
	check(surface.is_registered(a) and equal_polygons(surface.get_candidate_polygons(a), origin), "Legitimate active-tree reparent retains identity and position")
	check(equal_polygons(surface.get_committed_polygons(a), origin), "Reparenting does not rewrite the reservation")
	a.scale.x *= -1
	check(surface.validate_item(a).is_valid, "Mirrored valid footprints retain geometric validity")
	a.scale = Vector2.ZERO
	check(surface.validate_item(a).reason_key == "placement.invalid_geometry", "Singular item transform is rejected")
	a.scale = Vector2.ONE
	var prior_surface_transform := surface.transform
	surface.scale = Vector2.ZERO
	check(not surface.validate_item(a).is_valid, "Singular surface transform is rejected")
	surface.transform = prior_surface_transform
	a.position.x = NAN
	check(not surface.validate_item(a).is_valid, "Nonfinite item transform is rejected before geometry calls")
	a.position = Vector2(300,300)
	check(surface.commit_item(a), "Recovered valid transform can commit")
	b = item_at(Vector2(300,300), drag_layer)
	check(not surface.register_item(b, polygons(footprint)), "Live committed peer blocks a matching footprint")
	drag_layer.remove_child(a)
	check(surface.register_item(b, polygons(footprint)) and not surface.is_registered(a), "Detached peers are purged before validation")
	drag_layer.add_child(a)
	check(not surface.is_registered(a), "Readded detached item needs explicit registration")
	b.queue_free()
	check(surface.register_item(a, polygons(footprint)), "Queued peer deletion releases stale occupancy safely")
	a.free()
	c = item_at(Vector2(300,300), drag_layer)
	check(not surface.is_registered(c) and surface.register_item(c, polygons(footprint)), "Freed weak identity does not transfer to a new instance")
	c.set_as_top_level(true)
	c.global_position = surface.to_global(Vector2(500,500))
	var top_level_expected := surface.global_transform.affine_inverse() * c.global_transform
	check(surface.validate_item(c).is_valid and surface.get_candidate_polygons(c)[0][0].distance_to(top_level_expected * Vector2.ZERO) < .001, "Top-level items use their independent global transform root")
	var control_parent := Control.new()
	world.add_child(control_parent)
	control_parent.position = Vector2(40,40)
	control_parent.scale = Vector2(1.2,.8)
	var control_item := item_at(Vector2(300,300), control_parent)
	var control_expected := surface.global_transform.affine_inverse() * control_item.global_transform
	check(surface.register_item(control_item, polygons(footprint)) and surface.get_candidate_polygons(control_item)[0][0].distance_to(control_expected * Vector2.ZERO) < .001, "Control ancestry retains Godot global-transform semantics")

	reset_world()
	surface = new_surface(rect(0,0,100,100))
	a = item_at(Vector2(10,10))
	check(not surface.register_item(a, []), "Empty compound geometry is rejected")
	check(not surface.register_item(a, polygons(PackedVector2Array([Vector2.ZERO,Vector2.ONE]))), "Fewer than three vertices is rejected")
	check(not surface.register_item(a, polygons(PackedVector2Array([Vector2.ZERO,Vector2(10,0),Vector2(20,0)]))), "Zero-area contour is rejected")
	check(not surface.register_item(a, polygons(PackedVector2Array([Vector2.ZERO,Vector2(10,0),Vector2(10,0),Vector2(0,10)]))), "Consecutive duplicate vertices are rejected")
	check(not surface.register_item(a, polygons(PackedVector2Array([Vector2.ZERO,Vector2(20,20),Vector2(0,20),Vector2(20,0),Vector2(30,10)]))), "Nonzero-area self-intersection is rejected")
	check(not surface.register_item(a, polygons(PackedVector2Array([Vector2(NAN,0),Vector2(20,0),Vector2(0,20)]))), "Nonfinite footprint coordinates are rejected")
	check(not surface.register_item(a, polygons(rect(0,0,1e30,1e30))), "Overflowed polygon area is rejected before boolean geometry")
	check(surface.register_item(a, polygons(footprint)), "Invalid attempts leave registration available")
	surface.usable_polygon = PackedVector2Array()
	check(surface.validate_item(a).reason_key == "placement.invalid_geometry", "Missing usable polygon fails closed")
	surface.usable_polygon = rect(0,0,100,100)
	block = exclusion(surface, PackedVector2Array([Vector2.ZERO,Vector2.ONE]))
	check(surface.validate_item(a).reason_key == "placement.invalid_geometry", "Malformed authored exclusion fails closed")
	block.polygon = rect(50,50,10,10)
	block.scale = Vector2.ZERO
	check(surface.validate_item(a).reason_key == "placement.invalid_geometry", "Singular exclusion transform fails closed")
	block.scale = Vector2.ONE
	var surface_parent := surface.get_parent()
	surface_parent.remove_child(surface)
	check(not surface.validate_item(a).is_valid and not surface.register_item(a, polygons(footprint)), "Detached surfaces cannot accept placement")
	surface_parent.add_child(surface)
	check(surface.validate_item(a).is_valid, "Reparented active surface remains usable")
	for size in [Vector2i(1920,1080), Vector2i(1366,768), Vector2i(1280,720), Vector2i(1280,800)]:
		check_controller_contact(size)
	world.free()
	await process_frame
	print("PLACEMENT_GEOMETRY: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
