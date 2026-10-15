extends "res://tests/friend_demo_test.gd"
## Resize the same live demo; no replacement scene can conceal stale custody.

var utility_parents: Dictionary = {}
var probe: Node2D
var probe_shape: Array[PackedVector2Array] = [PackedVector2Array([
	Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])]


func utilities() -> Array[Node2D]:
	return [screen.get_node("WorldRoot/ToolLayer/WaterDrum"),
		screen.get_node("WorldRoot/DropZoneRoot/DiscardArea"),
		screen.get_node("WorldRoot/ToolLayer/BucketStation"),
		screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot")]


func utility_sprites() -> Array[Sprite2D]:
	return [screen.get_node("WorldRoot/ToolLayer/WaterDrum/Icon"),
		screen.get_node("WorldRoot/DropZoneRoot/DiscardArea/Basket"),
		screen.get_node("WorldRoot/ToolLayer/BucketStation/Sprite"),
		screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot/Sprite")]


func hover_art_bounds() -> Rect2:
	var result := Rect2()
	var initialized := false
	var owners := utilities()
	var sprites := utility_sprites()
	# The notebook deliberately crosses the screen edge; only these three
	# utility hover silhouettes must remain entirely inside the margin.
	for index in 3:
		var sprite := sprites[index]
		var rect := sprite.get_rect()
		var transform := sprite.get_global_transform_with_canvas()
		var pivot := owners[index].get_global_transform_with_canvas().origin
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var expanded: Vector2 = pivot + (transform * corner - pivot) * screen.hover_feedback.utility_pop_scale
			if not initialized:
				result = Rect2(expanded, Vector2.ZERO)
				initialized = true
			else: result = result.expand(expanded)
	return result


func notebook_alpha_bounds() -> Rect2:
	var sprite: Sprite2D = screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot/Sprite")
	var image := sprite.texture.get_image()
	var source := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, image.get_size())
	var start := Vector2i(floori(source.position.x), floori(source.position.y))
	var end := Vector2i(ceili(source.end.x), ceili(source.end.y))
	var pixels := Rect2i(start, end - start)
	var used := Rect2(image.get_region(pixels).get_used_rect())
	used.position += Vector2(start) - source.position + sprite.get_rect().position
	return sprite.get_global_transform_with_canvas() * used


func verify_notebook_edge(label: String) -> void:
	var bounds := notebook_alpha_bounds()
	var viewport := root.get_visible_rect()
	check(bounds.position.x < viewport.end.x and bounds.end.x > viewport.end.x,
		label + " places actual opaque notebook art across the right screen edge")
	var visible_fraction := bounds.intersection(viewport).size.x / bounds.size.x
	check(visible_fraction > 0.75 and visible_fraction < 0.98,
		label + " keeps most of the notebook visible with a deliberate cropped edge")


func verify_anchor(label: String) -> void:
	var bounds := hover_art_bounds()
	var viewport := root.get_visible_rect()
	var margin: Vector2 = screen.utility_edge_margin
	check(absf(viewport.end.x - bounds.end.x - margin.x) < 1.0,
		label + " keeps hovered artwork against the viewport's right margin")
	check(absf(viewport.end.y - bounds.end.y - margin.y) < 1.0,
		label + " keeps hovered artwork against the viewport's bottom margin")
	check(viewport.encloses(bounds), label + " keeps the complete hover expansion on screen")
	verify_notebook_edge(label)
	for utility in utilities():
		check(utility.get_parent() == utility_parents[utility.get_instance_id()],
			label + " preserves utility parent and identity: " + String(utility.name))


func resize_live(size_value: Vector2i) -> void:
	var placed: Array[Dictionary] = []
	for handle in get_nodes_in_group(&"table_placeables"):
		if handle is TablePlaceable and screen.is_ancestor_of(handle) and is_instance_valid(handle.item):
			placed.append({"item": handle.item, "parent": handle.item.get_parent(), "transform": handle.item.transform})
	root.size = size_value
	await frames(4)
	var unchanged := true
	for entry in placed:
		unchanged = unchanged and is_instance_valid(entry.item) and entry.item.get_parent() == entry.parent and entry.item.transform == entry.transform
	check(unchanged and not placed.is_empty(), "Dock resize leaves movable table/tray objects and ingredient containers at their existing local layout and proportions")
	verify_anchor("Live resize %s" % size_value)


func probe_at(surface_position: Vector2) -> DropValidation:
	probe.position = surface_position
	return table.validate_candidate(probe, probe_shape)


func base_points(owner_node: Node2D, center: Vector2, radius: Vector2) -> PackedVector2Array:
	# Sample the interior of the documented physical base, independently of
	# whichever exclusion nodes or reservation representation implements it.
	var result := PackedVector2Array()
	var transform := table.global_transform.affine_inverse() * owner_node.global_transform
	for y in [-0.5, 0.0, 0.5]:
		for x in [-0.5, 0.0, 0.5]:
			result.append(transform * (center + radius * Vector2(x, y)))
	return result


func current_base_points() -> PackedVector2Array:
	var nodes := utilities()
	var result := PackedVector2Array()
	result.append_array(base_points(nodes[0], Vector2(0, 61), Vector2(36, 8)))
	result.append_array(base_points(nodes[1], Vector2(0, 61), Vector2(45, 12)))
	result.append_array(base_points(nodes[2], Vector2(0, 45), Vector2(57, 17)))
	result.append_array(base_points(nodes[3], Vector2(0, 98), Vector2(33, 6)))
	return result


func verify_base_exclusions(label: String) -> void:
	var blocked_inside := 0
	var all_occupied := true
	for point in current_base_points():
		var validation := probe_at(point)
		all_occupied = all_occupied and not validation.is_valid
		if validation.reason_key == "placement.blocked": blocked_inside += 1
	check(all_occupied, label + " does not expose occupied utility bases as free table space")
	check(blocked_inside > 0, label + " uses live exclusions for utility bases intersecting the tabletop")


func check_live_layout_and_old_footprints() -> void:
	await resize_live(Vector2i(1920, 1080))
	verify_base_exclusions("Initial layout")
	var old_points := current_base_points()
	var old_blocked := PackedVector2Array()
	for point in old_points:
		if probe_at(point).reason_key == "placement.blocked": old_blocked.append(point)
	await resize_live(Vector2i(1280, 800))
	verify_base_exclusions("Changed aspect")
	var reclaimed := 0
	for point in old_blocked:
		if probe_at(point).is_valid: reclaimed += 1
	check(reclaimed > 0, "Moving the dock releases old tabletop exclusions instead of leaving invisible blockers")
	for size_value in [Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		await resize_live(size_value)
		verify_base_exclusions("Repeated resize %s" % size_value)
	await capture("00-anchored-utilities")


func check_water_resize_custody() -> void:
	var water: WaterDrum = screen.get_node("WorldRoot/ToolLayer/WaterDrum")
	var kettle: Kettle = screen.get_node("WorldRoot/ToolLayer/KettleStation")
	var supply: DailyWaterSupply = root.get_node("GameState").water_supply
	kettle.discard_contents()
	var before := supply.remaining_ml
	var identity := water.get_instance_id()
	check(water.begin_drag(water.get_global_transform_with_canvas().origin), "Water begins an actual reserved source drag")
	controller.update_drag(root.get_visible_rect().get_center())
	await resize_live(Vector2i(1280, 800))
	check(not controller.is_dragging() and water.get_instance_id() == identity,
		"Resize cancels the held water gesture while preserving the source identity")
	check(water.get_parent() == utility_parents[identity] and supply.remaining_ml == before and kettle.volume_ml == 0.0,
		"Resize restores source custody without consuming water")
	var home := water.transform
	check(water.begin_drag(water.get_global_transform_with_canvas().origin), "Canceled water reservation can immediately be used again")
	controller.release_drop(kettle.get_node("WaterFillTarget").get_global_transform_with_canvas().origin)
	await frames()
	check(kettle.volume_ml > 0.0 and is_equal_approx(before - supply.remaining_ml, kettle.volume_ml),
		"Subsequent fill transfers the exact conserved water quantity")
	check(not controller.is_dragging() and water.get_parent() == utility_parents[identity] and water.transform == home,
		"Successful fill returns to the resized dock home rather than its old authored location")
	verify_anchor("Water returned after resize")


func right_pick(cup: Cup) -> void:
	var point := cup.get_global_transform_with_canvas().origin
	if DisplayServer.get_name() == "headless":
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.pressed = true
		press.position = point
		controller._input(press)
		cup.get_node("PlacementHandle")._on_input_event(root, press, 0)
	else:
		await mouse_button(point, true, MOUSE_BUTTON_RIGHT)
	check(controller.current_drag_node == cup and controller.is_move_drag(), "Right pickup retains the real cup's placement gesture")


func right_release(point: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_RIGHT
		release.position = point
		controller._input(release)
	else:
		await mouse_button(point, false, MOUSE_BUTTON_RIGHT)


func check_covered_cup_recovery() -> void:
	await resize_live(Vector2i(1280, 800))
	var cup: Cup = screen.get_cups()[0]
	var handle: TablePlaceable = cup.get_node("PlacementHandle")
	var original := cup.transform
	var candidates := PackedVector2Array()
	# Find a real visible utility point where this cup's base would be blocked
	# after the dock moves. The same surface coordinates must be clear before.
	for sprite in utility_sprites().slice(0, 3):
		var rect: Rect2 = sprite.get_rect()
		for y in range(2, 9):
			for x in range(2, 9):
				var local: Vector2 = rect.position + rect.size * Vector2(x, y) / 10.0
				var point: Vector2 = sprite.get_global_transform_with_canvas() * local
				if screen.hover_feedback.get_utility_at(point) == null: continue
				var surface_point := table.get_global_transform_with_canvas().affine_inverse() * point
				cup.global_position = table.to_global(surface_point)
				if table.validate_candidate(cup, handle.get_footprints()).reason_key == "placement.blocked":
					candidates.append(surface_point)
	cup.transform = original
	await resize_live(Vector2i(1920, 1080))
	var destination := Vector2.INF
	for candidate in candidates:
		cup.global_position = table.to_global(candidate)
		if table.validate_candidate(cup, handle.get_footprints()).is_valid:
			destination = candidate
			break
	cup.transform = original
	check(destination.is_finite(), "Fixture finds free real table space subsequently covered by the resized dock")
	if not destination.is_finite(): return
	await right_pick(cup)
	await right_release(table.get_global_transform_with_canvas() * destination)
	check(handle.surface == table and table.is_registered(cup), "Cup is placed through the normal controller before the dock moves")
	var identity := cup.get_instance_id()
	await resize_live(Vector2i(1280, 800))
	var pickup := cup.get_global_transform_with_canvas().origin
	check(screen.hover_feedback.get_utility_at(pickup) != null and table.is_registered(cup),
		"Resize visibly covers the cup pickup while preserving its reservation and identity")
	await right_pick(cup)
	var clear_point: Vector2 = screen.world_root.get_global_transform_with_canvas() * Vector2(860, 900)
	await right_release(clear_point)
	check(not controller.is_dragging() and cup.get_instance_id() == identity and table.is_registered(cup)
		and table.validate_item(cup).is_valid and cup.get_global_transform_with_canvas().origin.distance_to(clear_point) < 0.1,
		"Right drag recovers the covered cup into clear table space without replacement or loss")


func settle_notebook(modal: KhataModal) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while (modal.is_traveling() or modal.book.busy) and Time.get_ticks_msec() < deadline: await frames()
	check(not modal.is_traveling() and not modal.book.busy, "Notebook presentation settles")


func check_notebook_resize_return() -> void:
	var modal: KhataModal = screen.khata_modal
	var cover: Sprite2D = screen.get_node("WorldRoot/ToolLayer/KhataStation/KhataHotspot/Sprite")
	modal.open_peek()
	await settle_notebook(modal)
	check(modal.is_peeking() and not cover.is_visible_in_tree(), "Peek owns the same docked cover")
	await resize_live(Vector2i(1600, 900))
	var resized_home := cover.get_global_transform_with_canvas()
	modal.close_peek()
	await settle_notebook(modal)
	check(not modal.is_peeking() and cover.is_visible_in_tree() and cover.get_global_transform_with_canvas() == resized_home,
		"Closing after resize restores the actual cover at the new viewport dock")
	verify_notebook_edge("Peek returned after resize")
	check(not controller.is_world_input_blocked(), "Resized notebook return releases world input")
	await capture("01-notebook-returned")
	check(modal.open(), "Full notebook opens from the same dock")
	await settle_notebook(modal)
	modal.close()
	var deadline := Time.get_ticks_msec() + 6000
	while not modal.is_traveling() and Time.get_ticks_msec() < deadline: await frames()
	check(modal.is_traveling() and not cover.is_visible_in_tree(), "Full close enters the actual cover return journey")
	await resize_live(Vector2i(1366, 768))
	resized_home = cover.get_global_transform_with_canvas()
	await settle_notebook(modal)
	check(cover.is_visible_in_tree() and cover.get_global_transform_with_canvas() == resized_home
		and not controller.is_world_input_blocked(), "Resize during Full return lands at the new cover home and releases modal ownership")
	verify_notebook_edge("Full returned during resize")


func check_bucket_after_resize() -> void:
	await resize_live(Vector2i(1280, 800))
	var cup: Cup = screen.get_cups()[0]
	var identity := cup.get_instance_id()
	fill(cup)
	check(cup.mark_served() and cup.finish_consumption(), "Bucket fixture uses the normal dirty-cup lifecycle")
	var water_before: float = root.get_node("GameState").water_supply.remaining_ml
	var stock_before := stock.quantities
	await take_cup(cup)
	check(await drop_bucket(), "Resized bucket receives the original dirty cup through its real drop target")
	bucket.config.output_travel_seconds = 0.0
	check(bucket.begin_wash(), "Resized bucket can begin the existing held wash")
	bucket.advance_washing(bucket.config.wash_seconds)
	await frames()
	check(cup.get_instance_id() == identity and cup.state == Cup.CupState.CLEAN and not bucket.has_cup(cup),
		"Resized bucket returns the same clean cup automatically")
	var handle: TablePlaceable = cup.get_node("PlacementHandle")
	check(handle.surface == tray.interior_surface and tray.interior_surface.is_registered(cup),
		"Automatic output keeps tray-first geometry and custody after resize")
	check(root.get_node("GameState").water_supply.remaining_ml == water_before and stock.quantities == stock_before,
		"Washing after resize neither depletes brewing water nor refunds ingredients")
	await capture("02-bucket-after-resize")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	await fixture()
	for utility in utilities(): utility_parents[utility.get_instance_id()] = utility.get_parent()
	probe = Node2D.new()
	table.add_child(probe)
	await check_live_layout_and_old_footprints()
	await check_water_resize_custody()
	await check_covered_cup_recovery()
	await check_notebook_resize_return()
	await check_bucket_after_resize()
	if is_instance_valid(screen): screen.queue_free()
	await frames()
	await create_timer(0.35).timeout
	print("DEMO_EDGE_ANCHOR: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
