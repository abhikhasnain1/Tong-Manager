extends SceneTree

# Production-scene integration for continuous table placement and safe lifecycle.
class ExitAction:
	extends Node
	func cancel_action() -> void:
		pass

var expected_table := PackedVector2Array([Vector2(0,710), Vector2(260,710), Vector2(330,730), Vector2(450,716), Vector2(620,742), Vector2(790,742), Vector2(850,734), Vector2(1090,719), Vector2(1195,716), Vector2(1240,726), Vector2(1400,726), Vector2(1500,709), Vector2(1640,709), Vector2(1740,706), Vector2(1920,700), Vector2(1920,1080), Vector2(0,1080)])
var expected_stove := PackedVector2Array([Vector2(115,774), Vector2(615,774), Vector2(640,793), Vector2(760,1059), Vector2(742,1079), Vector2(3,1079), Vector2(3,989), Vector2(95,784)])
var failures: Array[String] = []
var checks := 0
var preview: Node
var screen: Node2D
var world: Node2D
var surface: PlacementSurface
var controller: InteractionController
var drop_events := 0
var cancel_events := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func on_drop(_payload: HeldItemPayload, _zone: DropZone) -> void:
	drop_events += 1

func on_cancel(_payload: HeldItemPayload) -> void:
	cancel_events += 1

func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds

func same_polygons(first: Array[PackedVector2Array], second: Array[PackedVector2Array]) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if first[index].size() != second[index].size():
			return false
		for vertex in first[index].size():
			if not first[index][vertex].is_equal_approx(second[index][vertex]):
				return false
	return true

func viewport_point(authored: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas() * authored

func move_handle(handle: TablePlaceable, target: Vector2, click_offset := Vector2.ZERO) -> bool:
	var pointer := handle.item.get_global_transform_with_canvas().origin + click_offset
	if not handle.begin_drag(pointer):
		return false
	controller.update_drag(viewport_point(target) + click_offset)
	return true

func commit_move(handle: TablePlaceable, target: Vector2, label: String, offset := Vector2.ZERO) -> void:
	var item := handle.item
	var parent := item.get_parent()
	var basis := item.transform
	check(move_handle(handle, target, offset), "%s starts whole-object drag" % label)
	check(surface.validate_item(item).is_valid, "%s has a valid continuous candidate" % label)
	controller.release_drop(viewport_point(target) + offset)
	check(not controller.is_dragging() and item.get_parent() == parent, "%s commits to its original owner" % label)
	check(world.to_local(item.global_position).is_equal_approx(target), "%s preserves the unsnapped pointer position" % label)
	check(item.transform.x.is_equal_approx(basis.x) and item.transform.y.is_equal_approx(basis.y), "%s preserves scale and rotation" % label)
	check(same_polygons(surface.get_committed_polygons(item), surface.get_candidate_polygons(item)), "%s commits the same physical footprint" % label)

func invalid_move(handle: TablePlaceable, target: Vector2, reason: String) -> void:
	var item := handle.item
	var parent := item.get_parent()
	var transform := item.transform
	var committed := surface.get_committed_polygons(item)
	check(move_handle(handle, target), "%s test starts a drag" % reason)
	check(not surface.validate_item(item).is_valid, "%s candidate is rejected" % reason)
	controller.release_drop(viewport_point(target))
	check(not controller.is_dragging() and item.get_parent() == parent and item.transform.is_equal_approx(transform), "%s release restores exact ownership and transform" % reason)
	check(same_polygons(committed, surface.get_committed_polygons(item)), "%s release preserves reservation" % reason)

func run() -> void:
	root.size = Vector2i(1920,1080)
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	screen = preview.screen
	world = screen.get_node("WorldRoot")
	surface = screen.table_surface
	controller = preview.controller
	controller.drag_dropped.connect(on_drop)
	controller.drag_canceled.connect(on_cancel)
	check(surface.usable_polygon == expected_table, "Table follows the approved full-table outline without a far-side lockout")
	check((surface.get_node("Exclusions/Stove") as Polygon2D).polygon == expected_stove, "Stove exclusion follows approved geometry")
	check(surface.get_node("Exclusions").get_child_count() == 1, "No extra exclusion or hidden utility parking rule is introduced")
	check(screen.get_node_or_null("WorldRoot/DropZoneRoot/TableGrid") == null, "Production table has no legacy grid node")
	check(root.physics_object_picking_sort, "Utility picking sorts visible object priority")
	var rail := screen.get_node("WorldRoot/ToolLayer/ReadyItemRail")
	var handles: Array[TablePlaceable] = []
	var approved_bases := [Rect2(1470.512,732.32,129.408,79.296),Rect2(1604.456,768.62,72.96,25.08),Rect2(1732.136,768.62,72.96,25.08),Rect2(1662.4,792.94,72.72,22.68)]
	for name in ["TeaBox", "SugarCan", "SugarCanEnglish", "CondensedMilkCan"]:
		var handle := rail.get_node(String(name) + "/PlacementHandle") as TablePlaceable
		handles.append(handle)
		check(handle.surface == surface and surface.is_registered(handle.item), "%s begins with valid authored ownership" % name)
		var bounds := polygon_bounds(surface.get_committed_polygons(handle.item)[0])
		var expected: Rect2 = approved_bases[handles.size()-1]
		check(bounds.position.distance_to(expected.position) < .02 and bounds.size.distance_to(expected.size) < .02, "%s retains the visually approved base size and offset" % name)
		check(not handle.begin_drag(handle.item.get_global_transform_with_canvas().origin), "%s does not arrange in Interact mode" % name)
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	var tray_handle := tray.get_node("PlacementHandle") as TablePlaceable
	check(surface.is_registered(tray) and tray.get_cup_count() == 6, "Populated tray begins registered with existing supply")
	check(tray.get_node_or_null("InternalGrid") == null and tray.get_node_or_null("InteriorSurface") is PlacementSurface, "Tray retains a continuous interior instead of legacy slots")
	check(not surface.is_registered(preview.kettle), "Kettle retains special burner seating, not table parking")
	check(not surface.is_registered(screen.get_node("WorldRoot/ToolLayer/WaterDrum")), "Water remains a utility source, not an ordinary placeable")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	var tea := handles[0]
	var tea_start := world.to_local(tea.item.global_position)
	var tea_parent := tea.item.get_parent()
	var tea_transform := tea.item.transform
	var old_reservation := surface.get_committed_polygons(tea.item)
	var tea_target := Vector2(940.375,800.625)
	check(move_handle(tea, tea_target, Vector2(13,-7)), "Offset pickup starts without snapping")
	check(world.to_local(tea.item.global_position).is_equal_approx(tea_target), "Pointer-to-object offset survives reparenting")
	check(same_polygons(old_reservation, surface.get_committed_polygons(tea.item)), "Dragging does not prematurely release committed space")
	controller.action_requested.emit(InteractionController.INPUT_ROTATE_ITEM)
	check(tea.item.global_rotation == 0.0, "Unapproved rotate action does not rotate table objects")
	controller.cancel_drag()
	check(tea.item.get_parent() == tea_parent and tea.item.transform.is_equal_approx(tea_transform), "Cancellation restores exact source transform")
	check(same_polygons(old_reservation, surface.get_committed_polygons(tea.item)), "Cancellation leaves the committed footprint unchanged")
	commit_move(tea, tea_target, "Tea box", Vector2(13,-7))
	invalid_move(tea, Vector2(-50,800), "Outside table")
	invalid_move(tea, Vector2(350,850), "Stove overlap")
	invalid_move(tea, Vector2(1259,875), "Peer tray overlap")
	for test_mode in ["mode", "focus"]:
		var before := tea.item.transform
		check(move_handle(tea, tea_target + Vector2(11.25,6.5)), "%s cancellation starts" % test_mode)
		if test_mode == "mode":
			controller.set_mode(InteractionController.MODE_INTERACT)
		else:
			controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		check(not controller.is_dragging() and tea.item.transform.is_equal_approx(before), "%s restores source without committing" % test_mode)
		controller.set_mode(InteractionController.MODE_ORGANIZE)
	commit_move(tea, tea_start, "Tea restored")
	var destinations := [Vector2(840.125,979.375), Vector2(930.375,985.125), Vector2(1020.625,990.875)]
	for index in range(1,handles.size()):
		var handle := handles[index]
		var start := world.to_local(handle.item.global_position)
		commit_move(handle, destinations[index-1], String(handle.item.name), Vector2(-5,8))
		commit_move(handle, start, String(handle.item.name) + " restored")
	var cup_snapshots: Array[Dictionary] = []
	for child in tray.get_cups():
		var cup := child as Cup
		cup.set_process(false)
		cup.receive_liquid(&"black_tea", 90.0 + cup_snapshots.size(), 72.0)
		cup.assigned_order_id = &"placement_fixture"
		cup_snapshots.append({"cup":cup, "transform":cup.transform, "volume":cup.volume_ml, "temperature":cup.temperature, "zone":cup.get_node("PourTarget")})
	var tray_start := world.to_local(tray.global_position)
	commit_move(tray_handle, Vector2(1251.125,936.625), "Populated tray", Vector2(80,20))
	for snapshot in cup_snapshots:
		var cup := snapshot.cup as Cup
		check(cup.get_parent() == tray.get_contents() and cup.transform.is_equal_approx(snapshot.transform), "%s retains identity, owner and child-local pose" % cup.name)
		check(cup.volume_ml == snapshot.volume and cup.temperature == snapshot.temperature and cup.assigned_order_id == &"placement_fixture", "%s retains liquid, thermal and order data" % cup.name)
		check(cup.get_node("PourTarget") == snapshot.zone and controller._get_available_drop_zones().has(snapshot.zone), "%s retains the registered live pour target" % cup.name)
	commit_move(tray_handle, tray_start, "Tray restored")
	var peer := Node2D.new()
	world.add_child(peer)
	peer.position = Vector2(920,950)
	var peer_shapes: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-10,-10),Vector2(10,-10),Vector2(10,10),Vector2(-10,10)])]
	check(surface.register_item(peer, peer_shapes), "Temporary live peer reserves valid table space")
	check(move_handle(tea, Vector2(900,910)), "Dynamic-peer test starts a candidate")
	check(not surface.validate_item(tea.item).is_valid, "Live peer blocks a colliding candidate")
	peer.queue_free()
	check(surface.validate_item(tea.item).is_valid, "Queued-for-deletion peer cannot leave a ghost reservation")
	controller.cancel_drag()
	await process_frame
	var committed_before_resize := surface.get_committed_polygons(tray)
	for dimensions in [Vector2i(1600,900),Vector2i(1366,768),Vector2i(1280,800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(surface.validate_item(tray).is_valid and same_polygons(committed_before_resize,surface.get_candidate_polygons(tray)), "Viewport %s preserves authored geometry" % dimensions)
		var before := tea.item.transform
		check(move_handle(tea, tea_target, Vector2(9,4)), "Viewport %s retains offset pickup" % dimensions)
		check(world.to_local(tea.item.global_position).is_equal_approx(tea_target), "Viewport %s previews continuous authored positions" % dimensions)
		controller.cancel_drag()
		check(tea.item.transform.is_equal_approx(before), "Viewport %s cancellation restores local transform" % dimensions)
	check(move_handle(tea,Vector2(1830,950)), "Narrow-viewport edge candidate starts")
	check(surface.validate_item(tea.item).is_valid, "Cropped-edge candidate is geometrically inside authored table")
	check(not tea.validate_placement().is_valid, "Narrow viewport prevents committing an unreachable cropped base")
	controller.release_drop(viewport_point(Vector2(1830,950)))
	check(world.to_local(tea.item.global_position).is_equal_approx(tea_start), "Cropped-edge release restores reachable origin")
	check(move_handle(tea, tea_target), "Resize-during-drag fixture starts")
	root.size = Vector2i(1920,1080)
	await process_frame
	check(not controller.is_dragging(), "Viewport resize cancels an active drag before changing coordinates")
	controller.cancel_drag()
	check(tea.item.get_parent() == tea_parent and world.to_local(tea.item.global_position).is_equal_approx(tea_start), "Resize then cancellation preserves source ownership and authored origin")
	# The candidate is valid, but its former scene owner disappears before the
	# release. This specifically exercises try_apply_drop failure after accepts.
	var home := Node2D.new()
	world.add_child(home)
	var temporary := Node2D.new()
	temporary.name = "RemovedOwnerFixture"
	temporary.position = Vector2(925,1030)
	home.add_child(temporary)
	var temporary_handle := TablePlaceable.new()
	temporary_handle.footprint = PackedVector2Array([Vector2(-8,-6),Vector2(8,-6),Vector2(8,6),Vector2(-8,6)])
	temporary.add_child(temporary_handle)
	check(temporary_handle.configure(surface,controller), "Removed-owner fixture starts with a valid reservation")
	var origin := temporary.transform
	var reservation := surface.get_committed_polygons(temporary)
	check(move_handle(temporary_handle,Vector2(950,1020)), "Removed-owner fixture starts a valid candidate")
	world.remove_child(home)
	drop_events = 0
	cancel_events = 0
	controller.release_drop(viewport_point(Vector2(950,1020)))
	check(not controller.is_dragging() and drop_events == 0 and cancel_events == 1, "Failed commit emits cancellation and never a false successful drop")
	check(temporary.get_parent() == home and temporary.transform.is_equal_approx(origin), "Failed commit restores original ownership and transform")
	check(not temporary.is_inside_tree() and not surface.is_registered(temporary), "Detached owner cannot retain a live table reservation")
	check(not reservation.is_empty(), "Removed-owner fixture exercised an existing reservation")
	home.free()
	preview.reset_fixture()
	for snapshot in cup_snapshots:
		check((snapshot.cup as Cup).volume_ml == 0.0, "Preview reset still reaches %s after tray relocation" % (snapshot.cup as Cup).name)
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(move_handle(tea,Vector2(350,850)), "Scene-exit regression starts an invalid table drag")
	var exit_zone := controller.hovered_drop_zone
	var held_parent := tea.item.get_parent()
	var held_transform := tea.item.transform
	var cursor := root.get_node("CursorService")
	check(exit_zone != null and bool(exit_zone.get("_highlighted")) and cursor.current_state == &"invalid", "Scene exit begins with a visible invalid highlight and cursor")
	Input.action_press(InteractionController.INPUT_POUR)
	drop_events = 0
	root.remove_child(preview)
	check(controller.current_payload == null and controller.current_drag_node == null and not controller.is_dragging(), "Scene exit clears active drag references")
	check(controller.action_owner == null and controller.hovered_drop_zone == null, "Scene exit clears action and highlighted-target ownership")
	check(not bool(exit_zone.get("_highlighted")), "Scene exit clears the retained drop highlight")
	check(cursor.current_state == &"default" and not Input.is_action_pressed(InteractionController.INPUT_POUR), "Scene exit resets the persistent cursor and held pour input")
	check(tea.item.get_parent() == held_parent and tea.item.transform.is_equal_approx(held_transform), "Scene teardown does not reparent or restore a node through an exiting hierarchy")
	check(drop_events == 0, "Scene exit never emits a successful placement")
	preview.free()
	cup_snapshots.clear()
	# Controller removal also clears a live action lock when its host remains.
	var exit_host := Node2D.new()
	var drag_layer := Node2D.new()
	drag_layer.name = "DragLayer"
	exit_host.add_child(drag_layer)
	var zone_root := Node2D.new()
	zone_root.name = "DropZoneRoot"
	exit_host.add_child(zone_root)
	var exit_controller := InteractionController.new()
	exit_controller.drag_layer_path = NodePath("../DragLayer")
	exit_controller.drop_zone_root_path = NodePath("../DropZoneRoot")
	exit_host.add_child(exit_controller)
	var exit_action := ExitAction.new()
	exit_host.add_child(exit_action)
	root.add_child(exit_host)
	exit_controller.set_mode(InteractionController.MODE_INTERACT)
	check(exit_controller.lock_action(exit_action), "Controller-exit regression owns a live action")
	cursor.set_state(&"hover_actionable")
	Input.action_press(InteractionController.INPUT_POUR)
	exit_host.remove_child(exit_controller)
	check(not exit_controller.has_active_action() and exit_controller.action_owner == null, "Controller exit clears its live action lock")
	check(exit_controller.current_payload == null and exit_controller.current_drag_node == null and exit_controller.hovered_drop_zone == null, "Controller exit leaves no drag or target references")
	check(cursor.current_state == &"default" and not Input.is_action_pressed(InteractionController.INPUT_POUR), "Controller exit clears global cursor and input state")
	check(exit_action.get_parent() == exit_host and exit_action.is_inside_tree(), "Controller cleanup does not move its surviving action owner")
	exit_controller.free()
	exit_host.queue_free()
	await process_frame
	print("TABLE_PLACEMENT: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
