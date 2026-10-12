extends SceneTree

# Actual viewport picking, mode arbitration and brewing after free transfers.
var failures: Array[String] = []
var checks := 0
var preview: Node
var world: Node2D
var controller: InteractionController
var table: PlacementSurface
var interior: PlacementSurface
var tray: TrayStation
var rail: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func at(authored: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas() * authored

func handle_for(item: Node2D) -> TablePlaceable:
	return item.get_node("PlacementHandle") as TablePlaceable

func base_center(item: Node2D) -> Vector2:
	var handle := handle_for(item)
	var polygons := handle.surface.get_candidate_polygons(item)
	var bounds := Rect2(polygons[0][0],Vector2.ZERO)
	for polygon in polygons:
		for point in polygon:
			bounds = bounds.expand(point)
	return world.to_local(handle.surface.to_global(bounds.get_center()))

func move_pointer(point: Vector2, held := true) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event,true)
	await physics_frame
	await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	await move_pointer(point,pressed)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event,true)
	await physics_frame
	await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func tap(code: Key) -> void:
	await key(code,true)
	await key(code,false)

func transfer(item: Node2D, target: Vector2, destination: PlacementSurface, label: String, grip := Vector2.ZERO) -> void:
	var origin := world.to_local(item.global_position)
	var drop_at := origin + target - base_center(item)
	var before := item.global_transform
	await mouse(at(origin+grip),true)
	check(controller.current_drag_node == item, "%s real click picks the visible intended object" % label)
	await mouse(at(drop_at+grip),false)
	check(not controller.is_dragging() and handle_for(item).surface == destination and destination.is_registered(item), "%s real drop changes to the correct surface" % label)
	check(base_center(item).distance_to(target) < .003, "%s preserves free pointer placement" % label)
	check(item.global_transform.x.is_equal_approx(before.x) and item.global_transform.y.is_equal_approx(before.y), "%s preserves visual size after transfer" % label)

func reject(item: Node2D, target: Vector2, label: String) -> void:
	var owner := handle_for(item).surface
	var parent := item.get_parent()
	var pose := item.transform
	var drop_at := world.to_local(item.global_position)+target-base_center(item)
	await mouse(item.get_global_transform_with_canvas().origin,true)
	check(controller.current_drag_node == item, "%s picks the expected item" % label)
	await move_pointer(at(drop_at))
	check(controller.hovered_drop_zone != null and not controller.hovered_drop_zone.accepts(controller.current_payload).is_valid, "%s provides invalid preview" % label)
	await mouse(at(drop_at),false)
	check(not controller.is_dragging() and item.get_parent() == parent and item.transform.is_equal_approx(pose) and handle_for(item).surface == owner, "%s returns exactly to its origin" % label)

func aim(kettle: Kettle, cup: Cup) -> Vector2:
	return kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin + cup.get_node("PourTarget").get_global_transform_with_canvas().origin - kettle.get_pour_probe_viewport()

func verify_filled_overlap(back: Cup, front: Cup, captures: PackedStringArray) -> void:
	var back_origin := base_center(back)
	var front_origin := base_center(front)
	var back_base := Vector2(1580,865)
	var front_base := Vector2(1580,878)
	back.receive_liquid(&"black_tea",120,70)
	front.receive_liquid(&"black_tea",150,80)
	for front_last in [true,false]:
		if front_last:
			await transfer(back,back_base,table,"Rear filled cup fixture",Vector2(0,-20))
			await transfer(front,front_base,table,"Front filled cup fixture")
		else:
			await transfer(front,front_base,table,"Front filled cup fixture")
			await transfer(back,back_base,table,"Rear filled cup fixture",Vector2(0,-20))
		check(Geometry2D.intersect_polygons(table.get_candidate_polygons(back)[0],table.get_candidate_polygons(front)[0]).is_empty(),"Overlapping cup artwork has two separate physical bases")
		for cup in [back,front]:
			var liquid := cup.get_node("ContentsOverlay") as Sprite2D
			var body := cup.get_node("Sprite2D") as Sprite2D
			check(liquid.visible and liquid.z_as_relative and body.z_as_relative and liquid.z_index == body.z_index,"Filled cup liquid inherits the same painter depth as its body")
		var shared_point := (back.get_global_transform_with_canvas().origin + front.get_global_transform_with_canvas().origin) * .5
		check(handle_for(back)._contains_pointer(shared_point) and handle_for(front)._contains_pointer(shared_point),"Overlap regression clicks both filled cup hit shapes")
		await mouse(shared_point,true)
		check(controller.current_drag_node == front,"Real shared click picks front filled cup when front-placed-last is %s" % front_last)
		await tap(KEY_ESCAPE)
		await mouse(shared_point,false)
		check(base_center(back).distance_to(back_base) < .003 and base_center(front).distance_to(front_base) < .003 and back.volume_ml == 120 and front.volume_ml == 150,"Overlap-pick cancellation preserves both filled placements and contents")
		if front_last and captures.size() > 2:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(captures[2]) == OK,"Overlapping filled-cup depth review capture saved")
		await transfer(front,front_origin,table,"Front overlap cup restored")
		await transfer(back,back_origin,table,"Rear overlap cup restored",Vector2(0,-20))
	back.reset_clean()
	front.reset_clean()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run tray_transfer_input_test.gd with a window for real physics picking; use tray_transfer_test.gd headlessly.")
		quit(2)
		return
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	world = preview.screen.get_node("WorldRoot")
	controller = preview.controller
	table = preview.screen.table_surface
	tray = world.get_node("ToolLayer/TrayStation") as TrayStation
	interior = tray.get_node("InteriorSurface") as PlacementSurface
	rail = world.get_node("ToolLayer/ReadyItemRail") as Node2D
	var cups: Array[Cup] = tray.get_cups()
	var initial_bases: Array[Vector2] = []
	for cup in cups:
		initial_bases.append(base_center(cup))
	var captures := OS.get_cmdline_user_args()
	if captures.size() > 0:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[0]) == OK,"Initial transfer review capture saved")
	await tap(KEY_G)
	check(controller.current_mode == InteractionController.MODE_ORGANIZE,"Real G selects arrangement mode")
	for index in cups.size():
		await transfer(cups[index],Vector2(825+55*(index%3),835+120*(index/3)),table,"%s onto table" % cups[index].name)
	check(tray.get_cup_count() == 0 and preview.screen.get_cups().size() == 6,"Real transfers keep all cups discoverable outside tray")
	await verify_filled_overlap(cups[4],cups[5],captures)
	var sources: Array[Node2D] = []
	var source_bases: Array[Vector2] = []
	for source_name in ["TeaBox","SugarCan","SugarCanEnglish","CondensedMilkCan"]:
		var source := rail.get_node(String(source_name)) as Node2D
		sources.append(source)
		source_bases.append(base_center(source))
		await transfer(source,Vector2(1259.125,889.375),interior,"%s onto tray" % source_name)
		await transfer(source,source_bases.back(),table,"%s back to table" % source_name)
	# Cup hit areas must win over their underlying tray when Organize is active.
	await transfer(cups[0],Vector2(1130,925),interior,"Cup re-enters tray")
	await transfer(sources[0],Vector2(1270,875),interior,"Tea joins populated tray")
	var cup_local := cups[0].transform
	var tea_local := sources[0].transform
	var table_cup_pose := cups[1].global_transform
	var tray_base := base_center(tray)
	await transfer(tray,tray_base+Vector2(-8.125,29.375),table,"Mixed populated tray",Vector2(0,10))
	check(cups[0].transform.is_equal_approx(cup_local) and sources[0].transform.is_equal_approx(tea_local),"Real tray movement carries cup and ingredient at unchanged local positions")
	check(cups[1].global_transform.is_equal_approx(table_cup_pose),"Table cup stays still while tray moves")
	await transfer(tray,tray_base,table,"Mixed tray restored",Vector2(0,10))
	await transfer(sources[0],source_bases[0],table,"Tea restored")
	await reject(cups[0],Vector2(1259,950),"Cup crossing tray rim")
	await reject(cups[0],Vector2(1015,948),"Outer rim is not table fallback")
	await reject(cups[0],base_center(cups[1]),"Occupied table cup base")
	var saved_pose := cups[0].transform
	await mouse(cups[0].get_global_transform_with_canvas().origin,true)
	await move_pointer(at(Vector2(905,945)))
	await tap(KEY_ESCAPE)
	await mouse(at(Vector2(905,945)),false)
	check(not controller.is_dragging() and cups[0].transform.is_equal_approx(saved_pose),"Real Escape cancels a table/tray transfer")
	await mouse(cups[0].get_global_transform_with_canvas().origin,true)
	await tap(KEY_G)
	await mouse(at(Vector2(905,945)),false)
	check(controller.current_mode == InteractionController.MODE_INTERACT and cups[0].transform.is_equal_approx(saved_pose),"Real mode switch cancels pending placement")
	# Interact drags remain actions and cannot silently relocate a cup.
	var action_cup := cups[1]
	var action_pose := action_cup.transform
	await mouse(action_cup.get_global_transform_with_canvas().origin,true)
	check(controller.current_drag_node == action_cup,"Table-owned cup still responds to Interact pickup")
	await mouse(at(Vector2(1260,890)),false)
	check(action_cup.get_parent() == rail and action_cup.transform.is_equal_approx(action_pose),"Interact release over free tray space does not rearrange the cup")
	var kettle := preview.kettle as Kettle
	var drum := world.get_node("ToolLayer/WaterDrum") as WaterDrum
	await mouse(drum.get_global_transform_with_canvas().origin,true)
	await mouse(kettle.get_node("WaterFillTarget").get_global_transform_with_canvas().origin,false)
	check(kettle.volume_ml == 1500,"Production water source remains usable after transfers")
	kettle.apply_heat(10,1)
	kettle.add_tea_leaves()
	kettle.advance_brewing(kettle.config.steep_seconds)
	await mouse(kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin,true)
	for cup in [action_cup,cups[0]]:
		await move_pointer(aim(kettle,cup))
		check(controller.hovered_drop_zone == cup.get_node("PourTarget"),"Visible spout selects transferred %s on its actual surface" % cup.name)
		var before: float = cup.volume_ml
		await key(KEY_SPACE,true)
		await create_timer(.12).timeout
		await key(KEY_SPACE,false)
		check(cup.volume_ml > before,"Held Space pours into transferred %s" % cup.name)
	await mouse(aim(kettle,cups[0]),false)
	check(not controller.is_dragging() and not kettle.is_held,"Kettle returns safely after pouring across surfaces")
	var discard := world.get_node("DropZoneRoot/DiscardArea") as DiscardDropZone
	await mouse(action_cup.get_global_transform_with_canvas().origin,true)
	await mouse(discard.get_global_transform_with_canvas().origin,false)
	check(action_cup.volume_ml == 0 and action_cup.get_parent() == rail and action_cup.transform.is_equal_approx(action_pose),"Real discard empties and returns the table cup")
	# Sample customer remains a fixture; evaluate temperature at the actual drop.
	action_cup.receive_liquid(&"black_tea",170,35)
	await mouse(action_cup.get_global_transform_with_canvas().origin,true)
	await mouse(preview.service_zone.get_global_transform_with_canvas().origin,false)
	check(action_cup.state == Cup.CupState.SERVED and preview.service_zone.review.bad_review_count() == 1,"Transferred cold cup is accepted with one unhappy sample review")
	check(action_cup.transform.is_equal_approx(action_pose),"Sample service restores its real table origin")
	await mouse(action_cup.get_global_transform_with_canvas().origin,true)
	await mouse(preview.service_zone.get_global_transform_with_canvas().origin,false)
	check(preview.service_zone.review.accepted_count() == 1 and preview.service_zone.review.bad_review_count() == 1,"Duplicate action does not add another sample service or review")
	var reset_at: Vector2 = preview.reset_button.get_global_rect().get_center()
	await mouse(reset_at,true)
	await mouse(reset_at,false)
	check(action_cup.volume_ml == 0 and action_cup.state == Cup.CupState.CLEAN and action_cup.get_parent() == rail,"Real preview reset reaches cups on both surfaces without moving them")
	await tap(KEY_G)
	for index in cups.size():
		await transfer(cups[index],initial_bases[index],interior,"%s restored to free tray" % cups[index].name)
	await transfer(sources[1],Vector2(1200,910),interior,"Seventh object fits between old rows")
	check(tray.get_cup_count() == 6 and tray.get_contents().get_child_count() >= 7,"Real picking and placement allow more objects than the old slot count")
	if captures.size() > 1:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[1]) == OK,"Mixed free-tray review capture saved")
	await transfer(sources[1],source_bases[1],table,"Seventh object restored")
	preview.queue_free()
	await process_frame
	print("TRAY_TRANSFER_INPUT: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
