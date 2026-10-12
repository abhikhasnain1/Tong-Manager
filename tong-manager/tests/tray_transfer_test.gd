extends SceneTree

# Controller-level integration for free contents and atomic table/tray ownership.
var failures: Array[String] = []
var checks := 0
var preview: Node
var screen: Node2D
var world: Node2D
var controller: InteractionController
var table: PlacementSurface
var interior: PlacementSurface
var tray: TrayStation
var rail: Node2D
var dropped := 0

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
	if polygons.is_empty():
		return world.to_local(item.global_position)
	var bounds := Rect2(polygons[0][0], Vector2.ZERO)
	for polygon in polygons:
		for point in polygon:
			bounds = bounds.expand(point)
	return world.to_local(handle.surface.to_global(bounds.get_center()))

func begin_at_base(item: Node2D, target: Vector2, grip := Vector2.ZERO) -> Vector2:
	var destination := world.to_local(item.global_position) + target - base_center(item)
	check(handle_for(item).begin_drag(item.get_global_transform_with_canvas().origin + grip), "%s begins arrangement through its real handle" % item.name)
	controller.update_drag(at(destination) + grip)
	return at(destination) + grip

func transfer(item: Node2D, target: Vector2, destination: PlacementSurface, label: String) -> void:
	var handle := handle_for(item)
	var previous_surface := handle.surface
	var before := item.global_transform
	var pointer := begin_at_base(item, target, Vector2(7, -4))
	check(handle.validate_placement().is_valid, "%s previews a supported unoccupied base" % label)
	check(previous_surface.is_registered(item), "%s retains its source reservation until release" % label)
	controller.release_drop(pointer)
	check(not controller.is_dragging() and handle.surface == destination and destination.is_registered(item), "%s commits one destination owner" % label)
	check(base_center(item).distance_to(target) < .002, "%s keeps its exact continuous base position" % label)
	check(item.global_transform.x.is_equal_approx(before.x) and item.global_transform.y.is_equal_approx(before.y), "%s retains world size and orientation through nonuniform parents" % label)
	if previous_surface != destination:
		check(not previous_surface.is_registered(item), "%s releases its previous reservation only after success" % label)
	var expected_parent: Node = tray.get_contents() if destination == interior else rail
	if item == tray:
		expected_parent = world.get_node("ToolLayer")
	check(item.get_parent() == expected_parent, "%s has the corresponding physical content parent" % label)

func reject(item: Node2D, target: Vector2, label: String) -> void:
	var handle := handle_for(item)
	var owner := handle.surface
	var parent := item.get_parent()
	var local_pose := item.transform
	var original_base := base_center(item)
	var pointer := begin_at_base(item, target)
	check(not handle.validate_placement().is_valid, "%s shows an invalid candidate" % label)
	var before_drops := dropped
	controller.release_drop(pointer)
	check(not controller.is_dragging() and handle.surface == owner and owner.is_registered(item), "%s preserves its original surface" % label)
	check(item.get_parent() == parent and item.transform.is_equal_approx(local_pose) and base_center(item).distance_to(original_base) < .002, "%s restores its exact parent and pose" % label)
	check(dropped == before_drops, "%s emits no successful placement" % label)

func cup_snapshot(cup: Cup) -> Dictionary:
	return {"volume":cup.volume_ml, "temperature":cup.temperature, "liquid":cup.liquid_type, "base":cup.contents_base_id, "garnishes":cup.relish_item_ids.duplicate(), "order":cup.assigned_order_id, "state":cup.state, "target":cup.get_node("PourTarget")}

func check_cup(cup: Cup, snapshot: Dictionary, label: String) -> void:
	check(cup.volume_ml == snapshot.volume and cup.temperature == snapshot.temperature and cup.liquid_type == snapshot.liquid and cup.contents_base_id == snapshot.base, "%s preserves liquid and thermal data" % label)
	check(cup.relish_item_ids == snapshot.garnishes and cup.assigned_order_id == snapshot.order and cup.state == snapshot.state, "%s preserves ingredients, order and lifecycle" % label)
	check(cup.get_node("PourTarget") == snapshot.target and controller._get_available_drop_zones().has(snapshot.target), "%s preserves its live identity-bound pour target" % label)

func run() -> void:
	root.size = Vector2i(1920,1080)
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	screen = preview.screen
	world = screen.get_node("WorldRoot")
	controller = preview.controller
	table = screen.table_surface
	tray = screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	interior = tray.get_node("InteriorSurface") as PlacementSurface
	rail = screen.get_node("WorldRoot/ToolLayer/ReadyItemRail") as Node2D
	controller.drag_dropped.connect(func(_payload: HeldItemPayload, _zone: DropZone): dropped += 1)
	check(tray.get_node_or_null("InternalGrid") == null and tray.get_node_or_null("InternalDropZone") == null, "Tray has no grid or slot drop adapter")
	check(interior.usable_polygon == PackedVector2Array([Vector2(-206,-97),Vector2(206,-100),Vector2(265,77),Vector2(-265,77)]), "Tray uses the approved independent usable polygon")
	var cups: Array[Cup] = tray.get_cups()
	check(cups.size() == 6 and screen.get_cups().size() == 6, "Configured starting supply creates six distinct cups")
	var initial_bases: Array[Vector2] = []
	var initial_poses: Array[Transform2D] = []
	var snapshots: Array[Dictionary] = []
	var approved_bases := [Vector2(1147.552,883.55),Vector2(1259.399,883.04),Vector2(1371.246,882.53),Vector2(1132.606,942.88),Vector2(1259.399,942.71),Vector2(1386.192,942.54)]
	for index in cups.size():
		var cup := cups[index]
		cup.set_process(false)
		var liquid_overlay := cup.get_node("ContentsOverlay") as Sprite2D
		var cup_body := cup.get_node("Sprite2D") as Sprite2D
		check(liquid_overlay.z_as_relative and cup_body.z_as_relative and liquid_overlay.z_index == cup_body.z_index, "%s liquid shares body depth so a rear cup cannot draw over a front object" % cup.name)
		initial_bases.append(base_center(cup))
		initial_poses.append(cup.transform)
		check(base_center(cup).distance_to(approved_bases[index]) < .03, "%s retains its approved starting artwork pose" % cup.name)
		check(handle_for(cup).surface == interior and interior.is_registered(cup) and not table.is_registered(cup), "%s starts with exactly one tray reservation" % cup.name)
		check(not handle_for(cup).begin_drag(cup.get_global_transform_with_canvas().origin), "%s cannot rearrange in Interact" % cup.name)
		if index > 0:
			cup.receive_liquid(&"black_tea", 70.0 + index, 61.0 + index)
			cup.assigned_order_id = StringName("transfer_%d" % index)
		if index == 2:
			cup.add_relish(&"sugar")
		if index == 3 or index == 4:
			cup.mark_served()
		if index == 4:
			cup.mark_dirty()
		snapshots.append(cup_snapshot(cup))
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	for index in cups.size():
		transfer(cups[index], Vector2(825 + 55 * (index % 3), 835 + 120 * (index / 3)), table, "%s tray to table" % cups[index].name)
		check_cup(cups[index], snapshots[index], String(cups[index].name))
	check(tray.get_cup_count() == 0 and screen.get_cups().size() == 6, "All transferred cups remain discoverable outside the tray")
	var sources: Array[Node2D] = []
	var source_bases: Array[Vector2] = []
	for source_name in ["TeaBox","SugarCan","SugarCanEnglish","CondensedMilkCan"]:
		var source := rail.get_node(String(source_name)) as Node2D
		sources.append(source)
		source_bases.append(base_center(source))
		transfer(source, Vector2(1259.125,889.375), interior, "%s table to tray" % source_name)
		transfer(source, source_bases.back(), table, "%s tray to table" % source_name)
	# Both kinds of content travel with the tray, while table-owned cups do not.
	transfer(cups[0],Vector2(1130,926),interior,"Cup joins mixed tray")
	transfer(sources[0],Vector2(1270,875),interior,"Tea joins mixed tray")
	transfer(sources[1],Vector2(1390,925),interior,"Sugar joins mixed tray")
	var carried: Array[Node2D] = [cups[0],sources[0],sources[1]]
	var local_poses: Array[Transform2D] = []
	for item in carried:
		local_poses.append(item.transform)
	var stationary_pose := cups[1].global_transform
	var tray_center := base_center(tray)
	transfer(tray,tray_center + Vector2(-8.125,29.375),table,"Mixed populated tray")
	for index in carried.size():
		check(carried[index].get_parent() == tray.get_contents() and carried[index].transform.is_equal_approx(local_poses[index]), "%s travels with exact tray-local pose" % carried[index].name)
		check(interior.is_registered(carried[index]) and not table.is_registered(carried[index]), "%s never becomes a table collision peer of its own tray" % carried[index].name)
	check(cups[1].global_transform.is_equal_approx(stationary_pose), "Moving tray leaves a table-owned cup still")
	transfer(tray,tray_center,table,"Mixed tray restored")
	transfer(sources[0],source_bases[0],table,"Tea leaves mixed tray")
	transfer(sources[1],source_bases[1],table,"Sugar leaves mixed tray")
	for index in cups.size():
		transfer(cups[index],initial_bases[index],interior,"%s table to tray" % cups[index].name)
		check_cup(cups[index],snapshots[index],"%s round trip" % cups[index].name)
		var returned := cups[index].transform
		var original := initial_poses[index]
		check(returned.x.is_equal_approx(original.x) and returned.y.is_equal_approx(original.y) and returned.origin.distance_to(original.origin) < .002, "%s round trip preserves basis and returns within numerical pointer precision" % cups[index].name)
	# Seven objects fit: the former six slot count is not physical capacity.
	transfer(sources[1],Vector2(1200,910),interior,"Seventh object between former rows")
	check(tray.get_contents().get_child_count() >= 7 and tray.get_cup_count() == 6, "A fitting ingredient source does not consume or replace a cup slot")
	reject(cups[0],Vector2(1200,910),"Occupied interior")
	reject(cups[0],Vector2(1259,950),"Base crossing the tray rim")
	reject(cups[0],Vector2(1015,948),"Outer tray rim cannot fall through to table")
	reject(cups[0],Vector2(350,850),"Stove")
	reject(cups[0],Vector2(-20,900),"Outside table")
	transfer(sources[1],source_bases[1],table,"Seventh object restored")
	# Cancellation never releases a source reservation or changes sibling state.
	var cup := cups[1]
	for reason in ["cancel","mode","focus","resize"]:
		var pose := cup.transform
		begin_at_base(cup,Vector2(900,960))
		if reason == "cancel":
			controller.cancel_drag()
		elif reason == "mode":
			controller.set_mode(InteractionController.MODE_INTERACT)
		elif reason == "focus":
			controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		else:
			root.size = Vector2i(1280,800)
			await process_frame
		check(not controller.is_dragging() and cup.get_parent() == tray.get_contents() and cup.transform.is_equal_approx(pose), "%s during transfer restores original parent and pose" % reason)
		check(interior.is_registered(cup) and not table.is_registered(cup), "%s keeps exactly one original reservation" % reason)
		check_cup(cup,snapshots[1],reason)
		controller.set_mode(InteractionController.MODE_ORGANIZE)
		root.size = Vector2i(1920,1080)
		await process_frame
	# Moving a used/served/dirty cup never changes eligibility to receive liquid.
	check(not cups[3].can_receive_liquid(&"black_tea") and not cups[4].can_receive_liquid(&"black_tea"), "Moved served and dirty cups remain unavailable for pouring")
	transfer(cups[0],Vector2(920.375,940.625),table,"Action cup on table")
	cup = cups[0]
	cup.receive_liquid(&"black_tea",170,40)
	var table_pose := cup.transform
	controller.set_mode(InteractionController.MODE_INTERACT)
	check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Table cup starts its real Interact action drag")
	controller.release_drop(at(Vector2(1230,910)))
	check(cup.get_parent() == rail and cup.transform.is_equal_approx(table_pose) and handle_for(cup).surface == table, "Interact release onto tray cannot commit arrangement")
	var discard := screen.get_node("WorldRoot/DropZoneRoot/DiscardArea") as DiscardDropZone
	check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Moved cup can start disposal")
	controller.release_drop(discard.get_global_transform_with_canvas().origin)
	check(cup.volume_ml == 0 and cup.get_parent() == rail and cup.transform.is_equal_approx(table_pose), "Disposal empties the relocated cup and restores its actual table pose")
	cup.receive_liquid(&"black_tea",170,40)
	check(cup.begin_interaction_drag(cup.get_global_transform_with_canvas().origin), "Moved cup can start sample handoff")
	controller.release_drop(preview.service_zone.get_global_transform_with_canvas().origin)
	check(cup.state == Cup.CupState.SERVED and preview.service_zone.review.accepted_count() == 1 and preview.service_zone.review.bad_review_count() == 1, "Moved cold cup remains accepted once with the cold review")
	check(cup.get_parent() == rail and cup.transform.is_equal_approx(table_pose), "Sample handoff returns cup to its actual source surface")
	preview.reset_fixture()
	check(cup.state == Cup.CupState.CLEAN and cup.volume_ml == 0 and cup.get_parent() == rail, "Fixture reset reaches a table-owned cup without moving it")
	cup.receive_liquid(&"black_tea",100,65)
	cup.advance_cooling(2)
	check(cup.temperature < 65 and cup.volume_ml == 100, "Relocated cup cooling remains independent of placement")
	# New cups are configured once and disappear from target/ownership lookup.
	var added := load("res://scenes/gameplay/tools/Cup.tscn").instantiate() as Cup
	added.name = "AdditionalCupFixture"
	rail.add_child(added)
	added.global_transform = cup.global_transform
	added.global_position += world.global_transform.basis_xform(Vector2(70,0))
	check(screen.configure_cup(added), "Dynamic table cup gets placement and action setup")
	await process_frame
	check(screen.get_cups().size() == 7 and table.is_registered(added), "Dynamic cup uses real free surface fit rather than six-cup capacity")
	var added_target := added.get_node("PourTarget")
	var added_target_id := added_target.get_instance_id()
	check(screen.configure_cup(added) and added.get_node("PourTarget") == added_target, "Repeated setup retains one identity-bound target")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	transfer(added,Vector2(1195,910),interior,"Seventh cup transfers to tray")
	var freed_center := base_center(added)
	begin_at_base(added,Vector2(955,1015))
	var before_removed_drop := dropped
	added.queue_free()
	check(not interior.is_registered(added), "Queued deletion releases the removed cup reservation immediately")
	controller.release_drop(at(Vector2(955,995)))
	check(not controller.is_dragging() and dropped == before_removed_drop, "Removed drag source cannot emit a successful transfer or keep a gesture alive")
	await process_frame
	var stale_target := false
	for zone in controller._get_available_drop_zones():
		stale_target = stale_target or zone.get_instance_id() == added_target_id
	check(screen.get_cups().size() == 6 and not stale_target, "Removed cup leaves no discoverable cup or stale action target")
	transfer(cup,freed_center,interior,"Freed destination can be reused")
	# A removed destination cannot acquire ownership on release.
	transfer(cup,Vector2(900,970),table,"Destination-loss fixture")
	var safe_pose := cup.transform
	begin_at_base(cup,Vector2(1200,910))
	tray.remove_child(interior)
	controller.release_drop(at(Vector2(1200,890)))
	check(not controller.is_dragging() and cup.get_parent() == rail and cup.transform.is_equal_approx(safe_pose) and handle_for(cup).surface == table, "Removed destination cannot steal a cup or commit a false transfer")
	tray.add_child(interior)
	preview.queue_free()
	await process_frame
	print("TRAY_TRANSFER: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
