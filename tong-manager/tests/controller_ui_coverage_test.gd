extends SceneTree

class CircleControl extends Control:
	func _has_point(point: Vector2) -> bool:
		return point.distance_to(Vector2(30,30)) < 12

var checks := 0
var failures: Array[String] = []
var host := Node2D.new()
var controller := InteractionController.new()
var layer := CanvasLayer.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func point(control: Control, local: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local

func covered(control: Control, local: Vector2) -> bool:
	return controller.is_pointer_over_ui_at(point(control,local))

func panel(parent: Node, position: Vector2, size: Vector2, filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP) -> Control:
	var control := Control.new()
	control.position = position
	control.size = size
	control.mouse_filter = filter
	parent.add_child(control)
	return control

func run() -> void:
	root.size = Vector2i(1920,1080)
	var drag := Node2D.new()
	drag.name = "DragLayer"
	host.add_child(drag)
	var zones := Node2D.new()
	zones.name = "Zones"
	host.add_child(zones)
	controller.drag_layer_path = NodePath("../DragLayer")
	controller.drop_zone_root_path = NodePath("../Zones")
	host.add_child(controller)
	host.add_child(layer)
	root.add_child(host)
	await process_frame
	check(not controller.is_pointer_over_ui_at(Vector2(100,100)),"Empty scene leaves arbitrary pointer points available")
	var ui := panel(layer,Vector2.ZERO,Vector2(1920,1080),Control.MOUSE_FILTER_IGNORE)
	check(not covered(ui,Vector2(100,100)),"Full-screen IGNORE root does not block blank world space")
	var button := panel(ui,Vector2(300,200),Vector2(100,70))
	check(covered(button,Vector2(50,30)),"STOP child blocks its visible rectangle under an IGNORE root")
	check(not covered(button,Vector2(-1,30)) and not covered(button,Vector2(101,30)),"A control does not block points outside its local rectangle")
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	check(covered(button,Vector2(50,30)),"PASS controls count as UI consistently with endpoint hover handling")
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check(not covered(button,Vector2(50,30)),"Changing to IGNORE releases the point immediately")
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.rotation = 0.47
	button.scale = Vector2(1.7,0.65)
	check(covered(button,Vector2(50,30)),"Rotated nonuniform control remains covered in viewport coordinates")
	check(not covered(button,Vector2(110,30)),"Transformed hit testing avoids an axis-aligned bounding-box false positive")
	layer.offset = Vector2(85,46)
	layer.scale = Vector2(0.8,1.4)
	check(covered(button,Vector2(50,30)),"CanvasLayer scale and offset participate in the point transform")
	button.hide()
	check(not covered(button,Vector2(50,30)),"Hidden control cannot block world input")
	button.show()
	ui.hide()
	check(not covered(button,Vector2(50,30)),"Hidden UI ancestor removes child coverage")
	ui.show()
	layer.hide()
	check(not covered(button,Vector2(50,30)),"Hidden CanvasLayer removes child coverage")
	layer.show()
	button.scale = Vector2.ZERO
	check(not covered(button,Vector2.ZERO),"Zero-scale controls are ignored without inverting a singular transform")
	button.free()
	var clip := panel(ui,Vector2(400,300),Vector2(100,100),Control.MOUSE_FILTER_IGNORE)
	clip.clip_contents = true
	clip.rotation = -0.2
	clip.scale = Vector2(1.25,0.8)
	var child := panel(clip,Vector2(80,10),Vector2(80,60))
	check(covered(child,Vector2(10,20)),"Visible part of a child inside a transformed clip rectangle blocks input")
	check(not covered(child,Vector2(50,20)),"Clipped-out child pixels cannot block a swept pointer")
	clip.clip_contents = false
	check(covered(child,Vector2(50,20)),"Non-clipping IGNORE parents allow a child outside their own rectangle")
	clip.clip_contents = true
	child.top_level = true
	child.position = Vector2(700,450)
	check(covered(child,Vector2(50,20)),"Top-level controls escape former CanvasItem ancestor clipping")
	child.top_level = false
	child.position = Vector2(10,10)
	clip.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	check(not covered(child,Vector2(20,20)),"Recursive disabled mouse behavior is respected")
	child.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	check(covered(child,Vector2(20,20)),"Explicit child mouse behavior can override a disabled ancestor")
	clip.free()
	var circle := CircleControl.new()
	circle.position = Vector2(600,250)
	circle.size = Vector2(60,60)
	ui.add_child(circle)
	check(covered(circle,Vector2(30,30)),"Custom Control hit region includes its actual center")
	check(not covered(circle,Vector2(5,5)),"Custom Control hit region excludes transparent rectangle corners")
	circle.free()
	var foreign := SubViewport.new()
	foreign.size = Vector2i(1920,1080)
	host.add_child(foreign)
	panel(foreign,Vector2.ZERO,Vector2(1920,1080))
	check(not controller.is_pointer_over_ui_at(Vector2(700,400)),"Controls belonging to another Viewport do not block this viewport")
	var queued := panel(ui,Vector2(750,450),Vector2(90,90))
	check(covered(queued,Vector2(40,40)),"Live queued-removal fixture initially covers its point")
	queued.queue_free()
	check(not covered(queued,Vector2(40,40)),"Queued UI teardown cannot leave a stale swept-input blocker")
	check(not controller.is_pointer_over_ui_at(Vector2(INF,0)),"Non-finite query is rejected")
	host.queue_free()
	await process_frame
	print("CONTROLLER_UI_COVERAGE: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
