extends SceneTree

const TONG := preload("res://scenes/gameplay/tong/TongDayScreen.tscn")
const Feedback := preload("res://scripts/gameplay/interactions/demo_hover_feedback.gd")
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var feedback: DemoHoverFeedback
var controller: InteractionController
var capture_dir := ""


func _init() -> void:
	run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for index in count:
		await process_frame
		await physics_frame


func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved actual hover presentation: " + name)


func point_for(owner_node: Node2D, sprite: Sprite2D) -> Vector2:
	var rect := sprite.get_rect()
	for y in range(1, 20):
		for x in range(1, 20):
			var local := rect.position + rect.size * Vector2(x / 20.0, y / 20.0)
			if not sprite.is_pixel_opaque(local): continue
			var point := sprite.get_global_transform_with_canvas() * local
			feedback.update_feedback(0.0, point)
			if feedback.get_hovered_owner() == owner_node: return point
	return Vector2.INF


func check_art(owner_node: Node2D, sprite: Sprite2D, label: String, utility := false) -> Vector2:
	feedback.update_feedback(0.0, Vector2(-50, -50))
	var owner_transform := owner_node.global_transform
	var sprite_transform := sprite.transform
	var previous := sprite.material
	var old_z := owner_node.z_index
	var old_relative := owner_node.z_as_relative
	var point := point_for(owner_node, sprite)
	check(point.is_finite(), label + " has an opaque visible hover point")
	check(feedback.get_hovered_owner() == owner_node, label + " alone owns hover feedback")
	check(sprite.material is ShaderMaterial and sprite.material != previous, label + " uses alpha outline presentation")
	check(owner_node.global_transform == owner_transform and sprite.transform == sprite_transform,
		label + " preserves physical and sprite transforms")
	if sprite.material is ShaderMaterial:
		check(is_equal_approx(float((sprite.material as ShaderMaterial).get_shader_parameter("pop_scale")), 1.08 if utility else 1.04),
			label + " uses the configured render-only enlargement")
	feedback.update_feedback(0.0, Vector2(-50, -50))
	check(sprite.material == previous and owner_node.z_index == old_z and owner_node.z_as_relative == old_relative,
		label + " restores its original material and drawing order")
	return point


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): capture_dir = args[0]
	await frames()
	screen = TONG.instantiate()
	screen.customer_queue_enabled = false
	screen.customer_queue_auto_start = false
	root.add_child(screen)
	await frames(3)
	controller = screen.get_node("InteractionController")
	controller.set_mode(InteractionController.MODE_INTERACT)
	feedback = Feedback.new()
	screen.add_child(feedback)
	feedback.configure(screen)
	feedback.set_process(false)
	check(feedback.get_hovered_owner() == null, "No object starts highlighted")
	var cup: Cup = screen.get_cups()[0]
	var handle := cup.get_node("PlacementHandle") as TablePlaceable
	var committed := handle.surface.get_committed_polygons(cup).duplicate(true)
	var cup_point := check_art(cup, cup.cup_sprite, "Cup")
	check(handle.surface.get_committed_polygons(cup) == committed, "Cup enlargement cannot alter committed geometry")
	cup.receive_liquid(&"black_tea", 125.0, 70.0)
	feedback.update_feedback(0.0, cup_point)
	var overlay := cup.get_node("ContentsOverlay") as Sprite2D
	check(overlay.visible and overlay.material is ShaderMaterial, "Filled cup contents enlarge with the cup body")
	check(not bool((overlay.material as ShaderMaterial).get_shader_parameter("outline_enabled")), "Liquid receives no misleading white rim of its own")
	var cup_pivot: Vector2 = (cup.cup_sprite.material as ShaderMaterial).get_shader_parameter("pop_pivot")
	var liquid_pivot: Vector2 = (overlay.material as ShaderMaterial).get_shader_parameter("pop_pivot")
	check((cup.cup_sprite.get_global_transform_with_canvas() * cup_pivot).is_equal_approx(overlay.get_global_transform_with_canvas() * liquid_pivot),
		"Body and liquid enlargement share one physical pivot")
	await capture("cup-hover")
	for name in [&"TeaBox", &"SugarCan", &"SugarCanEnglish", &"CondensedMilkCan"]:
		var source := screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/" + String(name)) as Sprite2D
		var region := source.region_rect
		check_art(source, source, String(name))
		check(source.region_rect == region, "Source crop remains unchanged: " + String(name))
	var kettle := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var kettle_sprite := kettle.get_node("Sprite") as Sprite2D
	var kettle_point := check_art(kettle, kettle_sprite, "Kettle")
	feedback.update_feedback(0.0, kettle_point)
	var lid := kettle.get_node("Lid/Sprite") as Sprite2D
	check(lid.material is ShaderMaterial, "Kettle body and animated lid both receive feedback")
	var body_pivot: Vector2 = (kettle_sprite.material as ShaderMaterial).get_shader_parameter("pop_pivot")
	var lid_pivot: Vector2 = (lid.material as ShaderMaterial).get_shader_parameter("pop_pivot")
	check((kettle_sprite.get_global_transform_with_canvas() * body_pivot).is_equal_approx(lid.get_global_transform_with_canvas() * lid_pivot),
		"Kettle layers share a coherent rendered enlargement pivot")
	await capture("kettle-hover")
	var stove := screen.get_node("WorldRoot/ToolLayer/StoveStation") as Node2D
	check_art(stove, stove.get_node("Sprite") as Sprite2D, "Stove")
	for name in [&"DialA", &"DialB"]:
		var dial := stove.get_node(String(name)) as Node2D
		check_art(dial, dial.get_node("Sprite") as Sprite2D, String(name))
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	check_art(tray, tray.get_node("TraySprite") as Sprite2D, "Empty tray area")
	feedback.update_feedback(0.0, cup_point)
	check(feedback.get_hovered_owner() == cup and (tray.get_node("TraySprite") as Sprite2D).material == null,
		"Cup art takes hover precedence over the tray below")
	for pair in [["WorldRoot/ToolLayer/BucketStation", "Sprite"], ["WorldRoot/ToolLayer/WaterDrum", "Icon"],
		["WorldRoot/DropZoneRoot/DiscardArea", "Basket"], ["WorldRoot/ToolLayer/KhataStation/KhataHotspot", "Sprite"]]:
		var utility := screen.get_node(pair[0]) as Node2D
		var utility_point := check_art(utility, utility.get_node(pair[1]) as Sprite2D, String(utility.name), true)
		feedback.update_feedback(0.0, utility_point)
		await capture(String(utility.name) + "-hover")
	feedback.update_feedback(0.0, cup_point)
	var blocker := Node.new()
	screen.add_child(blocker)
	controller.set_world_input_blocked(blocker, true)
	feedback.update_feedback(0.0, cup_point)
	check(feedback.get_hovered_owner() == null and cup.cup_sprite.material == null, "Full modal input lock clears world feedback")
	controller.set_world_input_blocked(blocker, false)
	blocker.queue_free()
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = cup_point - Vector2(20, 20)
	panel.size = Vector2(40, 40)
	screen.get_node("HUDLayer/RootUI").add_child(panel)
	feedback.update_feedback(0.0, cup_point)
	check(feedback.get_hovered_owner() == null, "A newly placed GUI panel blocks underlying hover immediately")
	panel.free()
	feedback.update_feedback(0.0, cup_point)
	feedback.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(feedback.get_hovered_owner() == null and cup.cup_sprite.material == null, "Focus loss restores presentation immediately")
	feedback.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	feedback.update_feedback(0.0, Vector2(-50, -50))
	check(feedback.get_hovered_owner() == null, "Regaining focus does not resurrect stale hover")
	feedback.update_feedback(0.0, cup_point)
	check(cup.begin_interaction_drag(cup_point), "Actual cup gesture starts through the existing controller")
	feedback.update_feedback(0.0, Vector2(900, 450))
	check(feedback.get_hovered_owner() == cup, "Held physical cup keeps its one-owner feedback away from its starting point")
	controller.cancel_drag()
	feedback.update_feedback(0.0, cup_point)
	root.remove_child(screen)
	check(cup.cup_sprite.material == null, "Retained-screen exit restores all original sprite materials")
	root.add_child(screen)
	await frames()
	feedback.refresh_targets()
	feedback.update_feedback(0.0, cup_point)
	check(feedback.get_hovered_owner() == cup, "Retained-screen reentry can reacquire actual hover")
	feedback.free()
	check(cup.cup_sprite.material == null, "Removing optional helper leaves ordinary game presentation intact")
	screen.queue_free()
	await frames()
	print("DEMO_HOVER_FEEDBACK: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
