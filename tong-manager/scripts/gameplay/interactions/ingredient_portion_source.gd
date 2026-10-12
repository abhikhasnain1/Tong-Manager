class_name IngredientPortionSource
extends Node2D

var controller: InteractionController
var item_id: StringName
var unit: StringName
var provider: PortionStockProvider
var source_owner: Node2D
var placement_handle: TablePlaceable
var _input_area: Area2D
var _reserving := false
var _provider_revision := 0

func configure(interaction: InteractionController, source_item_id: StringName, source_unit: StringName, input_area: Area2D, handle: TablePlaceable) -> void:
	if is_instance_valid(controller) and controller != interaction and controller.mode_changed.is_connected(_on_mode_changed):
		controller.mode_changed.disconnect(_on_mode_changed)
	controller = interaction
	if not controller.mode_changed.is_connected(_on_mode_changed):
		controller.mode_changed.connect(_on_mode_changed)
	item_id = source_item_id
	unit = source_unit
	source_owner = get_parent() as Node2D
	placement_handle = handle
	if _input_area == input_area:
		return
	if is_instance_valid(_input_area):
		_input_area.input_event.disconnect(_on_input)
		_input_area.mouse_entered.disconnect(_on_hover.bind(true))
		_input_area.mouse_exited.disconnect(_on_hover.bind(false))
	_input_area = input_area
	if is_instance_valid(_input_area):
		_input_area.input_event.connect(_on_input)
		_input_area.mouse_entered.connect(_on_hover.bind(true))
		_input_area.mouse_exited.connect(_on_hover.bind(false))

func set_provider(value: PortionStockProvider) -> void:
	if provider == value:
		return
	_cancel_own_portion()
	provider = value
	_provider_revision += 1

func begin_portion(viewport_position: Vector2) -> bool:
	if not _can_extract():
		return false
	if provider == null:
		get_node("/root/CursorService").reset()
		controller.report_hint("Ingredients unavailable")
		return false
	# Provider signals are synchronous: listeners can reset stock, replace this
	# provider or remove the source before reserve returns. Keep the original
	# transaction alive locally and validate it before creating any held visual.
	var original_provider := provider
	var original_revision := _provider_revision
	var source_ref: WeakRef = weakref(self)
	var portion := IngredientPortion.new(item_id,unit,source_owner,original_provider)
	_reserving = true
	portion.token = original_provider.reserve(item_id,unit,1,portion.source_id)
	var active_source := source_ref.get_ref() as IngredientPortionSource
	if active_source == null:
		portion.cancel()
		return false
	active_source._reserving = false
	if (provider != original_provider or _provider_revision != original_revision
		or not portion.is_available() or not _can_extract()):
		portion.cancel()
		if portion.token == 0 and _can_extract():
			controller.report_hint("No %s portions left" % _name())
		return false
	var visual := IngredientPortionVisual.new(item_id,unit)
	visual.name = "HeldIngredientPortion"
	var payload := portion.create_payload(visual)
	if not controller.start_drag(payload,visual,viewport_position):
		portion.cancel()
		visual.free()
		return false
	controller.report_hint("Release %s over a valid target · Esc cancels" % _portion_name())
	return true

func _can_extract() -> bool:
	return (not _reserving and is_inside_tree() and not is_queued_for_deletion()
		and is_instance_valid(source_owner) and source_owner.is_inside_tree() and not source_owner.is_queued_for_deletion()
		and is_instance_valid(controller) and controller.is_inside_tree() and not controller.is_queued_for_deletion()
		and controller.current_mode == InteractionController.MODE_INTERACT
		and controller.can_start_world_action() and not controller.is_dragging() and not controller.has_active_action()
		and is_instance_valid(placement_handle) and is_instance_valid(placement_handle.surface)
		and placement_handle.surface.is_registered(source_owner))

func _on_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(placement_handle) and placement_handle._is_frontmost_at(event.position) and begin_portion(event.position):
			get_viewport().set_input_as_handled()

func _on_hover(entered: bool) -> void:
	if not _can_extract():
		return
	if not entered:
		get_node("/root/CursorService").reset()
		return
	if not placement_handle._is_frontmost_at(get_viewport().get_mouse_position()):
		return
	if provider == null:
		get_node("/root/CursorService").reset()
		controller.report_hint("Ingredients unavailable")
		return
	if provider.available(item_id) <= 0:
		get_node("/root/CursorService").reset()
		controller.report_hint("No %s portions left" % _name())
		return
	get_node("/root/CursorService").set_state(&"teabag" if unit == &"teabag" else &"spoon")
	controller.report_hint("Drag %s" % _portion_name())

func _on_mode_changed(mode: StringName) -> void:
	if (not is_inside_tree() or is_queued_for_deletion()
		or not is_instance_valid(controller) or not controller.can_start_world_action()):
		return
	var point := get_viewport().get_mouse_position()
	if (not is_instance_valid(placement_handle) or not placement_handle._contains_pointer(point)
		or not placement_handle._is_frontmost_at(point)):
		return
	if mode == InteractionController.MODE_INTERACT:
		_on_hover(true)
	elif mode == InteractionController.MODE_ORGANIZE:
		get_node("/root/CursorService").set_state(&"hover_actionable")

func _portion_name() -> String:
	return "one teabag" if unit == &"teabag" else "one spoonful of %s" % _name()

func _name() -> String:
	return "milk" if item_id == &"condensed_milk" else ("tea" if item_id == &"black_tea" else String(item_id))

func _cancel_own_portion() -> void:
	if not is_instance_valid(controller) or controller.current_payload == null:
		return
	var portion := controller.current_payload.metadata.get("portion") as IngredientPortion
	if portion != null and is_instance_valid(source_owner) and portion.source_id == source_owner.get_instance_id():
		controller.cancel_drag()

func _process(_delta: float) -> void:
	if not is_instance_valid(controller) or controller.current_payload == null:
		return
	var portion := controller.current_payload.metadata.get("portion") as IngredientPortion
	if (portion != null and is_instance_valid(source_owner)
		and portion.source_id == source_owner.get_instance_id() and not portion.is_available()):
		controller.cancel_drag()

func _exit_tree() -> void:
	_cancel_own_portion()
