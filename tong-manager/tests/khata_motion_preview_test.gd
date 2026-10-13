extends SceneTree
## Rendered checks for the isolated notebook study, not production Khata acceptance.

var preview: Node2D
var checks := 0
var failures: Array[String] = []
var capture_dir := ""


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int = 3) -> void:
	for index in count:
		await process_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while preview.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not preview.busy, "Motion reaches a stable state")
	await frames()


func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = preview.get_global_transform_with_canvas() * point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await frames()


func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = preview.get_global_transform_with_canvas() * point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await frames()


func tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)
	await frames()


func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Saved " + name)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		capture_dir = args[0]
	preview = load("res://scenes/development/KhataPreview.tscn").instantiate()
	root.add_child(preview)
	await frames(8)
	preview.sound_enabled = false
	check(not preview.opened and preview.spread == 0, "Starts closed on first spread")
	await capture("closed")
	await tap(KEY_ENTER)
	await settle()
	check(preview.opened, "Enter opens the cover")
	await capture("open")
	var right_corner: Vector2 = preview._book_origin() + Vector2(460, 640)
	await mouse(right_corner, true)
	await move(right_corner - Vector2(160, 0))
	await mouse(right_corner - Vector2(160, 0), false)
	await settle()
	check(preview.spread == 0, "Short corner drag returns the sheet without changing spread")
	await mouse(right_corner, true)
	await move(right_corner - Vector2(285, 0))
	check(preview.dragging and preview.turn_progress > 0.3, "Pointer drives lifted sheet")
	await capture("turn-front")
	await move(right_corner - Vector2(374, 0))
	await capture("turn-midpoint")
	await move(right_corner - Vector2(510, 0))
	await capture("turn-back")
	await mouse(right_corner - Vector2(510, 0), false)
	await settle()
	check(preview.spread == 1, "Long drag completes one forward turn")
	await capture("notes")
	await tap(KEY_LEFT)
	await settle()
	check(preview.spread == 0, "Left arrow returns to first spread")
	await tap(KEY_LEFT)
	check(not preview.busy and preview.spread == 0, "Cannot turn before first spread")
	await mouse(preview._tab_rect(2).get_center(), true)
	await mouse(preview._tab_rect(2).get_center(), false)
	await settle()
	check(preview.spread == 2, "Ledger tab traverses to final spread")
	await capture("ledger")
	await tap(KEY_RIGHT)
	check(not preview.busy and preview.spread == 2, "Cannot turn after final spread")
	var left_corner: Vector2 = preview._book_origin() + Vector2(-460, 640)
	await mouse(left_corner, true)
	await move(left_corner + Vector2(350, 0))
	await capture("turn-reverse")
	await tap(KEY_ESCAPE)
	await settle()
	check(preview.spread == 2 and preview.opened, "Escape cancels corner drag without closing")
	await mouse(left_corner, false)
	await tap(KEY_LEFT)
	await tap(KEY_ESCAPE)
	await settle()
	check(not preview.opened and not preview.turning, "Close during a turn settles and closes safely")
	await tap(KEY_SPACE)
	await settle()
	check(preview.opened and preview.spread == 1, "Reopening preserves settled page")
	await mouse(preview._tab_rect(0).get_center(), true)
	await mouse(preview._tab_rect(0).get_center(), false)
	await settle()
	await mouse(right_corner, true)
	await move(right_corner - Vector2(130, 0))
	preview.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle()
	check(not preview.dragging and preview.spread == 0, "Focus loss releases a short held turn")
	await mouse(right_corner, false)
	await mouse(right_corner, true)
	await move(right_corner - Vector2(510, 0))
	preview._fit()
	await settle()
	check(preview.spread == 0 and not preview.dragging, "Resize cancels even a long held turn")
	await mouse(right_corner, false)
	await tap(KEY_S)
	check(preview.slow_motion, "Slow motion toggle is available for review")
	await tap(KEY_S)
	preview.queue_free()
	await frames(5)
	print("Khata motion preview: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
