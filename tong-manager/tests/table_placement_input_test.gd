extends SceneTree

# Real viewport picking/regressions for the table and preserved brewing actions.
var failures: Array[String] = []
var checks := 0
var preview: Node
var world: Node2D
var controller: InteractionController

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func at(authored: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas() * authored

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

func arrange(item: Node2D, target: Vector2, label: String, authored_offset := Vector2.ZERO) -> void:
	var start := world.to_local(item.global_position)
	var parent := item.get_parent()
	await mouse(at(start + authored_offset),true)
	check(controller.is_dragging() and controller.current_drag_node == item, "%s real click picks the intended object" % label)
	await mouse(at(target + authored_offset),false)
	check(not controller.is_dragging() and item.get_parent() == parent, "%s real release completes ownership" % label)
	check(world.to_local(item.global_position).is_equal_approx(target), "%s lands continuously without grid snapping" % label)

func aim(kettle: Kettle, cup: Cup) -> Vector2:
	var target := (cup.get_node("PourTarget") as Node2D).get_global_transform_with_canvas().origin
	return (kettle.get_node("GripAnchor") as Node2D).get_global_transform_with_canvas().origin + target - kettle.get_pour_probe_viewport()

func place_overlap_fixture(item: Node2D, target: Vector2) -> void:
	# Only fixture setup bypasses physics picking; the disputed shared click below
	# is sent through the viewport after both bodies have settled.
	var handle := item.get_node("PlacementHandle") as TablePlaceable
	check(handle.begin_drag(item.get_global_transform_with_canvas().origin), "%s overlap fixture starts through the placement command" % item.name)
	controller.release_drop(at(target))
	check(world.to_local(item.global_position).is_equal_approx(target) and handle.validate_placement().is_valid, "%s overlap fixture is committed on free table space" % item.name)
	await physics_frame
	await process_frame

func verify_overlap_picking(rail: Node) -> void:
	var front := rail.get_node("SugarCan") as Node2D
	var back := rail.get_node("SugarCanEnglish") as Node2D
	var front_origin := world.to_local(front.global_position)
	var back_origin := world.to_local(back.global_position)
	var front_transform := front.transform
	var back_transform := back.transform
	var front_handle := front.get_node("PlacementHandle") as TablePlaceable
	var back_handle := back.get_node("PlacementHandle") as TablePlaceable
	var shared_point := Vector2(1600,935)
	for front_last in [true,false]:
		var records := [[back,Vector2(1587,910)],[front,Vector2(1613,950)]] if front_last else [[front,Vector2(1613,950)],[back,Vector2(1587,910)]]
		for record in records:
			await place_overlap_fixture(record[0] as Node2D,record[1])
		var front_base := front_handle.surface.get_candidate_polygons(front)[0]
		var back_base := back_handle.surface.get_candidate_polygons(back)[0]
		check(Geometry2D.intersect_polygons(front_base,back_base).is_empty(), "Overlapping tall art has separate nonoverlapping physical bases")
		var front_body := front.get_node("PlacementBody/CollisionPolygon2D") as CollisionPolygon2D
		var back_body := back.get_node("PlacementBody/CollisionPolygon2D") as CollisionPolygon2D
		check(Geometry2D.is_point_in_polygon(front_body.get_global_transform_with_canvas().affine_inverse()*at(shared_point),front_body.polygon) and Geometry2D.is_point_in_polygon(back_body.get_global_transform_with_canvas().affine_inverse()*at(shared_point),back_body.polygon), "Shared click actually intersects both tall container pick shapes")
		await mouse(at(shared_point),true)
		check(controller.is_dragging() and controller.current_drag_node == front, "Shared real click selects the visible front source when front-placed-last is %s" % front_last)
		await tap(KEY_ESCAPE)
		await mouse(at(shared_point),false)
		check(not controller.is_dragging() and world.to_local(front.global_position).is_equal_approx(Vector2(1613,950)) and world.to_local(back.global_position).is_equal_approx(Vector2(1587,910)), "Overlap-pick cancellation preserves both source placements")
		await place_overlap_fixture(front,front_origin)
		await place_overlap_fixture(back,back_origin)
		check(front.get_parent() == rail and back.get_parent() == rail and front.transform.is_equal_approx(front_transform) and back.transform.is_equal_approx(back_transform), "Both overlapping sources return to exact authored owners and transforms")

func verify_tray_source_picking(rail: Node, tray: TrayStation) -> void:
	var source := rail.get_node("SugarCan") as Node2D
	var source_start := world.to_local(source.global_position)
	var tray_start := world.to_local(tray.global_position)
	var source_transform := source.transform
	var tray_transform := tray.transform
	var source_handle := source.get_node("PlacementHandle") as TablePlaceable
	var tray_handle := tray.get_node("PlacementHandle") as TablePlaceable
	var shared_point := Vector2(1280,956)
	for source_last in [true,false]:
		var records := [[tray,tray_start],[source,Vector2(1290,950)]] if source_last else [[source,Vector2(1290,950)],[tray,tray_start]]
		for record in records:
			await place_overlap_fixture(record[0] as Node2D,record[1])
		var source_base := source_handle.surface.get_candidate_polygons(source)[0]
		var tray_base := tray_handle.surface.get_candidate_polygons(tray)[0]
		check(Geometry2D.intersect_polygons(source_base,tray_base).is_empty(), "Source base below tray remains physically separate despite tall-art overlap")
		var source_body := source.get_node("PlacementBody/CollisionPolygon2D") as CollisionPolygon2D
		var tray_body := tray.get_node("TrayBody/CollisionShape2D") as CollisionShape2D
		var tray_shape := tray_body.shape as ConvexPolygonShape2D
		check(Geometry2D.is_point_in_polygon(source_body.get_global_transform_with_canvas().affine_inverse()*at(shared_point),source_body.polygon) and Geometry2D.is_point_in_polygon(tray_body.get_global_transform_with_canvas().affine_inverse()*at(shared_point),tray_shape.points), "Tray/source regression actually clicks both authored hit shapes")
		await mouse(at(shared_point),true)
		check(controller.is_dragging() and controller.current_drag_node == source, "Visible source wins shared tray click when source-placed-last is %s" % source_last)
		await tap(KEY_ESCAPE)
		await mouse(at(shared_point),false)
		check(not controller.is_dragging() and world.to_local(source.global_position).is_equal_approx(Vector2(1290,950)) and tray.transform.is_equal_approx(tray_transform), "Tray/source cancellation preserves both placements")
		await place_overlap_fixture(source,source_start)
		check(source.get_parent() == rail and source.transform.is_equal_approx(source_transform) and tray.transform.is_equal_approx(tray_transform), "Tray/source overlap test restores exact scene poses")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run table_placement_input_test.gd with a window for physics pointer picking; use table_placement_test.gd headlessly.")
		quit(2)
		return
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	world = preview.screen.get_node("WorldRoot")
	controller = preview.controller
	var captures := OS.get_cmdline_user_args()
	if captures.size() > 0:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[0]) == OK, "Initial placement review capture saved")
	var tray := preview.screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	var rail: Node = preview.screen.get_node("WorldRoot/ToolLayer/ReadyItemRail")
	var tea := rail.get_node("TeaBox") as Node2D
	var tea_start := world.to_local(tea.global_position)
	await mouse(at(tea_start),true)
	check(not controller.is_dragging(), "Neutral does not arrange or extract from source containers")
	await mouse(at(tea_start),false)
	await tap(KEY_G)
	check(controller.current_mode == InteractionController.MODE_ORGANIZE, "Real G selects existing Organize mode")
	var hud := preview.screen.get_node("HUDLayer/RootUI") as TongHud
	check(hud.current_mode == controller.current_mode and hud.organize_mode_label.modulate == TongHud.ACTIVE_MODE_COLOR, "Visible mode indicator highlights Organize")
	await arrange(tea,Vector2(940.375,800.625),"Tea box",Vector2(12,-5))
	var tea_placed := tea.transform
	await mouse(tea.get_global_transform_with_canvas().origin,true)
	await mouse(at(Vector2(350,850)),false)
	check(tea.transform.is_equal_approx(tea_placed), "Real invalid stove drop restores tea")
	await mouse(tea.get_global_transform_with_canvas().origin,true)
	await move_pointer(at(Vector2(980,820)))
	await tap(KEY_ESCAPE)
	check(not controller.is_dragging() and tea.transform.is_equal_approx(tea_placed), "Real Escape cancels arrangement exactly")
	await mouse(at(Vector2(980,820)),false)
	await mouse(tea.get_global_transform_with_canvas().origin,true)
	await tap(KEY_R)
	check(tea.global_rotation == 0.0, "Real R does not introduce unapproved rotation")
	await tap(KEY_G)
	check(not controller.is_dragging() and tea.transform.is_equal_approx(tea_placed), "Real mode switch cancels arrangement")
	await mouse(at(Vector2(980,820)),false)
	await tap(KEY_G)
	await arrange(tea,tea_start,"Tea restored")
	var names := ["SugarCan","SugarCanEnglish","CondensedMilkCan"]
	var targets := [Vector2(840.125,979.375),Vector2(930.375,985.125),Vector2(1020.625,990.875)]
	for index in names.size():
		var item := rail.get_node(names[index]) as Node2D
		var start := world.to_local(item.global_position)
		await arrange(item,targets[index],names[index])
		await arrange(item,start,names[index]+" restored")
	await verify_overlap_picking(rail)
	await verify_tray_source_picking(rail,tray)
	var cup_snapshots: Array[Dictionary] = []
	for child in tray.get_cups():
		var cup := child as Cup
		cup_snapshots.append({"cup":cup,"transform":cup.transform,"zone":cup.get_node("PourTarget")})
	var tray_start := world.to_local(tray.global_position)
	# The middle now contains genuinely pickable free cups in Organize. Grip the
	# exposed lower rim so this regression moves the tray, not its front cup.
	var tray_grip := Vector2(0,65)
	await arrange(tray,Vector2(1251.125,936.625),"Populated tray",tray_grip)
	for snapshot in cup_snapshots:
		var cup := snapshot.cup as Cup
		check(cup.get_parent() == tray.get_contents() and cup.transform.is_equal_approx(snapshot.transform) and cup.get_node("PourTarget") == snapshot.zone, "%s keeps owner, local pose and pour target while tray moves" % cup.name)
	var tray_placed := tray.transform
	await mouse(at(world.to_local(tray.global_position)+tray_grip),true)
	check(controller.current_drag_node == tray,"Exposed-rim pickup selects tray for invalid populated drop")
	await mouse(at(Vector2(450,850)+tray_grip),false)
	check(tray.transform.is_equal_approx(tray_placed), "Real invalid populated-tray drop restores origin")
	await arrange(tray,Vector2(1000,875),"Tray covering water utility",tray_grip)
	var drum := preview.screen.get_node("WorldRoot/ToolLayer/WaterDrum") as WaterDrum
	var drum_at := drum.get_global_transform_with_canvas().origin
	var utility_hits_cup := false
	for utility_cup in tray.get_cups():
		var cup_handle := utility_cup.get_node("PlacementHandle") as TablePlaceable
		utility_hits_cup = utility_hits_cup or cup_handle._contains_pointer(drum_at)
	check((tray.get_node("PlacementHandle") as TablePlaceable)._contains_pointer(drum_at) and not utility_hits_cup,"Water passthrough fixture covers an exposed tray area rather than a cup")
	await mouse(drum_at,true)
	check(controller.current_drag_node == tray, "Organize click passes through water utility to covered tray")
	await tap(KEY_ESCAPE)
	await mouse(drum_at,false)
	await tap(KEY_U)
	var kettle := preview.kettle as Kettle
	var source_before: float = root.get_node("GameState").water_supply.remaining_ml
	await mouse(drum_at,true)
	check(controller.current_drag_node == drum, "Interact picks water above an overlapping tray")
	await mouse(kettle.get_node("WaterFillTarget").get_global_transform_with_canvas().origin,false)
	check(kettle.volume_ml == 1500.0 and root.get_node("GameState").water_supply.remaining_ml == source_before-1500.0, "Covered water utility still fills conservatively")
	check(drum.get_global_transform_with_canvas().origin.is_equal_approx(drum_at), "Water utility returns to its fixed accessible origin")
	await tap(KEY_G)
	await arrange(tray,Vector2(1550,930),"Tray covering discard utility",tray_grip)
	await tap(KEY_U)
	kettle.apply_heat(10,1)
	kettle.add_tea_leaves()
	kettle.advance_brewing(kettle.config.steep_seconds)
	var cup := tray.get_cups()[0] as Cup
	await mouse(kettle.get_node("GripAnchor").get_global_transform_with_canvas().origin,true)
	await move_pointer(aim(kettle,cup))
	check(controller.hovered_drop_zone == cup.get_node("PourTarget"), "Moved cup remains selected from visible spout")
	await key(KEY_SPACE,true)
	await create_timer(.15).timeout
	await key(KEY_SPACE,false)
	check(cup.volume_ml > 0.0, "Real held Space pours into the relocated tray cup")
	await mouse(aim(kettle,cup),false)
	check(not controller.is_dragging() and not kettle.is_held, "Pour release safely returns kettle after tray relocation")
	var cup_origin := cup.transform
	var discarded := preview.screen.get_node("WorldRoot/DropZoneRoot/DiscardArea") as DiscardDropZone
	await mouse(cup.get_global_transform_with_canvas().origin,true)
	check(controller.current_drag_node == cup, "Relocated cup still supports its existing drag lifecycle")
	await mouse(discarded.get_global_transform_with_canvas().origin,false)
	check(cup.volume_ml == 0.0 and cup.get_parent() == tray.get_contents() and cup.transform.is_equal_approx(cup_origin), "Discard above overlapping tray empties and restores the same cup")
	await mouse(cup.get_global_transform_with_canvas().origin,true)
	await mouse(at(Vector2(900,600)),false)
	check(cup.get_parent() == tray.get_contents() and cup.transform.is_equal_approx(cup_origin), "Invalid Interact release preserves cup ownership and placement")
	await tap(KEY_G)
	await arrange(tray,tray_start,"Tray restored after utility regressions",tray_grip)
	await tap(KEY_G)
	var reset_at: Vector2 = preview.reset_button.get_global_rect().get_center()
	await mouse(reset_at,true)
	await mouse(reset_at,false)
	check(kettle.volume_ml == 0.0 and root.get_node("GameState").water_supply.remaining_ml == 3000.0, "Real preview reset still starts the empty-kettle fixture day")
	check(hud.current_mode == InteractionController.MODE_NEUTRAL and hud.interact_mode_label.modulate == TongHud.INACTIVE_MODE_COLOR and hud.organize_mode_label.modulate == TongHud.INACTIVE_MODE_COLOR, "Preview reset visibly returns to Neutral")
	check(tray.get_cup_count() == 6 and preview.screen.get_cups().size() == 6, "Placement never loses or duplicates starting cup ownership")
	for child in tray.get_cups():
		check((child as Cup).volume_ml == 0.0, "Reset reaches %s after placement, pouring and discard" % child.name)
	if captures.size() > 1:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[1]) == OK, "Completed placement review capture saved")
	if captures.size() > 2:
		await tap(KEY_G)
		var offset := tray_grip
		await mouse(at(world.to_local(tray.global_position)+offset),true)
		await move_pointer(at(Vector2(1221.125,931.625)+offset))
		check(controller.current_drag_node == tray and controller.hovered_drop_zone != null and controller.hovered_drop_zone.accepts(controller.current_payload).is_valid, "Green review capture shows a valid free populated-tray candidate")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures[2]) == OK, "Valid green placement preview capture saved")
		if captures.size() > 3:
			await move_pointer(at(Vector2(450,850)+offset))
			check(controller.current_drag_node == tray and controller.hovered_drop_zone != null and not controller.hovered_drop_zone.accepts(controller.current_payload).is_valid, "Red review capture shows a stove-blocked candidate")
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(captures[3]) == OK, "Invalid red placement preview capture saved")
		await tap(KEY_ESCAPE)
		await mouse(at(tray_start+offset),false)
		check(world.to_local(tray.global_position).is_equal_approx(tray_start), "Preview captures leave the accepted tray placement intact")
	preview.queue_free()
	await process_frame
	print("TABLE_PLACEMENT_INPUT: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
