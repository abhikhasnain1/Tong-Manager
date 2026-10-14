extends SceneTree
## Read-only request presentation and draw sizing, separate from owner lifecycle.

const BUBBLE := preload("res://scenes/ui/CustomerOrderBubble.tscn")
var checks := 0
var failures: Array[String] = []
var catalog: Node
var bubble: CustomerOrderBubble
var sequence := 0


func _init() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func make_order(request_id: StringName) -> OrderState:
	sequence += 1
	return catalog.create_order(StringName("bubble_%d" % sequence), &"customer_a", request_id, 0.0)


func token_for(snapshot: Dictionary, item_id: StringName, kind: StringName = &"addition") -> Dictionary:
	for token: Dictionary in snapshot.tokens:
		if token.item_id == item_id and token.kind == kind: return token
	return {}


func check_bounds() -> void:
	var rects := bubble.get_token_rects()
	check(rects.size() == bubble.get_display_snapshot().tokens.size(), "Every requested cue has a drawn cell")
	check(bubble.size.is_finite() and bubble.size == bubble.get_combined_minimum_size(), "Draw size is finite and matches minimum size")
	for index in rects.size():
		check(Rect2(Vector2.ZERO, bubble.size).encloses(rects[index]), "Token cell stays inside component bounds")
		for other in range(index + 1, rects.size()):
			check(not rects[index].intersects(rects[other]), "Token cells do not overlap")
	var copy := bubble.get_token_rects()
	if not copy.is_empty():
		copy[0] = Rect2(1000, 1000, 1000, 1000)
		check(bubble.get_token_rects()[0] != copy[0], "Layout snapshots are detached")


func current_orders() -> void:
	var summaries: Dictionary = {}
	var expectations := {
		&"tea_cha_no_sugar": [], &"tea_cha": [&"sugar"],
		&"tea_dudh_cha_no_sugar": [&"condensed_milk"], &"tea_dudh_cha": [&"sugar", &"condensed_milk"],
	}
	for request_id: StringName in expectations:
		var order := make_order(request_id)
		var before := order.get_snapshot()
		bubble.set_order(order, catalog)
		var shown := bubble.get_display_snapshot()
		check(shown.valid and bubble.order == order and shown.order_id == order.order_id, "Bubble preserves supplied order identity")
		check(shown.request_id == request_id and shown.request_kind == &"tea", "Tea request identity is retained")
		check(shown.tokens.size() == 1 + expectations[request_id].size(), "Tea has a cup cue and exactly its requested cup additions")
		var tea: Dictionary = shown.tokens[0]
		check(tea.kind == &"tea" and tea.unit == &"cup" and tea.amount == 1, "Primary cue describes one cup, not one batch teabag")
		check(tea.icon == CustomerOrderBubble.CUP_ICON and tea.identity_icon == catalog.get_item(&"black_tea").icon, "Tea cup uses shared brewed-liquid artwork for identity")
		check(tea.amount_text.is_empty() and not tea.has("kettle_portion_counts"), "Batch dose is not misrepresented as a per-customer amount")
		for item_id: StringName in expectations[request_id]:
			var token := token_for(shown, item_id)
			check(token.amount == 1 and token.amount_text == "1" and token.unit == &"spoonful", "Requested spoon count/unit comes from the order snapshot")
			check(token.icon == catalog.get_item(item_id).icon, "Ingredient artwork is exactly the shared pantry icon")
		check(not summaries.has(shown.accessibility_summary), "All four teas have distinguishable accessible presentation")
		summaries[shown.accessibility_summary] = true
		check(bubble.get_accessibility_summary() == shown.accessibility_summary, "Plain-language summary matches the visible cues")
		var text := String(shown.accessibility_summary).to_lower()
		check(not text.contains("ml") and not text.contains("°") and not text.contains("ready") and not text.contains("price"), "Presentation invents no precision display, serving match or price")
		check(order.get_snapshot() == before, "Presenting an order does not change its authority")
		check_bounds()
	for request_id: StringName in [&"ready_banana", &"ready_biscuits"]:
		var order := make_order(request_id)
		bubble.set_order(order, catalog)
		var shown := bubble.get_display_snapshot()
		check(shown.tokens.size() == 1 and shown.tokens[0].kind == &"ready_item", "Ready item uses one request cue")
		var token: Dictionary = shown.tokens[0]
		check(token.icon == order.get_request().icon and token.icon == catalog.get_item(order.item_id).icon, "Ready item art is the exact shared snapshot/pantry texture")
		check(token.amount == 1 and token.unit == &"piece" and token.amount_text == "1", "Ready item preserves requested piece quantity")
		check_bounds()
	check(bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE and bubble.focus_mode == Control.FOCUS_NONE and bubble.get_child_count() == 0, "Custom drawing has no blocking controls or focus interception")


func data_driven_and_copies() -> void:
	var original := make_order(&"tea_dudh_cha")
	var request := original.get_request()
	request.cup_portion_counts = {&"condensed_milk": 2, &"sugar": 5}
	request.kettle_portion_counts[&"black_tea"] = 5
	var modified := OrderState.create(&"modified", original.customer_id, request, 0.0)
	check(modified != null, "Alternate valid recipe metadata produces a test order")
	bubble.set_order(modified, catalog)
	var shown := bubble.get_display_snapshot()
	check(shown.tokens[1].item_id == &"sugar" and shown.tokens[2].item_id == &"condensed_milk", "Addition order follows pantry order rather than dictionary insertion")
	check(token_for(shown, &"sugar").amount == 5 and token_for(shown, &"condensed_milk").amount == 2, "Configured amounts are displayed without a hardcoded one-spoon rule")
	check(shown.tokens.size() == 3 and shown.tokens[0].amount == 1, "Five batch bags still describe one requested cup")
	shown.tokens[1].amount = 999
	shown.tokens[1].icon = null
	shown["accessibility_summary"] = "changed"
	check(token_for(bubble.get_display_snapshot(), &"sugar").amount == 5 and token_for(bubble.get_display_snapshot(), &"sugar").icon != null, "Returned token dictionaries cannot mutate presentation")
	check(modified.get_request().cup_portion_counts[&"sugar"] == 5, "Presentation copies cannot mutate order state")
	request.cup_portion_counts[&"sugar"] = 20
	check(token_for(bubble.get_display_snapshot(), &"sugar").amount == 5, "Later mutation of a caller snapshot does not affect the bubble")
	var accepted := ServiceResult.create(&"served", modified.order_id, modified.customer_id, &"tea", true)
	modified.record_result(accepted)
	check(bubble.order.fulfilled and bubble.get_display_snapshot().valid, "Component retains model authority while owner controls fulfilled visibility")
	var sparse_catalog := Node.new()
	# An unavailable item catalog uses distinguishable initials and full labels;
	# it never mutates or discards the ingredient request.
	bubble.set_order(modified, sparse_catalog)
	shown = bubble.get_display_snapshot()
	check(token_for(shown, &"sugar").icon == null and token_for(shown, &"condensed_milk").icon == null, "Missing ingredient artwork has an explicit fallback")
	check(token_for(shown, &"sugar").label != token_for(shown, &"condensed_milk").label, "Fallback ingredients retain distinct human-readable identity")
	check(shown.tokens[0].identity_icon == original.get_request().icon, "Copied beverage art remains available without the item catalog")
	sparse_catalog.free()
	var extended := original.get_request()
	for index in 7:
		var identity := StringName("custom_addition_%d" % index)
		extended.relish_item_ids.append(identity)
		extended.cup_portion_counts[identity] = 10 + index
		extended.cup_portion_units[identity] = &"spoonful"
	var many := OrderState.create(&"many", original.customer_id, extended, 0.0)
	bubble.set_order(many, catalog)
	shown = bubble.get_display_snapshot()
	check(shown.tokens.size() == 10, "Additional configured ingredients are never silently omitted")
	check(bubble.size.y > bubble.bubble_diameter * 3, "Many ingredients wrap into bounded columns")
	check_bounds()
	for token: Dictionary in shown.tokens:
		if String(token.item_id).begins_with("custom_addition"):
			check(token.icon == null and token.amount >= 10 and token.description.contains("spoonfuls"), "Unrecognized catalog art preserves complete requested counts and units")
	bubble.amount_font_size = 24
	bubble.columns = 2
	bubble.set_order(many, catalog)
	check_bounds()
	bubble.columns = 3
	bubble.amount_font_size = 14
	bubble.bubble_diameter = NAN
	bubble.bubble_gap = INF
	bubble.set_order(original, catalog)
	check(bubble.size.is_finite() and bubble.size.x > 0.0, "Invalid visual settings fall back to finite bounds")
	bubble.bubble_diameter = 46.0
	bubble.bubble_gap = 5.0
	bubble.set_order(null, catalog)
	check(not bubble.get_display_snapshot().valid and bubble.order == null and bubble.get_token_rects().is_empty() and bubble.size == Vector2.ZERO, "Clearing order clears cues and their old layout")
	check(bubble.get_accessibility_summary().is_empty(), "Cleared order leaves no stale accessible text")


func run() -> void:
	await process_frame
	catalog = root.get_node("Catalog")
	bubble = BUBBLE.instantiate() as CustomerOrderBubble
	root.add_child(bubble)
	check(not bubble.get_display_snapshot().valid, "Unbound bubble begins with an explicit empty model")
	current_orders()
	data_driven_and_copies()
	# Exercise actual queued drawing for every current request without a separate
	# screenshot claim; rendered viewport/layout checks belong to integration.
	for request_id: StringName in [&"tea_cha_no_sugar", &"tea_cha", &"tea_dudh_cha_no_sugar", &"tea_dudh_cha", &"ready_banana", &"ready_biscuits"]:
		bubble.set_order(make_order(request_id), catalog)
		await process_frame
		check(bubble.get_display_snapshot().valid, "Queued custom drawing retains the current model")
	bubble.queue_free()
	await process_frame
	print("Customer order bubble: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
