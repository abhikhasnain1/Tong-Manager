extends SceneTree

var checks := 0
var failures: Array[String] = []
var apply_count := 0
var callback_provider: DevelopmentPortionStock
var callback_token := 0
var preview: Node
var screen: Node2D
var controller: InteractionController
var stock: DevelopmentPortionStock
var world: Node2D
var reserve_source: IngredientPortionSource
var reserve_action := ""
var reserve_reentry_allowed := false
var resolution_source: IngredientPortionSource
var resolution_new_drag := false
var resolution_canceled := 0
var resolution_dropped := 0
var resolution_change_mode := false

func _on_resolution_changed() -> void:
	controller.cancel_drag()
	resolution_new_drag = resolution_source.begin_portion(resolution_source.source_owner.get_global_transform_with_canvas().origin)
	if resolution_change_mode:
		controller.set_mode(InteractionController.MODE_ORGANIZE)

func _on_resolution_canceled(_payload: HeldItemPayload) -> void:
	resolution_canceled += 1

func _on_resolution_dropped(_payload: HeldItemPayload, _zone: DropZone) -> void:
	resolution_dropped += 1

func verify_resolution_callbacks(sugar: IngredientPortionSource, milk: IngredientPortionSource, cup: Cup) -> void:
	resolution_source = milk
	controller.drag_canceled.connect(_on_resolution_canceled)
	controller.drag_dropped.connect(_on_resolution_dropped)
	for action in ["cancel","commit","commit_and_mode"]:
		controller.set_mode(InteractionController.MODE_INTERACT)
		cup.reset_clean()
		cup.receive_liquid(&"black_tea",150,65)
		var before_sugar := stock.remaining(&"sugar")
		var before_milk := stock.available(&"condensed_milk")
		take(sugar)
		resolution_canceled = 0
		resolution_dropped = 0
		resolution_new_drag = false
		resolution_change_mode = action == "commit_and_mode"
		stock.changed.connect(_on_resolution_changed,CONNECT_ONE_SHOT)
		if action == "cancel":
			controller.cancel_drag()
		else:
			controller.release_drop(cup.get_node("IngredientTarget").get_global_transform_with_canvas().origin)
		check(not resolution_new_drag and controller.current_payload == null,"A %s stock observer cannot replace the resolving gesture" % action)
		check(stock.available(&"condensed_milk") == before_milk,"A %s observer cannot reserve or charge a second ingredient" % action)
		if action == "cancel":
			check(resolution_canceled == 1 and resolution_dropped == 0,"Cancellation observers receive one cancel and no drop")
			check(stock.available(&"sugar") == before_sugar and cup.relish_item_ids.is_empty(),"Reentrant cancellation returns stock without applying an ingredient")
		else:
			check(resolution_canceled == 0 and resolution_dropped == 1,"A %s produces exactly one drop and no cancel event" % action)
			check(stock.remaining(&"sugar") == before_sugar - 1 and cup.relish_item_ids == [&"sugar"],"A %s applies and charges one ingredient despite synchronous callbacks" % action)
		if resolution_change_mode:
			check(controller.current_mode == InteractionController.MODE_ORGANIZE,"A requested mode change occurs after the accepted gesture finishes")
	controller.drag_canceled.disconnect(_on_resolution_canceled)
	controller.drag_dropped.disconnect(_on_resolution_dropped)
	controller.set_mode(InteractionController.MODE_INTERACT)

func _on_reserve_changed() -> void:
	match reserve_action:
		"reset":
			stock.reset_fixture()
		"replace":
			reserve_source.set_provider(DevelopmentPortionStock.new())
		"replace_and_restore":
			reserve_source.set_provider(null)
			reserve_source.set_provider(stock)
		"detach":
			reserve_source.get_parent().remove_child(reserve_source)
		"detach_owner":
			reserve_source.source_owner.get_parent().remove_child(reserve_source.source_owner)
		"queue_delete":
			reserve_source.queue_free()
		"reenter":
			reserve_reentry_allowed = reserve_source.begin_portion(Vector2.ZERO)

func verify_reserve_callbacks(existing: IngredientPortionSource) -> void:
	for action in ["reset","replace","replace_and_restore","detach","detach_owner","queue_delete","reenter"]:
		reserve_action = action
		reserve_source = IngredientPortionSource.new()
		existing.source_owner.add_child(reserve_source)
		reserve_source.configure(controller,existing.item_id,existing.unit,existing.source_owner.get_node("PlacementBody"),existing.placement_handle)
		reserve_source.set_provider(stock)
		var before := stock.remaining(existing.item_id)
		var source_parent := existing.source_owner.get_parent()
		var before_visuals := controller.drag_layer.get_child_count()
		stock.changed.connect(_on_reserve_changed,CONNECT_ONE_SHOT)
		var began := reserve_source.begin_portion(existing.source_owner.get_global_transform_with_canvas().origin)
		if action == "reenter":
			check(began and not reserve_reentry_allowed,"A synchronous reservation listener cannot begin another pickup on the same source")
			controller.cancel_drag()
		else:
			check(not began,"Synchronous %s during reservation rejects the stale gesture" % action)
		check(controller.current_payload == null and not controller.is_dragging(),"Reservation %s leaves no active invalid payload" % action)
		check(stock.remaining(existing.item_id) == before and stock.available(existing.item_id) == before,"Reservation %s releases only the original reservation without consuming stock" % action)
		check(controller.drag_layer.get_child_count() == before_visuals + (1 if action == "reenter" else 0),"Reservation %s creates no orphaned held visual" % action)
		if existing.source_owner.get_parent() == null:
			source_parent.add_child(existing.source_owner)
		if is_instance_valid(reserve_source):
			reserve_source.free()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _apply_counted() -> bool:
	apply_count += 1
	return true

func _reject_application() -> bool:
	return false

func _reentrant_application() -> bool:
	check(not callback_provider.commit(callback_token,_apply_counted),"An in-flight token cannot re-enter target application")
	check(not callback_provider.reset_fixture(),"A synchronous model signal cannot reset stock halfway through a commit")
	apply_count += 1
	return true

func source_named(name: String) -> IngredientPortionSource:
	return screen.get_node("WorldRoot/ToolLayer/ReadyItemRail/%s/IngredientSource" % name) as IngredientPortionSource

func take(source: IngredientPortionSource) -> HeldItemPayload:
	var before := source.source_owner.global_transform
	var parent := source.source_owner.get_parent()
	check(source.begin_portion(source.source_owner.get_global_transform_with_canvas().origin),"%s begins one portion through the guarded source" % source.item_id)
	check(source.source_owner.get_parent() == parent and source.source_owner.global_transform.is_equal_approx(before),"Taking a portion leaves the entire source in place")
	return controller.current_payload

func cancel_and_check(item_id: StringName, before: int, label: String) -> void:
	var ghost := controller.current_drag_node
	controller.cancel_drag()
	check(controller.current_payload == null and not controller.is_dragging(),"%s clears the active payload" % label)
	check(not is_instance_valid(ghost) or ghost.is_queued_for_deletion(),"%s disposes its transient visual" % label)
	check(stock.remaining(item_id) == before and stock.available(item_id) == before,"%s consumes nothing and releases the reservation" % label)

func apply_to(source: IngredientPortionSource, target: Node2D, item_id: StringName, label: String) -> HeldItemPayload:
	var before := stock.remaining(item_id)
	var payload := take(source)
	controller.release_drop(target.get_node("IngredientTarget").get_global_transform_with_canvas().origin)
	check(not controller.is_dragging() and stock.remaining(item_id) == before - 1,"%s commits one shared stock deduction" % label)
	check(stock.available(item_id) == stock.remaining(item_id),"%s leaves no reserved stock" % label)
	return payload

func reject_at(source: IngredientPortionSource, target: Node2D, label: String) -> void:
	var before := stock.remaining(source.item_id)
	take(source)
	var zone := target.get_node("IngredientTarget") as IngredientPortionTarget
	controller.update_drag(zone.get_global_transform_with_canvas().origin)
	check(controller.hovered_drop_zone == zone and not zone.accepts(controller.current_payload).is_valid,"%s identifies the intended invalid target" % label)
	controller.release_drop(zone.get_global_transform_with_canvas().origin)
	check(not controller.is_dragging() and stock.remaining(source.item_id) == before and stock.available(source.item_id) == before,"%s returns the portion without applying or charging" % label)

func verify_provider() -> void:
	var missing := PortionStockProvider.new()
	check(missing.available(&"sugar") == 0 and missing.reserve(&"sugar",&"spoonful",1,10) == 0,"Base provider creates no production inventory")
	var provider := DevelopmentPortionStock.new()
	check(provider.remaining(&"black_tea") == 6 and provider.remaining(&"sugar") == 12 and provider.remaining(&"condensed_milk") == 12,"Fixture has explicit finite counts in approved portion forms")
	for args in [[&"black_tea",&"g",1,10],[&"sugar",&"spoonful",0,10],[&"sugar",&"spoonful",1,0],[&"coffee",&"spoonful",1,10]]:
		check(provider.reserve(args[0],args[1],args[2],args[3]) == 0,"Invalid unit/item/quantity/source cannot reserve stock")
	var token := provider.reserve(&"sugar",&"spoonful",1,10)
	check(token > 0 and provider.remaining(&"sugar") == 12 and provider.available(&"sugar") == 11,"Reservation reduces availability without consuming stock")
	check(provider.reservation_matches(token,&"sugar",&"spoonful",1,10),"Reservation binds item, unit, quantity and source identity")
	check(not provider.reservation_matches(token,&"sugar",&"spoonful",1,11),"Another jar cannot claim an existing reservation")
	check(not provider.reservation_matches(token,&"condensed_milk",&"spoonful",1,10),"Changing the item cannot reuse its reservation")
	provider.release(token)
	provider.release(token)
	check(provider.available(&"sugar") == 12 and provider.remaining(&"sugar") == 12,"Repeated cancellation restores exactly one reservation")
	token = provider.reserve(&"sugar",&"spoonful",1,10)
	check(provider.commit(token,_apply_counted) and apply_count == 1 and provider.remaining(&"sugar") == 11,"Successful commit applies and deducts once")
	check(not provider.commit(token,_apply_counted) and apply_count == 1,"Repeated command does not duplicate its target effect")
	provider.release(token)
	check(provider.remaining(&"sugar") == 11,"Cleanup after commit does not refund used contents")
	token = provider.reserve(&"sugar",&"spoonful",1,20)
	check(not provider.commit(token,_reject_application) and provider.remaining(&"sugar") == 11 and provider.available(&"sugar") == 11,"Failed target application restores stock and releases its token")
	callback_provider = provider
	callback_token = provider.reserve(&"sugar",&"spoonful",1,20)
	check(provider.commit(callback_token,_reentrant_application) and apply_count == 2 and provider.remaining(&"sugar") == 10,"Synchronous re-entry still produces one effect and charge")
	var first_jar := provider.reserve(&"sugar",&"spoonful",6,10)
	check(first_jar > 0 and provider.reserve(&"sugar",&"spoonful",5,20) == 0,"Two sugar jars share the same available balance")
	provider.release(first_jar)
	token = provider.reserve(&"black_tea",&"teabag",1,10)
	provider.reset_fixture()
	var fresh := provider.reserve(&"black_tea",&"teabag",1,10)
	check(fresh != token and not provider.commit(token,_apply_counted),"Reset invalidates old portions without token reuse")
	provider.release(fresh)
	for index in 6:
		token = provider.reserve(&"black_tea",&"teabag",1,10)
		check(provider.commit(token,_apply_counted),"Finite tea portion %d commits" % (index+1))
	check(provider.available(&"black_tea") == 0 and provider.reserve(&"black_tea",&"teabag",1,20) == 0,"Depleted stock cannot create another portion")

func run() -> void:
	verify_provider()
	root.size = Vector2i(1920,1080)
	var production: Node2D = load("res://scenes/gameplay/tong/TongDayScreen.tscn").instantiate()
	root.add_child(production)
	await process_frame
	var production_controller := production.get_node("InteractionController") as InteractionController
	production_controller.set_mode(InteractionController.MODE_INTERACT)
	for source in production.portion_sources:
		check(source.provider == null and not source.begin_portion(source.source_owner.get_global_transform_with_canvas().origin),"Normal scene source waits for an injected production provider")
	production.queue_free()
	await process_frame
	preview = load("res://scenes/development/BrewingPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await physics_frame
	screen = preview.screen
	controller = preview.controller
	stock = preview.portion_stock
	world = screen.get_node("WorldRoot")
	var tea := source_named("TeaBox")
	var sugar := source_named("SugarCan")
	var sugar_other := source_named("SugarCanEnglish")
	var milk := source_named("CondensedMilkCan")
	var kettle := preview.kettle as Kettle
	var cups: Array[Cup] = screen.get_cups()
	var cup := cups[0]
	kettle.set_process(false)
	for candidate in cups:
		candidate.set_process(false)
	for burner in preview.stove.burners:
		burner.set_process(false)
	check(controller.current_mode == InteractionController.MODE_NEUTRAL,"Preview begins in real Neutral rather than extracting by default")
	check(not tea.begin_portion(tea.source_owner.global_position),"Neutral cannot take a portion")
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	check(not tea.begin_portion(tea.source_owner.global_position),"Organize never extracts source contents")
	controller.set_mode(InteractionController.MODE_INTERACT)
	check(tea.provider == stock and sugar.provider == stock and sugar_other.provider == stock and milk.provider == stock,"All physical sources share one explicitly injected fixture provider")
	verify_reserve_callbacks(sugar)
	await process_frame
	var payload := take(tea)
	if payload == null:
		preview.queue_free()
		await process_frame
		quit(1)
		return
	check(payload.item_id == &"black_tea" and payload.quantity == 1 and payload.metadata.unit == &"teabag" and payload.metadata.source_id == tea.source_owner.get_instance_id(),"Tea payload records one teabag and its actual source identity")
	check(payload.metadata.transient and payload.metadata.cursor_state == &"teabag", "Portion visual and cursor are separate from whole-container placement")
	check(stock.remaining(&"black_tea") == 6 and stock.available(&"black_tea") == 5,"Pickup reserves without consuming tea")
	cancel_and_check(&"black_tea",6,"Explicit cancellation")
	reject_at(tea,kettle,"Empty kettle")
	kettle.add_water(700)
	reject_at(tea,kettle,"Cold water")
	kettle.temperature = kettle.config.boiling_temperature
	payload = apply_to(tea,kettle,&"black_tea","Tea into boiling kettle")
	check(kettle.contains_tea and kettle.state == Kettle.BrewState.STEEPING,"Teabag fixture enters the existing brew progression")
	var tea_zone := kettle.get_node("IngredientTarget") as IngredientPortionTarget
	check(not tea_zone.try_apply_drop(payload) and stock.remaining(&"black_tea") == 5,"Duplicate accepted drop cannot add or debit another teabag")
	reject_at(tea,kettle,"Already brewed kettle")
	reject_at(sugar,kettle,"Spoon-to-kettle remains outside this fixture")
	reject_at(milk,cup,"Empty cup")
	cup.receive_liquid(&"water",100,60)
	reject_at(sugar,cup,"Cup contains incompatible liquid")
	cup.reset_clean()
	cup.receive_liquid(&"black_tea",175,67)
	var volume := cup.volume_ml
	var temperature := cup.temperature
	payload = apply_to(sugar,cup,&"sugar","Sugar spoon")
	check(cup.relish_item_ids == [&"sugar"] and sugar_other.provider.remaining(&"sugar") == 11,"One sugar source updates the same stock seen by its other visual")
	var cup_zone := cup.get_node("IngredientTarget") as IngredientPortionTarget
	check(not cup_zone.try_apply_drop(payload) and cup.relish_item_ids.size() == 1,"Duplicate spoon payload cannot repeat target mutation")
	apply_to(milk,cup,&"condensed_milk","Milk spoon")
	check(cup.relish_item_ids == [&"sugar",&"condensed_milk"] and cup.volume_ml == volume and cup.temperature == temperature,"Abstract fixture spoon preserves liquid volume and temperature")
	reject_at(tea,cup,"Cup teabag brewing remains outside this fixture")
	apply_to(sugar_other,cup,&"sugar","Other sugar source")
	reject_at(milk,cup,"Current garnish capacity")
	check(cup.relish_item_ids.size() == 3,"Rejected fourth portion leaves existing garnishes intact")
	cup.mark_served()
	reject_at(milk,cup,"Served cup")
	cup.mark_dirty()
	reject_at(sugar,cup,"Dirty cup")
	# Mode, focus and explicit UI blocking all release the same reservation.
	for cause in ["neutral","organize","focus","modal"]:
		controller.set_mode(InteractionController.MODE_INTERACT)
		var before := stock.remaining(&"sugar")
		take(sugar)
		if cause == "neutral":
			controller.set_mode(InteractionController.MODE_NEUTRAL)
		elif cause == "organize":
			controller.set_mode(InteractionController.MODE_ORGANIZE)
		elif cause == "focus":
			controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		else:
			controller.set_world_input_blocked(screen,true)
		check(not controller.is_dragging() and controller.current_payload == null and stock.remaining(&"sugar") == before and stock.available(&"sugar") == before,"%s cancels without stock loss" % cause)
		controller.set_world_input_blocked(screen,false)
	controller.set_mode(InteractionController.MODE_INTERACT)
	controller.set_world_input_blocked(screen,true)
	check(not sugar.begin_portion(sugar.source_owner.global_position),"An open modal blocks source extraction")
	controller.set_world_input_blocked(screen,false)
	var before_sugar := stock.remaining(&"sugar")
	take(sugar)
	var visual := controller.current_drag_node
	visual.queue_free()
	await process_frame
	await process_frame
	check(not controller.is_dragging() and controller.current_payload == null and stock.available(&"sugar") == before_sugar,"Removing a transient visual releases its reservation without mouse movement")
	take(sugar)
	sugar.set_provider(null)
	check(not controller.is_dragging() and stock.available(&"sugar") == before_sugar,"Changing a source provider invalidates its outstanding portion")
	sugar.set_provider(stock)
	take(milk)
	stock.reset_fixture()
	await process_frame
	check(not controller.is_dragging() and stock.available(&"condensed_milk") == 12,"Fixture reset invalidates a held old token without pointer motion")
	take(milk)
	var source_parent := milk.get_parent()
	source_parent.remove_child(milk)
	check(not controller.is_dragging() and stock.available(&"condensed_milk") == 12,"Removing the source adapter releases a held portion immediately")
	source_parent.add_child(milk)
	# A nearest invalid cup must not yield to a valid cup in the same snap radius.
	cup.reset_clean()
	cups[1].reset_clean()
	controller.set_mode(InteractionController.MODE_ORGANIZE)
	for record in [[cup,Vector2(915,855)],[cups[1],Vector2(915,870)]]:
		var moving := record[0] as Cup
		var handle := moving.get_node("PlacementHandle") as TablePlaceable
		check(handle.begin_drag(moving.get_global_transform_with_canvas().origin),"Crowded fixture starts a real free-placement command")
		controller.release_drop(world.get_global_transform_with_canvas()*record[1])
		check(handle.surface == screen.table_surface,"Crowded target fixture is legitimately placed on table")
	cup.receive_liquid(&"black_tea",170,70)
	cups[1].receive_liquid(&"black_tea",170,70)
	cups[1].mark_served()
	cups[1].mark_dirty()
	controller.set_mode(InteractionController.MODE_INTERACT)
	reject_at(sugar,cups[1],"Nearest dirty cup beside an eligible cup")
	check(cup.relish_item_ids.is_empty(),"Valid neighbour cannot steal a portion aimed at a dirty cup")
	apply_to(milk,cup,&"condensed_milk","Moved cup target")
	check(cup.get_parent() == screen.get_node("WorldRoot/ToolLayer/ReadyItemRail"),"Ingredient target follows the same table-owned cup")
	var target_zone := cup.get_node("IngredientTarget") as IngredientPortionTarget
	var before_milk := stock.remaining(&"condensed_milk")
	take(milk)
	var target_at := target_zone.get_global_transform_with_canvas().origin
	cup.remove_child(target_zone)
	controller.release_drop(target_at)
	check(not controller.is_dragging() and stock.available(&"condensed_milk") == before_milk and cup.relish_item_ids.size() == 1,"Removed target cancels without changing stock or existing cup contents")
	cup.add_child(target_zone)
	# Disposal never refunds committed ingredients.
	var used_stock := stock.remaining(&"condensed_milk")
	cup.discard_contents()
	check(stock.remaining(&"condensed_milk") == used_stock,"Contents disposal is not a portion cancellation or stock refund")
	verify_resolution_callbacks(sugar,milk,cup)
	# Removing a whole source and exiting the scene clean reservations too.
	take(sugar)
	var source_owner := sugar.source_owner
	source_owner.queue_free()
	await process_frame
	check(not controller.is_dragging() and stock.available(&"sugar") == stock.remaining(&"sugar"),"Queued source deletion cancels without waiting for mouse movement")
	take(milk)
	var before_exit := stock.remaining(&"condensed_milk")
	root.remove_child(preview)
	check(controller.current_payload == null and stock.available(&"condensed_milk") == before_exit,"Scene exit releases transient stock reservations")
	preview.free()
	await process_frame
	print("INGREDIENT_PORTIONS: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
