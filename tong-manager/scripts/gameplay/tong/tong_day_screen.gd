extends Node2D

const AUTHORED_SIZE := Vector2(1920.0, 1080.0)
const CROP_SAFE_RECT := Rect2(96.0, 0.0, 1728.0, 1080.0)

@export var tool_def: Resource
@export var day_config: Resource
@export var ingredient_policy: IngredientPolicy = preload("res://data/balance/ingredient_policy.tres")
@export var source_layout: PortionSourceLayout = preload("res://data/balance/portion_sources_level_1.tres")
@export_group("Customers")
@export var customer_queue_enabled := true
@export var customer_queue_auto_start := true
@export var customer_queue_seed := 0
@export var payment_feedback_config: PaymentFeedbackConfig = preload("res://data/balance/payment_feedback.tres")

@onready var world_root: Node2D = %WorldRoot
@onready var composition_guides: Node2D = %CompositionGuides
@onready var cursor_service: Node = get_node("/root/CursorService")
@onready var table_surface: PlacementSurface = $WorldRoot/DropZoneRoot/TablePlacementSurface
var portion_sources: Array[IngredientPortionSource] = []
var hanging_sources: Array[HangingSourceBody] = []
var _portion_provider: PortionStockProvider
var khata_modal: KhataModal
var _extra_portion_targets: Array[DropZone] = []
var _export_targets: Array[DropZone] = []
var customer_queue: CustomerQueueManager
var customer_order_overlay: CustomerOrderOverlay
var customer_service: CustomerService
var customer_payments: CustomerPayments
var payment_feedback: PaymentFeedback


func _ready() -> void:
	get_viewport().physics_object_picking_sort = true
	get_viewport().size_changed.connect(_fit_authored_world)
	var interaction := $InteractionController as InteractionController
	var hud := $HUDLayer/RootUI as TongHud
	interaction.modal_root = $HUDLayer/RootUI/ModalStack
	hud.bind_controller(interaction)
	cursor_service.bind_hover_target($WorldRoot/ToolLayer/KhataStation/KhataHotspot)
	_fit_authored_world()
	_configure_table_placement()
	_configure_portion_sources()
	_configure_hanging_sources()
	_configure_portion_target($WorldRoot/ToolLayer/KettleStation)
	khata_modal = $HUDLayer/RootUI/ModalStack/KhataModal
	khata_modal.configure(interaction)
	var game_state := get_node("/root/GameState")
	if game_state.ensure_finance(day_config):
		hud.bind_finance(game_state.finance)
	if game_state.ensure_inventory(day_config):
		set_portion_provider(game_state.inventory)
	_sync_inventory_targets()
	$HUDLayer/RootUI/StatusBadges.bind_scope(self)
	$WorldRoot/ToolLayer/KhataStation/KhataHotspot.input_event.connect(_on_khata_input)
	_verify_layout_contract()
	_configure_customer_queue()
	if customer_queue_enabled:
		customer_service = CustomerService.new()
		customer_service.name = "CustomerService"
		add_child(customer_service)
		customer_service.targets_changed.connect(_sync_inventory_targets)
		customer_service.configure(self, interaction, customer_queue)
		_configure_payments(game_state, hud)
		_sync_inventory_targets()
	customer_order_overlay = $HUDLayer/RootUI/CustomerOrderOverlay
	if customer_queue_enabled:
		customer_order_overlay.bind_queue(customer_queue, get_node("/root/Catalog"))


func _configure_payments(game_state: Node, hud: TongHud) -> void:
	if not game_state.finance.initialized: return
	customer_payments = game_state.get_node_or_null("CustomerPayments") as CustomerPayments
	if customer_payments == null:
		customer_payments = CustomerPayments.new()
		customer_payments.name = "CustomerPayments"
		game_state.add_child(customer_payments)
	customer_payments.configure(game_state.finance)
	customer_service.payments = customer_payments
	payment_feedback = PaymentFeedback.new()
	payment_feedback.name = "PaymentFeedback"
	hud.add_child(payment_feedback)
	payment_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	payment_feedback.configure(payment_feedback_config)
	customer_payments.payment_recorded.connect(_on_payment_recorded)


func _on_payment_recorded(transaction: Dictionary, screen_id: int, origin: Vector2) -> void:
	if (screen_id != get_instance_id() or not is_inside_tree() or is_queued_for_deletion()
		or not is_instance_valid(payment_feedback) or not is_visible_in_tree()): return
	var hud := $HUDLayer/RootUI as TongHud
	var destination := hud.cash_label.get_global_transform_with_canvas() * Vector2(hud.cash_label.size.x * 0.5, hud.cash_label.size.y + 18.0)
	payment_feedback.show_payment(transaction, origin, destination)


func _configure_customer_queue() -> void:
	customer_queue = $CustomerQueueManager as CustomerQueueManager
	if not customer_queue_enabled:
		customer_queue.set_process(false)
		return
	# Presentation review scenes explicitly opt out and retain their fixed samples.
	for sample_name in ["CustomerA", "CustomerB"]:
		var sample := get_node_or_null("WorldRoot/CustomerLayer/" + sample_name) as Customer
		if sample != null:
			sample.hide()
			sample.queue_free()
	var slots: Array[Marker2D] = []
	for child in $WorldRoot/CustomerLayer/CustomerQueueSlots.get_children():
		if child is Marker2D: slots.append(child as Marker2D)
	if not customer_queue.configure(slots, $WorldRoot/CustomerLayer/ActiveCustomers, get_node("/root/Catalog")):
		push_error("Customer queue could not bind the stall layout")
		return
	if customer_queue_auto_start:
		start_customer_queue(day_config, customer_queue_seed)


func start_customer_queue(config: Resource = null, seed_value: int = 0) -> bool:
	if not customer_queue_enabled or not is_instance_valid(customer_queue): return false
	# Starting a schedule is independent of inventory/day-state initialization.
	var started := customer_queue.start(day_config if config == null else config, seed_value)
	if not started:
		push_warning("Customer schedule did not start: " + "; ".join(customer_queue.get_snapshot().errors))
	return started


func _on_khata_input(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if khata_modal.open_peek():
			get_viewport().set_input_as_handled()


func set_portion_provider(provider: PortionStockProvider) -> void:
	# Physical containers and the pantry use the same run inventory.
	_portion_provider = provider
	if is_instance_valid(khata_modal):
		khata_modal.configure_inventory(provider)
	for source in portion_sources:
		if is_instance_valid(source):
			source.set_provider(provider)


func set_extra_portion_targets(targets: Array[DropZone]) -> void:
	# Development scenes may explicitly add their labelled snack fixtures.
	_extra_portion_targets = targets.duplicate()
	_sync_inventory_targets()


func _sync_inventory_targets() -> void:
	if not is_inside_tree() or not is_instance_valid(khata_modal):
		return
	var targets: Array[DropZone] = []
	var kettle_zone := get_node_or_null("WorldRoot/ToolLayer/KettleStation/IngredientTarget") as DropZone
	if is_instance_valid(kettle_zone) and kettle_zone.is_inside_tree() and not kettle_zone.is_queued_for_deletion():
		targets.append(kettle_zone)
	for cup in get_cups():
		var zone := cup.get_node_or_null("IngredientTarget") as DropZone
		if is_instance_valid(zone) and zone.is_inside_tree() and not zone.is_queued_for_deletion():
			targets.append(zone)
	for zone in _extra_portion_targets:
		if is_instance_valid(zone) and zone.is_inside_tree() and not zone.is_queued_for_deletion() and not targets.has(zone):
			targets.append(zone)
	if is_instance_valid(customer_service):
		for zone in customer_service.get_drop_targets():
			if not targets.has(zone): targets.append(zone)
	if targets != _export_targets:
		_export_targets = targets
		khata_modal.configure_export_targets(targets)


func _configure_portion_sources() -> void:
	if source_layout == null:
		return
	for binding in source_layout.physical_sources:
		if binding == null: continue
		var item := get_node_or_null(binding.node_path) as Node2D
		var definition: ItemDef = get_node("/root/Catalog").get_portion_item(binding.item_id)
		if item == null or definition == null:
			push_warning("Invalid physical portion source: %s" % binding.item_id)
			continue
		var input := item.get_node_or_null(binding.input_area_path) as Area2D
		var handle := item.get_node_or_null(binding.placement_handle_path) as TablePlaceable
		if input == null or handle == null:
			push_warning("Portion source requires its input area and placement handle")
			continue
		var source := IngredientPortionSource.new()
		source.name = "IngredientSource"
		item.add_child(source)
		source.configure($InteractionController, definition.id, definition.unit, input, handle)
		source.set_provider(_portion_provider)
		portion_sources.append(source)


func _configure_hanging_sources() -> void:
	if source_layout == null:
		return
	for binding in source_layout.hanging_sources:
		if binding == null: continue
		var authored := get_node_or_null(binding.art_path) as Sprite2D
		var definition: ItemDef = get_node("/root/Catalog").get_portion_item(binding.item_id)
		if authored == null or definition == null:
			push_warning("Invalid hanging portion source: %s" % binding.item_id)
			continue
		_add_hanging_source(authored, binding.node_name, definition.id, binding.region, binding.pivot, definition.unit)
		authored.hide()


func _add_hanging_source(authored: Sprite2D, node_name: String, item_id: StringName, region: Rect2, pivot: Vector2, unit: StringName) -> void:
	var hanging := HangingSourceBody.new()
	hanging.name = node_name
	hanging.position = authored.position
	authored.get_parent().add_child(hanging)
	hanging.configure($InteractionController, authored.texture, region, authored.scale.x, pivot)
	hanging_sources.append(hanging)
	var source := IngredientPortionSource.new()
	source.name = "ReadyItemSource"
	hanging.add_child(source)
	source.configure_fixed($InteractionController, item_id, unit, hanging,
		hanging.input_area, hanging.contains_pointer, hanging.is_frontmost_at)
	source.set_provider(_portion_provider)
	portion_sources.append(source)


func _configure_portion_target(target: Node2D) -> void:
	var zone := target.get_node_or_null("IngredientTarget") as IngredientPortionTarget
	if zone == null:
		zone = IngredientPortionTarget.new()
		zone.name = "IngredientTarget"
		target.add_child(zone)
	var anchor := target.get_node_or_null("IngredientAnchor") as Marker2D
	zone.policy = ingredient_policy
	zone.position = anchor.position if anchor != null else (Vector2(26, -70) if target is Kettle else Vector2(0, -12))
	zone.configure($InteractionController, target)
	if not zone.tree_exited.is_connected(_sync_inventory_targets):
		zone.tree_exited.connect(_sync_inventory_targets, CONNECT_DEFERRED)
		zone.tree_entered.connect(_sync_inventory_targets, CONNECT_DEFERRED)
	_sync_inventory_targets()


func set_ingredient_policy(value: IngredientPolicy) -> bool:
	if value == null or not value.configuration_errors().is_empty():
		return false
	var interaction := get_node_or_null("InteractionController") as InteractionController
	if is_instance_valid(interaction) and interaction.is_dragging():
		interaction.cancel_drag()
	ingredient_policy = value
	# Use ownership rather than fixed scene paths: held/moved vessels still belong here.
	for node in find_children("IngredientTarget", "", true, false):
		if node is IngredientPortionTarget:
			(node as IngredientPortionTarget).policy = value
	return true


func set_composition_guides_visible(is_visible: bool) -> void:
	composition_guides.visible = is_visible


func _fit_authored_world() -> void:
	var interaction := get_node_or_null("InteractionController") as InteractionController
	if is_instance_valid(interaction) and interaction.is_dragging():
		interaction.cancel_drag()
	var viewport_size := get_viewport().get_visible_rect().size
	var cover_scale := maxf(viewport_size.x / AUTHORED_SIZE.x, viewport_size.y / AUTHORED_SIZE.y)
	world_root.scale = Vector2.ONE * cover_scale
	world_root.position = (viewport_size - AUTHORED_SIZE * cover_scale) * 0.5
	for hanging in hanging_sources:
		if is_instance_valid(hanging):
			hanging.sync_layout()


func _configure_table_placement() -> void:
	var tray := $WorldRoot/ToolLayer/TrayStation as TrayStation
	for node in get_tree().get_nodes_in_group(&"table_placeables"):
		if is_ancestor_of(node):
			var handle := node as TablePlaceable
			if handle.item is Cup:
				continue
			var configured := handle.configure(table_surface, $InteractionController)
			assert(configured,
				"Invalid initial table placement: %s" % handle.get_parent().name)
			if handle.item != tray:
				handle.set_available_surfaces([table_surface, tray.interior_surface])
	for cup in get_cups():
		var configured := configure_cup(cup)
		assert(configured, "Invalid initial cup placement: %s" % cup.name)


func get_cups() -> Array[Cup]:
	var result: Array[Cup] = []
	for node in get_tree().get_nodes_in_group(&"cups"):
		if node is Cup and is_ancestor_of(node) and not node.is_queued_for_deletion() and node.state != Cup.CupState.SERVED:
			result.append(node)
	return result


func configure_cup(cup: Cup) -> bool:
	if (not is_instance_valid(cup) or not is_ancestor_of(cup) or cup.is_queued_for_deletion()
		or cup.state == Cup.CupState.SERVED or not is_instance_valid(table_surface)):
		return false
	var tray := $WorldRoot/ToolLayer/TrayStation as TrayStation
	var handle := cup.get_node_or_null("PlacementHandle") as TablePlaceable
	if handle == null:
		return false
	# Reconfiguration must not overwrite ownership during a drag or transfer.
	if not is_instance_valid(handle.surface) or not handle.surface.is_registered(cup):
		var initial := tray.interior_surface if cup.get_parent() == tray.get_contents() else table_surface
		if not handle.configure(initial, $InteractionController):
			return false
		cup.capacity_ml = float(tool_def.cup_volume_ml)
	handle.set_available_surfaces([table_surface, tray.interior_surface])
	cup.bind_controller($InteractionController)
	_configure_portion_target(cup)
	return true


func _verify_layout_contract() -> void:
	assert(tool_def != null, "TongDayScreen requires a ToolDef resource.")
	assert(day_config != null, "TongDayScreen requires a DayConfig resource.")
	assert(tool_def.starting_cup_count >= 0, "Starting cup supply cannot be negative.")
	var tray_station := $WorldRoot/ToolLayer/TrayStation as TrayStation
	assert(tray_station != null, "TongDayScreen requires the functional TrayStation scene.")
	assert(get_cups().size() == tool_def.starting_cup_count, "Starting cup supply must follow ToolDef.")
	assert(table_surface.is_registered(tray_station), "Tray requires a committed table footprint.")
	assert(tool_def.burner_count == 2, "The demo stove exposes two configurable burners.")
	for marker in get_tree().get_nodes_in_group("critical_interaction_anchor"):
		var authored_position := world_root.to_local(marker.global_position)
		assert(
			CROP_SAFE_RECT.has_point(authored_position),
			"%s at %s is outside the 16:10 crop-safe area." % [marker.get_path(), authored_position]
		)
