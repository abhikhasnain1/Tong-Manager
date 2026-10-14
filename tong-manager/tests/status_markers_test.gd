extends SceneTree

const Presenter := preload("res://scripts/ui/status/vessel_status_presenter.gd")
const CONFIG := preload("res://data/balance/status_markers.tres")
const CUP := preload("res://scenes/gameplay/tools/Cup.tscn")
const KETTLE := preload("res://scenes/gameplay/tools/Kettle.tscn")
const TONG := preload("res://scenes/gameplay/tong/TongDayScreen.tscn")
const PREVIEW := preload("res://scenes/development/StatusMarkersPreview.tscn")

var checks := 0
var failures: Array[String] = []
var owned: Array[Node] = []
var catalog: Node


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


func cup() -> Cup:
	var value := CUP.instantiate() as Cup
	root.add_child(value)
	value.set_process(false)
	owned.append(value)
	return value


func kettle() -> Kettle:
	var value := KETTLE.instantiate() as Kettle
	root.add_child(value)
	value.set_process(false)
	owned.append(value)
	return value


func tokens(vessel: Node) -> Array[Dictionary]:
	return Presenter.snapshot(vessel, catalog, CONFIG)


func by_kind(snapshot: Array[Dictionary], kind: StringName) -> Dictionary:
	for entry in snapshot:
		if entry.get("kind") == kind:
			return entry
	return {}


func ingredient(snapshot: Array[Dictionary], item_id: StringName) -> Dictionary:
	for entry in snapshot:
		if entry.get("kind") == &"ingredient" and entry.get("item_id") == item_id:
			return entry
	return {}


func presentation(snapshot: Array[Dictionary]) -> String:
	var text := ""
	for entry in snapshot:
		text += String(entry.get("label", "")) + " " + String(entry.get("description", "")) + " "
	return text.to_lower()


func check_content_semantics() -> void:
	var value := cup()
	check(by_kind(tokens(value), &"fill").get("band") == &"empty", "An empty cup has an empty fill state")
	value.add_relish(&"sugar")
	var dry := tokens(value)
	check(by_kind(dry, &"fill").get("label") == "No liquid", "Dry portions are not described as an empty vessel")
	check(by_kind(dry, &"thermal").is_empty(), "A dry cup does not claim a liquid temperature")
	check(ingredient(dry, &"sugar").get("amount") == 1.0, "A pre-added spoon is present before tea")
	value.receive_liquid(&"black_tea", 125.0, 70.0, {&"sugar": 0.5, &"condensed_milk": 0.25})
	var snapshot := tokens(value)
	check(ingredient(snapshot, &"sugar").get("amount") == 1.5, "Marker combines direct and inherited portions without rounding")
	check(ingredient(snapshot, &"condensed_milk").get("amount") == 0.25, "A fractional milk transfer remains visible")
	check(ingredient(snapshot, &"sugar").get("icon") == catalog.items[&"sugar"].icon, "Sugar uses the exact shared pantry texture resource")
	check(ingredient(snapshot, &"condensed_milk").get("icon") == catalog.items[&"condensed_milk"].icon, "Milk uses the exact shared pantry texture resource")
	check(not String(ingredient(snapshot, &"condensed_milk").get("amount_text", "")).is_empty(), "Fractional texture markers include an amount label")
	check(by_kind(snapshot, &"fill").get("liquid_id") == &"black_tea", "Liquid identity stays separate from added portions")
	check(by_kind(snapshot, &"fill").get("band") != &"full", "FILLED lifecycle does not falsely show a partial cup as full")
	check(value.state == Cup.CupState.FILLED and not presentation(snapshot).contains("ready"), "FILLED does not become an order-readiness claim")
	var counts := value.get_ingredient_amounts()
	snapshot[0]["label"] = "MUTATED COPY"
	ingredient(snapshot, &"sugar")["amount"] = 1000.0
	check(value.get_ingredient_amounts() == counts and not presentation(tokens(value)).contains("mutated"), "Presentation snapshots cannot mutate gameplay contents or future snapshots")
	value.apply_ingredient(&"sugar", 100, &"mix")
	check(ingredient(tokens(value), &"sugar").get("amount") == 101.5, "Markers preserve extra portions without an arbitrary cap")
	value.receive_liquid(&"black_tea", 1.0, 70.0, {&"trace_spice": 0.0000001})
	var unknown := ingredient(tokens(value), &"trace_spice")
	check(not unknown.is_empty() and unknown.get("amount", 0.0) > 0.0, "Unknown positive trace ingredients are retained")
	check(unknown.get("icon") == null and not String(unknown.get("label", "")).is_empty(), "Missing catalog artwork has a named fallback")
	check(String(unknown.get("amount_text", "0")) != "0", "A tiny positive amount never displays as zero")
	value.temperature = value.config.cold_temperature - 1.0
	var cold := tokens(value)
	check(by_kind(cold, &"thermal").get("band") == &"cool", "Cold contents get informational thermal feedback")
	check(not presentation(cold).contains("unservable") and not presentation(cold).contains("rejected"), "Cold feedback does not invent a service rejection")
	check(value.can_receive_liquid(&"black_tea"), "Reading a cold marker does not disable vessel use")
	for state_text in [presentation(dry), presentation(cold), presentation(tokens(value))]:
		check(not state_text.contains(" ml") and not state_text.contains("°") and not state_text.contains("celsius"), "Player-facing marker text avoids exact volume and temperature readouts")
	value.mark_served()
	check(by_kind(tokens(value), &"cleanliness").get("band") == &"served", "Served lifecycle is distinct from a clean cup")
	value.mark_dirty()
	value.discard_contents()
	var discarded := tokens(value)
	check(by_kind(discarded, &"cleanliness").get("band") == &"dirty", "Discarding contents never washes the dirty marker")
	check(by_kind(discarded, &"fill").get("band") == &"empty" and ingredient(discarded, &"sugar").is_empty(), "Discard clears old fill and portions immediately")
	value.reset_clean()
	check(by_kind(tokens(value), &"cleanliness").is_empty(), "A clean cup adds no redundant cleanliness decoration")
	var custom := ItemDef.new()
	custom.id = &"marker_test_spice"
	custom.unit = &"piece"
	custom.portion_label = "Test spice"
	custom.pantry_order = -10
	custom.icon = catalog.items[&"black_tea"].icon
	catalog.items[custom.id] = custom
	value.apply_ingredient(custom.id, 2, &"mix")
	value.add_relish(&"sugar")
	var custom_snapshot := tokens(value)
	var ingredient_ids: Array[StringName] = []
	for entry in custom_snapshot:
		if entry.kind == &"ingredient": ingredient_ids.append(entry.item_id)
	check(ingredient_ids[0] == custom.id, "Configured pantry order determines stable ingredient order")
	check(ingredient(custom_snapshot, custom.id).get("icon") == custom.icon, "New configured items reuse their shared pantry image")
	custom.icon = catalog.items[&"condensed_milk"].icon
	check(ingredient(tokens(value), custom.id).get("icon") == custom.icon, "A live catalog image change is reflected without a cached parallel asset list")
	catalog.items.erase(custom.id)
	check(not ingredient(tokens(value), custom.id).is_empty(), "Removing a catalog definition does not hide retained vessel contents")
	check(Presenter.snapshot(value, null, CONFIG).size() > 0, "Missing catalog still permits named state and ingredient fallbacks")


func check_brewing_semantics() -> void:
	var source := kettle()
	source.add_water(1000.0)
	check(by_kind(tokens(source), &"fill").get("liquid_id") == &"water", "Plain water does not masquerade as brewed tea")
	check(by_kind(tokens(source), &"brew").is_empty(), "Warming water adds no redundant heating-stage marker")
	check(not by_kind(tokens(source), &"thermal").is_empty(), "Water retains its contents-temperature cue before boiling")
	source.apply_heat(20.0, 1.0)
	check(by_kind(tokens(source), &"brew").get("band") == &"boiling", "Boiling plain water has a brewing-state marker")
	check(by_kind(tokens(source), &"thermal").is_empty(), "Boiling bubbles replace a duplicate hot marker")
	check(by_kind(tokens(source), &"heating").is_empty(), "Hot water without an active burner has no burner-on marker")
	source.apply_ingredient(&"black_tea", 5, &"infuse", &"black_tea")
	var brewing := tokens(source)
	check(ingredient(brewing, &"black_tea").get("amount") == 5.0, "A configured five-bag batch displays all five portions")
	check(ingredient(brewing, &"black_tea").get("icon") == catalog.items[&"black_tea"].icon, "Tea uses the exact shared pantry image")
	check(by_kind(brewing, &"brew").get("band") == &"steeping", "Infusing bags do not immediately claim a finished brew")
	source.is_held = true
	source.advance_brewing(source.config.steep_seconds)
	check(source.state == Kettle.BrewState.LIQUOR_READY, "Held off-stove brewing still progresses to a finished batch")
	check(by_kind(tokens(source), &"brew").is_empty() and by_kind(tokens(source), &"fill").get("liquid_id") == &"black_tea",
		"Finished tea is conveyed by its liquid identity without a redundant done marker")
	check(by_kind(tokens(source), &"heating").is_empty(), "Held kettle does not claim applied stove heat")
	source.is_held = false
	source.temperature = source.config.cold_temperature - 1.0
	var receiver := cup()
	check(source.can_pour_into(receiver), "A cold brewed batch remains pourable")
	check(by_kind(tokens(source), &"thermal").get("band") == &"cool", "A cold brewed kettle keeps its independent thermal marker")
	source.advance_brewing(source.config.oversteep_seconds)
	var oversteeped := presentation(tokens(source))
	check(by_kind(tokens(source), &"brew").get("band") == &"oversteeped" and not oversteeped.contains("sour"), "Oversteeped feedback introduces no souring mechanic")
	source.discard_contents()
	check(by_kind(tokens(source), &"brew").is_empty() and ingredient(tokens(source), &"black_tea").is_empty(), "Emptying a kettle clears old brewing and ingredient markers")
	source.add_water(100.0)
	source.apply_ingredient(&"other_bag", 1, &"infuse", &"herbal_drink")
	check(by_kind(tokens(source), &"fill").get("liquid_id") == &"herbal_drink", "Configured infusion output is not hardcoded to black tea")


func check_poured_quality() -> void:
	var source := kettle()
	var value := cup()
	source.add_water(500.0)
	source.apply_heat(100.0, 1.0)
	source.apply_ingredient(&"black_tea", 1, &"infuse", &"black_tea")
	check(source.start_pour(value), "Underbrewed marker fixture uses a real pour")
	source.update_pour(.1)
	source.stop_pour()
	var early := by_kind(tokens(value), &"brew")
	check(early.get("band") == &"underbrewed" and early.get("label") == "Underbrewed", "Poured early tea retains an exceptional quality cue")
	check(not String(early.get("description", "")).contains("Steeping"), "Cup warning does not imply the cup continues brewing")
	source.advance_brewing(source.config.steep_seconds)
	check(by_kind(tokens(value), &"brew").get("band") == &"underbrewed", "Source reaching ready cannot improve already poured cup history")
	source.start_pour(value)
	source.update_pour(.1)
	source.stop_pour()
	check(by_kind(tokens(value), &"brew").get("band") == &"underbrewed", "Adding ready tea cannot hide an earlier underbrewed contribution")
	source.advance_brewing(source.config.oversteep_seconds)
	source.start_pour(value)
	source.update_pour(.1)
	source.stop_pour()
	var mixed := tokens(value)
	check(by_kind(mixed, &"brew").get("band") == &"oversteeped", "A mixed cup retains its worst quality warning")
	check(String(by_kind(mixed, &"brew").get("description", "")).contains("underbrewed"), "Mixed quality description retains the earlier underbrewed history")
	check(mixed.filter(func(token: Dictionary) -> bool: return token.kind == &"brew").size() == 1, "A mixed cup has only one exceptional quality marker")
	check(value.can_receive_liquid(&"black_tea") and not presentation(mixed).contains("unservable"), "Quality cue remains informational and does not gate imperfect service")
	source.discard_contents()
	check(by_kind(tokens(value), &"brew").get("band") == &"oversteeped", "Warning survives source disposal because cup history owns it")
	value.discard_contents()
	check(by_kind(tokens(value), &"brew").is_empty(), "Discard clears obsolete cup-quality warnings")
	value.receive_liquid(&"water", 15.0)
	check(by_kind(tokens(value), &"brew").is_empty(), "Plain water adds no tea-quality warning")
	value.reset_clean()
	source.add_water(500.0)
	source.apply_ingredient(&"black_tea", 1, &"infuse", &"black_tea")
	source.advance_brewing(source.config.steep_seconds)
	source.start_pour(value)
	source.update_pour(.1)
	source.stop_pour()
	check(by_kind(tokens(value), &"brew").is_empty(), "Ordinary ready tea adds no redundant ready tick")


func check_controls_ignore(node: Node) -> void:
	if node is Control:
		check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE,
			"Marker Control %s cannot swallow world pointer or keyboard focus" % node.name)
	for child in node.get_children(): check_controls_ignore(child)


func check_layout(layer: ObjectStatusBadgeLayer, label: String) -> void:
	var rectangles: Array[Rect2] = []
	for vessel in layer.get_vessels():
		var badge := layer.get_badge_for(vessel)
		check(badge != null, label + ": every live vessel has one badge")
		if badge == null or not badge.visible: continue
		var rect := Rect2(badge.position, badge.get_badge_size())
		check(root.get_visible_rect().encloses(rect), label + ": marker remains inside the logical viewport")
		for previous in rectangles:
			check(not rect.intersects(previous), label + ": nearby vessel marker groups do not overlap")
		for other in layer.get_vessels():
			if other.is_visible_in_tree():
				var body := layer.get_vessel_bounds(other)
				check(not body.has_area() or not rect.intersects(body), label + ": marker group leaves vessel hit bodies uncovered")
		rectangles.append(rect)


func reveal_for_layout(layer: ObjectStatusBadgeLayer, vessel: Node) -> void:
	# This suite isolates elapsed presentation from native pointer picking, which
	# the rendered probe covers separately using real Cup/Kettle input events.
	var interaction: InteractionController = vessel.controller
	vessel.controller = null
	vessel._on_hover(true)
	layer._process(maxf(CONFIG.hover_rise_seconds, CONFIG.hover_fade_in_seconds) + 0.01)
	vessel.controller = interaction
	check(layer.get_badge_for(vessel).visible and is_equal_approx(layer.get_badge_for(vessel).modulate.a, 1.0),
		"Layout fixture reveals the actual owner's group before checking its bounds")


func check_hover_animation() -> void:
	var scope := Node2D.new()
	root.add_child(scope)
	var first := CUP.instantiate() as Cup
	var second := CUP.instantiate() as Cup
	scope.add_child(first)
	scope.add_child(second)
	for value in [first, second]:
		value.position = root.get_visible_rect().size * 0.5
		value.set_process(false)
	var layer := ObjectStatusBadgeLayer.new()
	root.add_child(layer)
	layer.bind_scope(scope)
	layer.set_process(false)
	var a: ObjectStatusBadge = layer.get_badge_for(first)
	var b: ObjectStatusBadge = layer.get_badge_for(second)
	check(not a.visible and not b.visible and a.modulate.a == 0.0 and b.modulate.a == 0.0,
		"Unhovered owners start fully hidden without discarding their readable state")
	check(not a.get_tokens().is_empty(), "Hidden owner state stays available without a visible cluster")
	first._on_hover(true)
	layer._process(CONFIG.hover_fade_in_seconds * 0.4)
	var fading_in: float = a.modulate.a
	var early_position: Vector2 = a.position
	check(a.visible and fading_in > 0.0 and fading_in < 1.0, "Hover fades in progressively")
	var local_rects: Array[Rect2] = a.get_token_rects()
	first._on_hover(false)
	layer._process(CONFIG.hover_fade_out_seconds * 0.1)
	var fading_out: float = a.modulate.a
	check(a.visible and fading_out > 0.0 and fading_out < fading_in, "Leaving reverses a partial fade without disappearing")
	var interrupted_position: Vector2 = a.position
	first._on_hover(true)
	layer._process(0.001)
	check(a.modulate.a > fading_out and a.modulate.a < 1.0, "Rapid reentry resumes from current opacity rather than restarting or jumping")
	check(a.position.distance_to(interrupted_position) < 1.0, "Rapid reentry preserves a continuous group position")
	layer._process(CONFIG.hover_rise_seconds + CONFIG.hover_fade_in_seconds)
	check(is_equal_approx(a.modulate.a, 1.0) and a.position.y < early_position.y,
		"Sustained hover completes its fade and gentle rise")
	var motion_bounds := Rect2(a.position, Vector2.ZERO)
	for _sample in 16:
		layer._process(CONFIG.hover_bob_period / 8.0)
		motion_bounds = motion_bounds.expand(a.position)
		check(a.get_token_rects() == local_rects, "Continuing smoke-like motion preserves every icon's relative placement")
		check_layout(layer, "Sustained group motion")
	check(motion_bounds.size.y > 1.0 and motion_bounds.size.x > 0.5, "Stationary sustained hover keeps drifting vertically and sideways")
	check(motion_bounds.size.y <= CONFIG.hover_bob_amplitude * 2.0 + 0.01
		and motion_bounds.size.x <= CONFIG.hover_sway_amplitude * 2.0 + 0.01,
		"Continuing group drift stays inside the configured motion envelope")
	# Both owners intentionally share the same anchor. Their body remains an
	# obstacle, but the second, fully hidden badge cannot reserve a second slot.
	first._on_hover(false)
	second._on_hover(true)
	layer._process(CONFIG.hover_fade_in_seconds)
	check(a.visible and a.modulate.a > 0.0 and b.visible and is_equal_approx(b.modulate.a, 1.0),
		"Pointer switching shows the new group while the previous group fades")
	check(not Rect2(a.position, a.get_badge_size()).intersects(Rect2(b.position, b.get_badge_size())),
		"A fading group still reserves its space against the newly hovered group")
	layer._process(CONFIG.hover_fade_out_seconds + CONFIG.hover_rise_seconds)
	check(not a.visible and a.modulate.a == 0.0 and b.visible, "Only the newly hovered group remains after the old fade finishes")
	second._on_hover(false)
	layer._process(CONFIG.hover_fade_out_seconds + 0.1)
	first._on_hover(true)
	layer._process(CONFIG.hover_rise_seconds + CONFIG.hover_fade_in_seconds)
	var first_only: Vector2 = a.position
	first._on_hover(false)
	layer._process(CONFIG.hover_fade_out_seconds + 0.1)
	second._on_hover(true)
	layer._process(CONFIG.hover_rise_seconds + CONFIG.hover_fade_in_seconds)
	check(b.position.is_equal_approx(first_only), "A fully faded peer releases its old packing slot for the next hover")
	var before_focus_loss: Vector2 = b.position
	layer.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	layer._process(CONFIG.hover_fade_out_seconds * 0.5)
	check(b.visible and b.modulate.a > 0.0 and b.modulate.a < 1.0,
		"Window focus loss fades a group despite its stale owner hover flag")
	check(absf(b.position.y - before_focus_loss.y) <= CONFIG.hover_bob_amplitude * 2.0 + 0.01,
		"A leaving group holds its rise while dissolving, with only bounded bob remaining")
	layer._process(CONFIG.hover_fade_out_seconds)
	check(not b.visible and b.modulate.a == 0.0, "Focus loss finishes with no visible stale owner markers")
	check(not layer.get_vessel_bounds(second).has_point(root.get_mouse_position()),
		"Headless focus-return fixture places the pointer outside the old owner")
	layer.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	layer._process(CONFIG.hover_fade_in_seconds)
	check(not b.visible, "Focus return does not revive a stale hover after the pointer left the owner")
	second._on_hover(false)
	layer._process(0.01)
	second._on_hover(true)
	layer._process(CONFIG.hover_fade_in_seconds)
	check(b.visible, "A fresh owner hover works normally after returning focus")
	second.hide()
	layer.refresh()
	check(not b.visible and b.modulate.a == 0.0, "Hiding an owner immediately clears even its in-progress presentation")
	second.show()
	layer._process(CONFIG.hover_fade_in_seconds)
	check(not b.visible, "Showing an owner with stale hover outside its hit region does not resurrect markers")
	second._on_hover(false)
	layer._process(0.01)
	second._on_hover(true)
	layer._process(CONFIG.hover_fade_in_seconds)
	layer.hide()
	check(not b.visible and b.modulate.a == 0.0, "Hiding the presentation layer clears its visible animation state")
	layer.show()
	layer._process(CONFIG.hover_fade_in_seconds)
	check(not b.visible, "Showing the layer does not replay a stale hover outside the owner")
	layer.queue_free()
	scope.queue_free()
	await frames()


func check_layer_lifecycle() -> void:
	var screen := TONG.instantiate() as Node2D
	root.add_child(screen)
	await frames(4)
	var layer := screen.get_node("HUDLayer/RootUI/StatusBadges") as ObjectStatusBadgeLayer
	var cups: Array[Cup] = screen.get_cups()
	var source := screen.get_node("WorldRoot/ToolLayer/KettleStation") as Kettle
	var tray := screen.get_node("WorldRoot/ToolLayer/TrayStation") as TrayStation
	for value in cups: value.set_process(false)
	source.set_process(false)
	for burner in (screen.get_node("WorldRoot/ToolLayer/StoveStation") as Stove).burners: burner.set_process(false)
	layer.refresh()
	check(layer.get_vessels().size() == cups.size() + 1, "Initial cups and kettle each have owner-bound markers")
	for vessel in layer.get_vessels():
		check(not layer.get_badge_for(vessel).visible and layer.get_badge_for(vessel).modulate.a == 0.0,
			"A newly opened stall has no unhovered floating markers")
	check_controls_ignore(layer)
	var value := cups[0]
	value.receive_liquid(&"black_tea", 125.0, 70.0, {&"condensed_milk": 0.25})
	value.add_relish(&"sugar")
	layer.refresh()
	var badge := layer.get_badge_for(value)
	check(ingredient(badge.get_tokens(), &"condensed_milk").get("amount") == 0.25, "The live layer refreshes changed owner content")
	var copy := badge.get_tokens()
	copy[0]["label"] = "MUTATED BADGE COPY"
	check(not badge.get_presentation_text().contains("MUTATED"), "External badge token snapshots cannot corrupt presentation")
	check(not value.get_node("VolumeMarker").visible and value.get_node("VolumeMarker").text.is_empty(), "Cup's replaced numerical readout is hidden and empty")
	check(not source.get_node("Status").visible and source.get_node("Status").text.is_empty(), "Kettle's replaced textual status does not compete with the markers")
	var initial_anchor := layer.get_anchor_position(value)
	var tray_transform := tray.transform
	tray.position += Vector2(-35.0, -15.0)
	layer.refresh()
	check(layer.get_badge_for(value) == badge and not layer.get_anchor_position(value).is_equal_approx(initial_anchor), "A populated tray moves the same cup's marker anchor")
	tray.transform = tray_transform
	var holder := Node2D.new()
	screen.add_child(holder)
	var original_parent := value.get_parent()
	value.reparent(holder, true)
	layer.refresh()
	check(layer.get_badge_for(value) == badge, "Same-scene reparenting preserves marker identity")
	check(layer.get_anchor_position(value).is_equal_approx(initial_anchor), "Reparenting with a preserved world transform preserves the marker anchor")
	value.reparent(original_parent, true)
	var foreign := Node2D.new()
	root.add_child(foreign)
	value.reparent(foreign, true)
	layer.refresh()
	check(layer.get_badge_for(value) == null and not layer.get_vessels().has(value), "A vessel moved outside the owning stall loses its old badge")
	value.reparent(original_parent, true)
	layer.refresh()
	check(layer.get_badge_for(value) != null, "Returning a live vessel restores one badge")
	foreign.queue_free()
	value.hide()
	layer.refresh()
	check(not layer.get_badge_for(value).visible, "Hidden vessels do not leave floating markers")
	value.show()
	layer.refresh()
	check(not layer.get_badge_for(value).visible, "Showing an unhovered vessel keeps its marker hidden")
	var spawned := CUP.instantiate() as Cup
	spawned.name = "MarkerLifecycleCup"
	holder.add_child(spawned)
	spawned.set_process(false)
	layer.refresh()
	check(layer.get_badge_for(spawned) != null, "New cup instances acquire markers without a fixed six-slot list")
	holder.remove_child(spawned)
	layer.refresh()
	check(layer.get_badge_for(spawned) == null, "Detached live cups lose their markers")
	holder.add_child(spawned)
	layer.refresh()
	check(layer.get_badge_for(spawned) != null, "A detached cup can reenter with a fresh marker")
	spawned.queue_free()
	layer.refresh()
	check(layer.get_badge_for(spawned) == null, "Queued owner deletion removes its marker before the next frame")
	await frames()
	layer.set_process(false)
	for dimensions in [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 800)]:
		root.size = dimensions
		await frames(3)
		layer.refresh()
		for vessel in layer.get_vessels():
			reveal_for_layout(layer, vessel)
			check_layout(layer, str(dimensions))
			vessel._on_hover(false)
			layer._process(CONFIG.hover_fade_out_seconds + 0.1)
		var expected: Vector2 = value.get_node("StatusBadgeAnchor").get_global_transform_with_canvas().origin
		var actual := layer.get_global_transform_with_canvas() * layer.get_anchor_position(value)
		check(actual.is_equal_approx(expected), "Owner anchor projection follows world fitting at " + str(dimensions))
		# Exercise the real reparenting/drag path at an edge where the normal
		# above-owner cluster cannot fit, instead of calling a packing helper.
		var interaction := screen.get_node("InteractionController") as InteractionController
		interaction.set_mode(InteractionController.MODE_ORGANIZE)
		var handle := value.get_node("PlacementHandle") as TablePlaceable
		var origin := value.global_transform
		var began := handle.begin_drag(value.get_global_transform_with_canvas().origin)
		check(began, "Edge-layout fixture starts a real cup drag at " + str(dimensions))
		if began:
			interaction.update_drag(Vector2(root.get_visible_rect().size.x * 0.25, 30.0))
			reveal_for_layout(layer, value)
			check(layer.get_anchor_position(value).y < layer.get_badge_for(value).get_badge_size().y,
				"Top-edge owner has insufficient space for its usual above-object markers")
			check_layout(layer, "Held near top " + str(dimensions))
			interaction.cancel_drag()
			layer.refresh()
			check(value.global_transform.is_equal_approx(origin), "Top-edge layout review preserves drag cancellation")
			value._on_hover(false)
			layer._process(CONFIG.hover_fade_out_seconds + 0.1)
		interaction.set_mode(InteractionController.MODE_NEUTRAL)
	screen.queue_free()
	await frames()


func check_preview_boundary() -> void:
	var game_state := root.get_node("GameState")
	check(game_state.ensure_inventory(), "Preview tests have the shared inventory authority")
	game_state.ensure_water_day()
	var stock_before: Dictionary = game_state.inventory.quantities
	var water_before: float = game_state.water_supply.remaining_ml
	var view := PREVIEW.instantiate()
	root.add_child(view)
	await frames(3)
	for index in view.EXAMPLES.size():
		if index == 6:
			view.controller.set_mode(InteractionController.MODE_ORGANIZE)
		var previous_mode: StringName = view.controller.current_mode
		view.apply_example(index)
		check(game_state.inventory.quantities == stock_before and game_state.water_supply.remaining_ml == water_before,
			"Development vessel example %d neither consumes nor replenishes supplies" % index)
		check(view.controller.current_mode == previous_mode, "Development example preserves the selected interaction mode")
		if index == 6:
			var first: Cup = view.screen.get_cups()[0]
			check(first.volume_ml == 250.0, "Fractional example actually fills the receiving cup")
			check(first.get_ingredient_amounts() == {&"sugar": 1.5, &"condensed_milk": 0.25},
				"Fractional example combines one direct sugar spoon with the quarter-batch transfer")
			check(view.kettle.volume_ml == 750.0 and view.kettle.get_mixed_amounts() == {&"sugar": 1.5, &"condensed_milk": 0.75},
				"Fractional example retains the unpoured mixed amounts in the kettle")
			check(view.kettle.get_infused_counts() == {&"black_tea": 5},
				"All five infusing bags stay in the kettle during the sample pour")
			check(not view.kettle.is_pouring and not view.controller.has_active_action(), "The sample pour releases its normal action lock")
		var layer := view.screen.get_node("HUDLayer/RootUI/StatusBadges") as ObjectStatusBadgeLayer
		layer.refresh()
		check(not layer.get_badge_for(view.kettle).get_tokens().is_empty(), "Each development example uses the real live marker layer")
	view.clear_vessels()
	check(not view.kettle.has_contents(), "Clear returns the kettle to ordinary manual brewing")
	for value in view.screen.get_cups(): check(not value.has_contents(), "Clear removes each development cup's contents")
	check(game_state.inventory.quantities == stock_before and game_state.water_supply.remaining_ml == water_before, "Clearing examples never refunds or resets supplies")
	check(not view.controller.is_dragging() and not view.controller.is_world_input_blocked(), "Development controls leave normal world interaction available")
	view.queue_free()
	await frames()


func run() -> void:
	catalog = root.get_node("Catalog")
	check_content_semantics()
	check_brewing_semantics()
	check_poured_quality()
	for node in owned:
		if is_instance_valid(node): node.queue_free()
	await frames()
	await check_hover_animation()
	await check_layer_lifecycle()
	await check_preview_boundary()
	print("STATUS_MARKERS: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
