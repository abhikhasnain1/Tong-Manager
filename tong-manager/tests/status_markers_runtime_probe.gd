extends SceneTree
## Run with a rendered window. Optional first user argument is a capture directory.

const PREVIEW := preload("res://scenes/development/StatusMarkersPreview.tscn")
var checks := 0
var failures: Array[String] = []
var capture_dir := ""
var view: Node
var screen: Node2D
var controller: InteractionController
var layer: ObjectStatusBadgeLayer


func _init() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for _index in count:
		await physics_frame
		await process_frame


func point(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func move_pointer(to: Vector2, held := false) -> void:
	var from := root.get_mouse_position()
	root.warp_mouse(to)
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await frames()


func mouse(to: Vector2, pressed: bool) -> void:
	await move_pointer(to, pressed)
	var event := InputEventMouseButton.new()
	event.position = to
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await frames()


func escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()


func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered marker capture has pixels: " + name)
	if image != null and not image.is_empty():
		check(image.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved marker capture: " + name)


func check_layout(label: String) -> void:
	var rectangles: Array[Rect2] = []
	for vessel in layer.get_vessels():
		var badge := layer.get_badge_for(vessel)
		check(badge != null and badge.visible, label + ": live owner has a visible marker group")
		if badge == null: continue
		var rect := Rect2(badge.position, badge.get_badge_size())
		check(root.get_visible_rect().encloses(rect), label + ": marker group fits the rendered viewport")
		for previous in rectangles:
			check(not rect.intersects(previous), label + ": marker groups remain distinct")
		for other in layer.get_vessels():
			if other.is_visible_in_tree():
				var body := layer.get_vessel_bounds(other)
				check(not body.has_area() or not rect.intersects(body), label + ": floating markers leave vessel bodies uncovered")
		rectangles.append(rect)
		check(not controller.is_pointer_over_ui_at(badge.get_global_rect().get_center()), label + ": floating markers do not report blocking UI")


func front_cup() -> Cup:
	for value: Cup in screen.get_cups():
		var handle := value.get_node("PlacementHandle") as TablePlaceable
		if handle._is_frontmost_at(point(value)) and not controller.is_pointer_over_ui_at(point(value)):
			return value
	return null


func check_hover_and_pointer(value: Cup) -> void:
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	await move_pointer(Vector2(12, root.size.y - 12))
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	var badge := layer.get_badge_for(value)
	var resting := badge.position
	await move_pointer(point(value))
	check(value.is_status_hovered(), "Real vessel hover activates the owner marker group")
	await create_timer(0.35).timeout
	check(badge.position.y < resting.y, "Real hover gently raises the marker group")
	await create_timer(layer.config.hover_rise_seconds).timeout
	check(absf(badge.position.y - (resting.y - layer.config.hover_lift)) < 0.1, "Sustained hover reaches its configured lift")
	await capture("hover-raised")
	# Cover the still-hovered owner with a real Control; feedback follows world
	# input routing, including a control appearing beneath a stationary pointer.
	var overlay := Control.new()
	overlay.position = point(value) - Vector2(45, 45)
	overlay.size = Vector2(90, 90)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.get_node("HUDLayer/RootUI").add_child(overlay)
	await frames()
	check(controller.is_pointer_over_ui_at(point(value)) and not value.is_status_hovered(), "An overlaid UI control suppresses world-owner hover")
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	check(badge.position.is_equal_approx(resting), "UI coverage settles the marker without moving the vessel")
	overlay.queue_free()
	await frames()
	await move_pointer(Vector2(12, root.size.y - 12))
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	check(badge.position.is_equal_approx(resting), "Pointer exit returns the markers to their resting position")
	# Force a marker over the cup only for this passthrough regression, so the
	# physical click must travel through the actual presentation Control.
	layer.set_process(false)
	badge.position = point(value) - badge.get_badge_size() * 0.5
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	var origin := value.global_transform
	var anchor := layer.get_anchor_position(value)
	await mouse(point(value), true)
	check(controller.is_dragging() and controller.current_payload.world_node == value, "A marker overlapping a cup does not intercept the real Organize press")
	layer.set_process(true)
	if controller.is_dragging():
		await move_pointer(point(value) + Vector2(-65, -35), true)
		check(layer.get_badge_for(value) == badge, "The same marker instance follows a held cup through drag-layer reparenting")
		check(not layer.get_anchor_position(value).is_equal_approx(anchor), "Held cup movement moves its projected marker anchor")
		await capture("drag-follow")
		await escape()
		await mouse(point(value), false)
		check(not controller.is_dragging() and value.global_transform.is_equal_approx(origin), "Cancel restores the actual cup exactly")
		check(layer.get_anchor_position(value).is_equal_approx(anchor), "Cancel restores the same cup marker anchor")
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	await move_pointer(Vector2(12, root.size.y - 12))
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout


func check_overlap_hover() -> void:
	var cups: Array[Cup] = screen.get_cups()
	if cups.size() < 2:
		check(false, "Overlap hover fixture requires two cups")
		return
	var back := cups[0]
	var front := cups[1]
	var old_transform := front.transform
	var back_handle := back.get_node("PlacementHandle") as TablePlaceable
	var front_handle := front.get_node("PlacementHandle") as TablePlaceable
	var surface := front_handle.surface
	check(back.get_parent() == front.get_parent(), "Overlap fixture uses two cups on one surface")
	# Their narrow bases stay separate while their taller artwork/hit regions
	# overlap. Authored default spacing is intentionally not the test fixture.
	front.transform = back.transform
	front.position += back.transform.y * 25.0
	var valid := surface.validate_item(front).is_valid
	check(valid, "Overlapping artwork fixture keeps two legally separated cup bases")
	if valid:
		check(surface.commit_item(front), "Overlap fixture commits its valid base reservation")
		await frames()
		var location: Vector2 = back.get_global_transform_with_canvas() * Vector2(0, 12.5)
		check(back_handle._contains_pointer(location) and front_handle._contains_pointer(location), "Both real hit regions cover the overlap probe")
		await move_pointer(location)
		check(front_handle._is_frontmost_at(location) and not back_handle._is_frontmost_at(location), "Y ordering identifies the visible front cup")
		check(front.is_status_hovered() and not back.is_status_hovered(), "Only the front cup raises its markers in overlapping real hit regions")
		await capture("overlap-front-hover")
	front.transform = old_transform
	check(surface.commit_item(front), "Overlap fixture restores the original committed placement")
	await frames()


func check_kettle_hover_and_pointer() -> void:
	var kettle: Kettle = view.kettle as Kettle
	var grip: Marker2D = kettle.get_node("GripAnchor") as Marker2D
	var away: Vector2 = Vector2(12, root.get_visible_rect().size.y - 12)
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	await move_pointer(away)
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	var badge: ObjectStatusBadge = layer.get_badge_for(kettle)
	check(badge != null, "The live kettle has its own marker group")
	if badge == null: return
	var resting: Vector2 = badge.position
	var token_rects: Array[Rect2] = badge.get_token_rects()
	var dimensions: Vector2 = badge.get_badge_size()
	var hover_point: Vector2 = point(grip)
	check(not controller.is_pointer_over_ui_at(hover_point), "The real kettle grip is reachable outside UI")
	await move_pointer(hover_point)
	check(kettle.is_status_hovered(), "Real kettle grip hover activates the kettle marker group")
	await create_timer(layer.config.hover_rise_seconds * 0.25).timeout
	check(badge.position.y < resting.y and badge.position.y > resting.y - layer.config.hover_lift,
		"Kettle hover rises partway before completing its animation")
	check(badge.get_token_rects() == token_rects and badge.get_badge_size() == dimensions,
		"Kettle icons retain their relative arrangement during the rise")
	await create_timer(layer.config.hover_rise_seconds).timeout
	check(badge.position.is_equal_approx(resting - Vector2(0, layer.config.hover_lift)),
		"Sustained kettle hover lifts the whole group by the configured amount")
	check(badge.get_token_rects() == token_rects,
		"Kettle hover has no independent icon jitter at full lift")
	await capture("kettle-hover-raised")

	var overlay: Control = Control.new()
	overlay.position = hover_point - Vector2(45, 35)
	overlay.size = Vector2(90, 70)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.get_node("HUDLayer/RootUI").add_child(overlay)
	await frames()
	check(controller.is_pointer_over_ui_at(hover_point) and not kettle.is_status_hovered(),
		"UI appearing beneath the stationary kettle pointer suppresses world hover")
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	check(badge.position.is_equal_approx(resting),
		"Covered kettle markers return to their resting position")
	check(badge.get_token_rects() == token_rects,
		"The kettle group retains its internal layout during the return")
	overlay.queue_free()
	await frames()
	await move_pointer(away)
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	check(not kettle.is_status_hovered() and badge.position.is_equal_approx(resting),
		"Removing UI and leaving the kettle restores its unhovered presentation")

	controller.set_mode(InteractionController.MODE_INTERACT)
	var origin: Transform2D = kettle.global_transform
	var origin_anchor: Vector2 = layer.get_anchor_position(kettle)
	var pickup_point: Vector2 = point(grip)
	await mouse(pickup_point, true)
	check(controller.is_dragging() and controller.current_payload.world_node == kettle and kettle.is_held,
		"The real grip still picks up the kettle beneath its floating markers")
	if controller.is_dragging() and controller.current_payload.world_node == kettle:
		await move_pointer(pickup_point + Vector2(100, -25), true)
		check(layer.get_badge_for(kettle) == badge,
			"Held kettle reparenting preserves the same marker group")
		check(not layer.get_anchor_position(kettle).is_equal_approx(origin_anchor),
			"The held kettle moves its actual status anchor")
		check(badge.get_token_rects() == token_rects,
			"Held kettle markers keep their icon arrangement")
		var spout_point: Vector2 = point(kettle.get_node("Spout") as Marker2D)
		for vessel: Node in layer.get_vessels():
			var visible_badge: ObjectStatusBadge = layer.get_badge_for(vessel)
			if visible_badge == null or not visible_badge.visible: continue
			var marker_rect: Rect2 = Rect2(visible_badge.get_global_transform_with_canvas().origin, visible_badge.get_badge_size())
			check(not marker_rect.has_point(spout_point),
				"Floating marker groups leave the held kettle's pouring spout visible")
		await capture("kettle-drag-follow")
		await escape()
		await mouse(point(grip), false)
		check(not controller.is_dragging() and not kettle.is_held and kettle.global_transform.is_equal_approx(origin),
			"Escape restores the actual kettle transform and held state")
		check(layer.get_badge_for(kettle) == badge and layer.get_anchor_position(kettle).is_equal_approx(origin_anchor),
			"Kettle cancellation restores the same marker identity and anchor")
	controller.set_mode(InteractionController.MODE_NEUTRAL)
	await move_pointer(away)
	await create_timer(layer.config.hover_return_seconds + 0.15).timeout
	check(badge.position.is_equal_approx(resting) and badge.get_token_rects() == token_rects,
		"After kettle pickup and cancellation its marker group settles without rearranging")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Status marker runtime probe requires a rendered window; use status_markers_test.gd headless.")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	view = PREVIEW.instantiate()
	root.add_child(view)
	await frames(4)
	screen = view.screen
	controller = view.controller
	layer = screen.get_node("HUDLayer/RootUI/StatusBadges")
	# Freeze only these sample vessels for repeatable photographs; the fixture
	# itself and normal play keep their simulation live.
	view.kettle.set_process(false)
	for value: Cup in screen.get_cups(): value.set_process(false)
	for burner in view.stove.burners: burner.set_process(false)
	await move_pointer(Vector2(12, root.size.y - 12))
	for index in view.EXAMPLES.size():
		view.apply_example(index)
		await frames(3)
		check_layout("Example %d" % index)
		await capture("example-%d" % index)
	view.apply_example(6)
	await frames()
	var selected := front_cup()
	check(selected != null, "At least one visible cup can receive actual input")
	if selected != null:
		await check_hover_and_pointer(selected)
	await check_kettle_hover_and_pointer()
	await check_overlap_hover()
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	var initial := tray.transform
	var cup: Cup = screen.get_cups()[0]
	var initial_anchor := layer.get_anchor_position(cup)
	tray.position += Vector2(-45, -22)
	await frames()
	check(not layer.get_anchor_position(cup).is_equal_approx(initial_anchor), "Populated tray movement carries its children's markers")
	check_layout("Moved populated tray")
	await capture("moved-tray")
	tray.transform = initial
	await frames()
	check(layer.get_anchor_position(cup).is_equal_approx(initial_anchor), "Restoring the tray restores the owner projection")
	view.queue_free()
	await frames()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Marker review teardown leaves a visible cursor")
	print("STATUS_MARKERS_RUNTIME: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
