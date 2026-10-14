extends SceneTree
## Customer presentation consumes outcome data; vessel matching and payment are separate.

const CUSTOMER := preload("res://scenes/gameplay/customers/Customer.tscn")
var checks := 0
var failures: Array[String] = []
var catalog: Node
var stage: Node2D
var sequence := 0


func _init() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count := 2) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func make_order(id: StringName = &"customer_a", request: StringName = &"tea_cha_no_sugar") -> OrderState:
	sequence += 1
	return catalog.create_order(StringName("scene_test_%d" % sequence), id, request, 0.0) as OrderState


func make_customer(id: StringName = &"customer_a") -> Customer:
	var value := CUSTOMER.instantiate() as Customer
	value.auto_arrive = false
	value.customer_def = catalog.get_customer(id)
	value.reduced_motion = true
	stage.add_child(value)
	value.arrive()
	return value


func outcome(order: OrderState, accepted: bool, cold := false, reason: StringName = &"") -> ServiceResult:
	sequence += 1
	return ServiceResult.create(StringName("handoff_%d" % sequence), order.order_id, order.customer_id,
		order.request_kind, accepted, cold, reason)


func check_results() -> void:
	var actor := make_customer()
	var order := make_order()
	check(actor.set_order(order) and actor.order == order, "Actor retains the supplied authoritative order")
	check(actor.is_serve_enabled(), "A visible waiting customer with an order can be addressed")
	var other_order := make_order(&"customer_b")
	check(not actor.set_order(other_order) and actor.order == order, "Another customer's order cannot replace the bound identity")
	var invalids: Array[ServiceResult] = [null,
		ServiceResult.create(&"foreign_customer", order.order_id, &"customer_b", &"tea", true),
		ServiceResult.create(&"foreign_order", &"missing_order", &"customer_a", &"tea", true),
		ServiceResult.create(&"foreign_kind", order.order_id, &"customer_a", &"ready_item", true)]
	for invalid in invalids:
		check(not actor.apply_service_result(invalid) and order.get_results().is_empty(), "Mismatched or missing outcome cannot mutate actor or order")
	var rejected := outcome(order, false, false, &"wrong_item")
	check(actor.apply_service_result(rejected), "A fresh rejected outcome is recorded and presented")
	var rejection := actor.get_presentation_snapshot()
	check(not order.fulfilled and actor.is_serve_enabled() and order.get_results().size() == 1,
		"Wrong service leaves the same customer waiting and able to receive another attempt")
	check(int(rejection.review_count) == 0, "Rejection is not a cold acceptance or bad review")
	check(not actor.apply_service_result(rejected) and order.get_results().size() == 1, "Rejected replay is idempotent")
	var warm := outcome(order, true)
	check(actor.apply_service_result(warm) and order.fulfilled and order.get_results().size() == 2, "A new valid attempt fulfills once after rejection")
	var warm_snapshot := actor.get_presentation_snapshot()
	check(actor.state == Customer.State.SERVED and not actor.is_serve_enabled() and int(warm_snapshot.review_count) == 0,
		"Warm acceptance becomes served with no bad review")
	var pending_copy := OrderState.create(order.order_id, order.customer_id, order.get_request(), order.created_time)
	check(not actor.set_order(pending_copy) and actor.order == order and actor.order.fulfilled,
		"A reconstructed pending copy cannot replace an existing order authority with the same identity")
	check(actor.set_order(order) and actor.order == order, "Rebinding the same authority is safe")
	check(not actor.apply_service_result(warm) and not actor.apply_service_result(outcome(order, true)), "Neither exact replay nor fresh acceptance duplicates a fulfilled order")
	var cold_order := make_order()
	check(actor.set_order(cold_order), "A genuinely new order resets presentation identity")
	actor.arrive()
	var cold := outcome(cold_order, true, true)
	var notifications: Array[Dictionary] = []
	var reentry: Array[bool] = []
	var observer := func(data: Dictionary):
		notifications.append(data.duplicate(true))
		reentry.append(actor.apply_service_result(cold))
		data["reason"] = &"changed_by_observer"
	actor.service_result_presented.connect(observer)
	check(actor.apply_service_result(cold), "Cold tea is accepted and presented")
	actor.service_result_presented.disconnect(observer)
	var cold_snapshot := actor.get_presentation_snapshot()
	check(cold_order.fulfilled and cold_order.get_accepted_result().unhappy and cold_order.get_accepted_result().bad_review,
		"Cold acceptance preserves fulfillment and the approved dissatisfied outcome")
	check(int(cold_snapshot.review_count) == 1 and cold_snapshot.review_reason == &"cold_tea"
		and cold_snapshot.emotion != warm_snapshot.emotion and cold_snapshot.emotion != rejection.emotion,
		"Cold accepted feedback is distinct from warm acceptance and rejection")
	check(notifications.size() == 1 and reentry == [false], "Synchronous presentation observer cannot replay the same outcome")
	check(cold_order.get_accepted_result().reason == &"cold_tea", "Observer changes cannot rewrite authoritative outcome history")
	cold_snapshot["review_count"] = 99
	check(int(actor.get_presentation_snapshot().review_count) == 1, "Presentation snapshots are detached")
	actor.reset_presentation()
	check(actor.order == cold_order and cold_order.fulfilled and not actor.apply_service_result(cold), "Reset preserves authority and once-only presentation history")
	var recorded_order := make_order()
	var recorded := outcome(recorded_order, true)
	check(recorded_order.record_result(recorded) and actor.set_order(recorded_order), "An upstream-recorded outcome can be bound")
	check(actor.apply_service_result(recorded) and not actor.apply_service_result(recorded), "An already-recorded matching result presents exactly once")
	check(recorded_order.get_results().size() == 1, "Presentation does not append an already-recorded result")
	var conflicting := ServiceResult.create(recorded.get_snapshot().handoff_id, recorded_order.order_id,
		recorded_order.customer_id, &"tea", true, true)
	check(not actor.apply_service_result(conflicting), "Conflicting data with the same handoff identity cannot replace the recorded result")
	actor.set_customer_def(catalog.get_customer(&"customer_b"))
	check(actor.order == null and actor.get_presentation_snapshot().customer_id == &"customer_b", "Changing definition identity clears the old order")
	var snack := make_order(&"customer_b", &"ready_banana")
	check(actor.set_order(snack), "The same actor accepts typed ready-item orders")
	actor.arrive()
	check(actor.apply_service_result(outcome(snack, true)) and snack.fulfilled
		and int(actor.get_presentation_snapshot().review_count) == 0, "Ready-item acceptance has no invented thermal review")
	actor.queue_free()
	await frames()


func pixel_in(image: Image, region: Rect2, opaque: bool) -> Vector2i:
	var bounds := Rect2i(Vector2i(region.position), Vector2i(region.size))
	for y in range(bounds.position.y, bounds.end.y, 3):
		for x in range(bounds.position.x, bounds.end.x, 3):
			var alpha := image.get_pixel(x, y).a
			if (alpha > 0.95 if opaque else alpha == 0.0):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func pixel_global(actor: Customer, image: Image, pixel: Vector2i) -> Vector2:
	var rect := actor.get_front_rect()
	var local_point := rect.position + (Vector2(pixel) + Vector2.ONE * 0.5) / Vector2(image.get_size()) * rect.size
	return (actor.get_node("VisualRoot/BobRoot") as Node2D).to_global(local_point)


func check_geometry() -> void:
	for id: StringName in [&"customer_a", &"customer_b"]:
		var actor := make_customer(id)
		actor.set_order(make_order(id))
		actor.arrive()
		var texture := actor.get_front_texture()
		check(texture == (catalog.get_customer(id) as CustomerDef).sprite_texture, "Target alpha comes from the actual customer portrait")
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		var used := Rect2(image.get_used_rect())
		var bands: Array[Rect2] = [
			Rect2(used.position + used.size * Vector2(0.25, 0.02), used.size * Vector2(0.5, 0.23)),
			Rect2(used.position + used.size * Vector2(0.35, 0.35), used.size * Vector2(0.3, 0.3)),
			Rect2(used.position + used.size * Vector2(0.02, 0.4), used.size * Vector2(0.23, 0.4)),
			Rect2(used.position + used.size * Vector2(0.75, 0.4), used.size * Vector2(0.23, 0.4)),
		]
		var pixels: Array[Vector2i] = []
		for band in bands:
			var pixel := pixel_in(image, band, true)
			check(pixel.x >= 0, "Portrait exposes opaque head, torso and arm samples")
			if pixel.x >= 0: pixels.append(pixel)
		var transparent := pixel_in(image, Rect2(Vector2.ZERO, Vector2(image.get_size())), false)
		check(transparent.x >= 0, "Portrait has transparent bounds for negative targeting")
		for transform in [Transform2D.IDENTITY, Transform2D(0.24, Vector2(1.35, 0.72), 0.0, Vector2(430, 250)),
			Transform2D(-0.18, Vector2(-0.8, 1.2), 0.0, Vector2(720, 430))]:
			stage.transform = transform
			for pixel in pixels:
				var point := pixel_global(actor, image, pixel)
				check(actor.contains_serve_point(point), "Whole visible head/torso/arm remains targetable through parent transforms")
				check(actor.get_serve_bounds().grow(0.01).has_point(point), "Reported global target bounds contain visible target points")
			check(not actor.contains_serve_point(pixel_global(actor, image, transparent)), "Transparent portrait bounds do not become a rectangular drop target")
		stage.transform = Transform2D.IDENTITY
		var hit := pixel_global(actor, image, pixels[0])
		check(not actor.contains_serve_point(Vector2(NAN, 0)) and not actor.contains_serve_point(Vector2(INF, INF)), "Nonfinite target points are safely rejected")
		actor.hide()
		check(not actor.contains_serve_point(hit) and not actor.is_serve_enabled(), "Hidden customers cannot receive a drop")
		actor.show()
		actor.reduced_motion = false
		actor.arrive()
		check(not actor.contains_serve_point(hit), "Arriving customers are not active recipients")
		actor.reduced_motion = true
		actor.leave()
		check(not actor.contains_serve_point(hit) and not actor.is_serve_enabled(), "Departed customers are not active recipients")
		actor.queue_free()
		await frames()


func sample_motion(actor: Customer, leaving: bool) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	if leaving: actor.leave()
	else: actor.arrive()
	var deadline := Time.get_ticks_msec() + 3000
	while bool(actor.get_presentation_snapshot().moving) and Time.get_ticks_msec() < deadline:
		values.append(actor.get_presentation_snapshot())
		await process_frame
	check(not bool(actor.get_presentation_snapshot().moving), "Motion settles within a bounded time")
	values.append(actor.get_presentation_snapshot())
	return values


func check_motion() -> void:
	var actor := make_customer()
	actor.set_order(make_order())
	actor.reduced_motion = false
	var finished: Array[int] = []
	actor.departure_finished.connect(func(): finished.append(1))
	for leaving: bool in [false, true]:
		var values := await sample_motion(actor, leaving)
		var motion: Array[Dictionary] = []
		for value in values:
			if bool(value.moving): motion.append(value)
		check(motion.size() > 3, "Normal motion has multiple continuous updates")
		var bob_seen := false
		var prior_travel := -1.0
		for value in motion:
			bob_seen = bob_seen or absf((value.bob_offset as Vector2).y) > 0.1
			if float(value.travel_progress) < prior_travel - 0.0001:
				check(false, "Travel progress never reverses")
			prior_travel = float(value.travel_progress)
		check(bob_seen, "Both arrival and departure contain a gentle walking bob")
		check((actor.get_presentation_snapshot().bob_offset as Vector2).is_zero_approx(), "Settled motion has no residual bob")
		if leaving:
			var turn_clear := true
			var rear_static := true
			for value in motion:
				if float(value.turn_progress) < 1.0:
					turn_clear = turn_clear and (value.bob_offset as Vector2).is_zero_approx() and is_zero_approx(float(value.travel_progress))
				else:
					rear_static = rear_static and int(value.turn_frame) == 3
			check(turn_clear and rear_static, "Departure turns without bob, then holds one rear pose while walking away")
			check(finished.size() == 1 and not actor.is_serve_enabled(), "Departure finishes once and disables serving")
		else:
			check(actor.is_serve_enabled() and actor.state == Customer.State.ORDERING, "Arrival settles at the same bound order")
	actor.arrive()
	await create_timer(0.12).timeout
	actor.reset_presentation()
	await create_timer(1.25).timeout
	check(not bool(actor.get_presentation_snapshot().moving) and actor.order != null and finished.size() == 1,
		"Reset stops the old motion without a delayed departure callback")
	actor.arrive()
	await create_timer(0.1).timeout
	actor.reduced_motion = true
	check(not bool(actor.get_presentation_snapshot().moving) and actor.is_serve_enabled(), "Reduced motion settles an active arrival")
	actor.leave()
	check(not bool(actor.get_presentation_snapshot().moving) and finished.size() == 2, "Reduced departure finishes immediately and once")
	actor.reduced_motion = false
	actor.arrive()
	await create_timer(0.1).timeout
	stage.remove_child(actor)
	await create_timer(1.25).timeout
	check(not bool(actor.get_presentation_snapshot().moving) and finished.size() == 2, "Removing the actor cancels motion without a stale finish")
	stage.add_child(actor)
	actor.reduced_motion = true
	actor.arrive()
	check(actor.is_serve_enabled(), "A retained actor can be deliberately reused after re-entry")
	actor.queue_free()
	await frames()


func check_configured_timing() -> void:
	var actor := make_customer()
	actor.set_order(make_order())
	actor.reduced_motion = false
	actor.set_process(false)
	for duration: float in [0.7, 1.15, 1.7]:
		actor.presentation.total_duration = duration
		for leaving: bool in [false, true]:
			actor.reset_presentation()
			if leaving: actor.leave()
			else: actor.arrive()
			actor._process(duration - 0.005)
			check(bool(actor.get_presentation_snapshot().moving), "Arrival and total departure stay active until the configured duration")
			actor._process(0.005)
			check(not bool(actor.get_presentation_snapshot().moving), "Arrival and complete departure finish at the same configured duration")
			check(actor.visible != leaving, "Exact completion applies the correct final visibility")
	actor.queue_free()
	await frames()


func check_order_rebind_motion() -> void:
	var actor := make_customer()
	actor.reduced_motion = false
	actor.set_process(false)
	actor.arrive()
	actor._process(0.2)
	var original := make_order()
	check(actor.set_order(original) and bool(actor.get_presentation_snapshot().moving)
		and actor.state == Customer.State.ARRIVING, "An initial order can bind during the existing arrival")
	actor._process(2.0)
	var finished: Array[int] = []
	actor.departure_finished.connect(func(): finished.append(1))
	actor.leave()
	actor._process(0.2)
	check(actor.set_order(original) and bool(actor.get_presentation_snapshot().moving), "Rebinding the same authority does not restart its departure")
	var replacement := make_order()
	check(actor.set_order(replacement), "A new order can replace a departing order")
	var snapshot := actor.get_presentation_snapshot()
	check(actor.order == replacement and actor.is_visible_in_tree() and actor.is_serve_enabled()
		and not bool(snapshot.moving) and (snapshot.depth_offset as Vector2).is_zero_approx()
		and (snapshot.bob_offset as Vector2).is_zero_approx() and (snapshot.depth_scale as Vector2).is_equal_approx(Vector2.ONE),
		"New-order binding cancels the old departure and restores the front-facing resting pose")
	actor._process(3.0)
	check(finished.is_empty() and actor.order == replacement and actor.is_visible_in_tree() and actor.is_serve_enabled(),
		"Old departure cannot hide the replacement order or emit a late finish")
	actor.queue_free()
	await frames()


func run() -> void:
	await frames()
	catalog = root.get_node("Catalog")
	stage = Node2D.new()
	root.add_child(stage)
	await check_results()
	await check_geometry()
	await check_motion()
	await check_configured_timing()
	await check_order_rebind_motion()
	stage.queue_free()
	await frames()
	print("CUSTOMER_SCENE: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
