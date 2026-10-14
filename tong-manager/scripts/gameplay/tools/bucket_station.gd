class_name BucketStation
extends Node2D

signal changed(snapshot: Dictionary)
signal cup_cleaned(cup: Cup)

@export var config: BucketConfig = preload("res://data/balance/bucket_config.tres")

var owner_screen: Node2D
var controller: InteractionController
var transfers: CupTransfer
var _entries: Array[Dictionary] = []
var _zone: BucketDropZone
var _washing := false
var _resolving := false
var _focused := true
var _hovered := false
var _highlighted := false
var _highlight_valid := false
var _feedback_text := ""
var _feedback_seconds := 0.0
var _foam_time := 0.0
var _revision := 0

@onready var holder: Node2D = $Cups
@onready var body: Area2D = $Body
@onready var body_shape: CollisionPolygon2D = $Body/CollisionPolygon2D
@onready var sprite: Sprite2D = $Sprite
@onready var counts_label: Label = $Counts
@onready var hint_label: Label = $Hint
@onready var clean_pickup: Area2D = $CleanPickup
@onready var clean_icon: Sprite2D = $CleanPickup/Icon
@onready var clean_label: Label = $CleanPickup/Label
@onready var progress_visual: Node2D = $Progress

func _enter_tree() -> void:
	_restore_registration.call_deferred()

func _restore_registration() -> void:
	if _available() and _live(_zone):
		controller.register_drop_zone(_zone)

func _ready() -> void:
	_zone = BucketDropZone.new()
	_zone.bucket = self
	add_child(_zone)
	body.input_event.connect(_on_body_input)
	body.mouse_entered.connect(_on_hover.bind(true))
	body.mouse_exited.connect(_on_hover.bind(false))
	clean_pickup.input_event.connect(_on_pickup_input)
	progress_visual.draw.connect(_draw_progress)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(cancel_action)
	_refresh_visuals()

func configure(screen: Node2D, interaction: InteractionController, cup_transfers: CupTransfer) -> bool:
	cancel_action()
	if _live(controller):
		controller.unregister_drop_zone(_zone)
		if controller.mode_changed.is_connected(_on_mode_changed):
			controller.mode_changed.disconnect(_on_mode_changed)
	owner_screen = screen
	controller = interaction
	transfers = cup_transfers
	_revision += 1
	if not _available():
		return false
	controller.register_drop_zone(_zone)
	controller.mode_changed.connect(_on_mode_changed)
	_refresh_visuals()
	return true

func get_drop_targets() -> Array[DropZone]:
	var targets: Array[DropZone] = []
	if _available() and _live(_zone):
		targets.append(_zone)
	return targets

func get_cups() -> Array[Cup]:
	var cups: Array[Cup] = []
	for entry in _entries:
		var cup: Variant = (entry.cup as WeakRef).get_ref()
		if _owned_live(cup):
			cups.append(cup as Cup)
	return cups

func has_cup(cup: Variant) -> bool:
	return _owned_live(cup) and not _entry_for(cup).is_empty()

func can_receive(payload: HeldItemPayload) -> DropValidation:
	if (_resolving or not _available() or not is_visible_in_tree() or payload == null
		or not _live(payload.world_node) or not payload.world_node is Cup
		or controller.current_mode != InteractionController.MODE_INTERACT
		or controller.is_world_input_blocked() or controller.current_payload != payload
		or controller.current_drag_node != payload.world_node):
		return DropValidation.invalid("bucket.active_cup_drag_required")
	var cup := payload.world_node as Cup
	if has_cup(cup):
		return DropValidation.invalid("bucket.already_owned")
	if cup.state != Cup.CupState.DIRTY:
		return DropValidation.invalid("bucket.dirty_cup_required")
	if config == null or not config.is_valid():
		return DropValidation.invalid("bucket.unavailable")
	if get_cups().size() >= config.capacity:
		return DropValidation.invalid("bucket.full")
	if not transfers.can_commit(payload):
		return DropValidation.invalid("bucket.source_unavailable")
	return DropValidation.valid()

func try_receive(payload: HeldItemPayload) -> bool:
	if not can_receive(payload).is_valid:
		return false
	_resolving = true
	var self_ref: WeakRef = weakref(self)
	var accepted := transfers.commit_to_holder(payload, holder, _book_received)
	if self_ref.get_ref() == null:
		return accepted
	_resolving = false
	if accepted and is_inside_tree() and not is_queued_for_deletion():
		_feedback_text = ""
		_refresh_visuals()
		changed.emit(get_snapshot())
	return accepted

func _book_received(cup: Cup) -> void:
	# The transfer owner calls this during its atomic commit. Book ownership
	# without signals; source retirement happens before try_receive publishes.
	_entries.append({"cup": weakref(cup), "elapsed": 0.0})
	_revision += 1

func begin_clean_pickup(point: Vector2) -> bool:
	if (_resolving or not _available() or not is_visible_in_tree() or not point.is_finite()
		or controller.current_mode != InteractionController.MODE_INTERACT
		or not controller.can_start_world_action()):
		return false
	var cup := _first_cup(Cup.CupState.CLEAN)
	if cup == null:
		return false
	_resolving = true
	var self_ref: WeakRef = weakref(self)
	var started := transfers.begin_transfer(cup, point, self, _owns_clean_cup, _release_clean_cup)
	if self_ref.get_ref() != null:
		_resolving = false
		_refresh_visuals()
	return started

func _owns_clean_cup(cup: Cup) -> bool:
	return _available() and has_cup(cup) and cup.state == Cup.CupState.CLEAN

func _release_clean_cup(cup: Cup) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		if (_entries[index].cup as WeakRef).get_ref() == cup:
			_entries.remove_at(index)
			_revision += 1
			break
	# Destination and source callbacks finish before observers see the new count.
	_emit_changed.call_deferred()

func begin_wash() -> bool:
	if (_resolving or not _available() or not _focused or not is_visible_in_tree()
		or config == null or not config.is_valid() or _first_cup(Cup.CupState.DIRTY) == null
		or controller.current_mode != InteractionController.MODE_INTERACT
		or not controller.can_start_world_action() or not controller.lock_action(self)):
		return false
	_washing = true
	_feedback_text = ""
	controller.report_hint("Hold to wash · release pauses · drag a clean cup out when ready")
	_refresh_visuals()
	return _washing and _wash_allowed()

func cancel_action() -> void:
	_washing = false
	if is_instance_valid(controller):
		controller.unlock_action(self)
	if is_node_ready():
		_refresh_visuals()

func advance_washing(delta: float) -> void:
	if _resolving or not is_finite(delta) or delta <= 0.0 or not _washing:
		return
	if not _wash_allowed():
		cancel_action()
		return
	_resolving = true
	var remaining := delta
	var self_ref: WeakRef = weakref(self)
	while remaining > 0.0 and _washing and _wash_allowed():
		var cup := _first_cup(Cup.CupState.DIRTY)
		if cup == null:
			cancel_action()
			break
		var entry := _entry_for(cup)
		var used := minf(remaining, maxf(0.0, config.wash_seconds - float(entry.elapsed)))
		entry.elapsed = float(entry.elapsed) + used
		remaining -= used
		if float(entry.elapsed) + 0.000001 < config.wash_seconds:
			break
		entry.elapsed = 0.0
		# Cup commits its clean state before publishing its own content signals.
		# Reentrant input cannot begin another transfer while this step resolves.
		cup.reset_clean()
		if self_ref.get_ref() == null:
			return
		if has_cup(cup) and cup.state == Cup.CupState.CLEAN:
			cup_cleaned.emit(cup)
		if self_ref.get_ref() == null:
			return
	if self_ref.get_ref() == null:
		return
	_resolving = false
	if _first_cup(Cup.CupState.DIRTY) == null:
		cancel_action()
	_refresh_visuals()

func get_snapshot() -> Dictionary:
	var dirty := 0
	var clean := 0
	var progress := 0.0
	for cup in get_cups():
		if cup.state == Cup.CupState.DIRTY:
			dirty += 1
			if dirty == 1 and config != null and config.is_valid():
				progress = clampf(float(_entry_for(cup).elapsed) / config.wash_seconds, 0.0, 1.0)
		elif cup.state == Cup.CupState.CLEAN:
			clean += 1
	return {"total": get_cups().size(), "dirty": dirty, "clean": clean,
		"capacity": config.capacity if config != null else 0, "washing": _washing, "progress": progress}

func contains_pointer(point: Vector2) -> bool:
	if (not is_node_ready() or not is_visible_in_tree() or not point.is_finite()
		or body_shape.disabled or is_zero_approx(body_shape.get_global_transform_with_canvas().determinant())):
		return false
	return Geometry2D.is_point_in_polygon(body_shape.get_global_transform_with_canvas().affine_inverse() * point, body_shape.polygon)

func set_drop_highlight(active: bool, valid: bool) -> void:
	_highlighted = active
	_highlight_valid = valid
	_refresh_visuals()

func report_rejection(reason: String) -> void:
	_feedback_text = "Bucket full" if reason == "bucket.full" else "Dirty cups only"
	_feedback_seconds = 2.5
	if _live(controller):
		controller.report_hint("Bucket full · wash and take out a clean cup" if reason == "bucket.full" else "Only dirty cups go into the wash bucket")
	_refresh_visuals()

func _input(event: InputEvent) -> void:
	if not _washing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (not contains_pointer(event.position) or controller.is_pointer_over_ui_at(event.position)):
		cancel_action()

func _on_body_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var handled := begin_clean_pickup(event.position) if _over_clean_pickup(event.position) else begin_wash()
	if handled:
		get_viewport().set_input_as_handled()

func _on_pickup_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and begin_clean_pickup(event.position):
		get_viewport().set_input_as_handled()

func _over_clean_pickup(point: Vector2) -> bool:
	return clean_pickup.visible and (clean_pickup.get_global_transform_with_canvas().affine_inverse() * point).length() <= 22.0

func _on_hover(entered: bool) -> void:
	_hovered = entered
	if entered and _available() and controller.can_start_world_action() and controller.current_mode == InteractionController.MODE_INTERACT:
		controller.report_hint("Hold bucket to wash · drag the small clean cup to the table or tray")
	_refresh_visuals()

func _on_mode_changed(_mode: StringName) -> void:
	cancel_action()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		cancel_action()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_focused = false
		cancel_action()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN]:
		_focused = true

func _process(delta: float) -> void:
	_purge_entries()
	if _washing and (not _wash_allowed() or controller.is_pointer_over_ui_at(get_viewport().get_mouse_position())):
		cancel_action()
	advance_washing(delta)
	if _washing:
		_foam_time += delta
	if _feedback_seconds > 0.0:
		_feedback_seconds = maxf(0.0, _feedback_seconds - delta)
		if _feedback_seconds == 0.0:
			_feedback_text = ""
	_refresh_visuals()

func _wash_allowed() -> bool:
	return (_available() and _focused and is_visible_in_tree() and config != null and config.is_valid()
		and controller.current_mode == InteractionController.MODE_INTERACT and controller.action_owner == self
		and not controller.is_world_input_blocked() and not controller.is_dragging())

func _available() -> bool:
	return (_live(self) and is_node_ready() and _live(owner_screen) and owner_screen.is_ancestor_of(self)
		and _live(controller) and _live(transfers) and _live(holder))

func _owned_live(cup: Variant) -> bool:
	return (_live(cup) and cup is Cup and _live(owner_screen) and owner_screen.is_ancestor_of(cup)
		and ((_live(holder) and holder.is_ancestor_of(cup))
			or (_live(transfers) and transfers.is_transferring(cup))))

func _live(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node and value.is_inside_tree() and not value.is_queued_for_deletion()

func _entry_for(cup: Variant) -> Dictionary:
	for entry in _entries:
		if (entry.cup as WeakRef).get_ref() == cup:
			return entry
	return {}

func _first_cup(state: Cup.CupState) -> Cup:
	for cup in get_cups():
		if cup.state == state:
			return cup
	return null

func _purge_entries() -> void:
	for index in range(_entries.size() - 1, -1, -1):
		if not _owned_live((_entries[index].cup as WeakRef).get_ref()):
			_entries.remove_at(index)
			_revision += 1

func _emit_changed() -> void:
	if _available():
		_refresh_visuals()
		changed.emit(get_snapshot())

func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	var snapshot := get_snapshot()
	counts_label.text = "%d dirty · %d clean" % [snapshot.dirty, snapshot.clean]
	clean_pickup.visible = snapshot.clean > 0
	clean_pickup.input_pickable = snapshot.clean > 0
	clean_label.text = "Drag clean"
	hint_label.text = _feedback_text if not _feedback_text.is_empty() else ("Washing…" if _washing else ("Hold to wash" if snapshot.dirty > 0 else "Drop dirty cups"))
	sprite.modulate = Color(1.2, 1.2, 1.2) if _hovered or _washing else Color.WHITE
	if _highlighted:
		sprite.modulate = Color(1.2, 1.35, 1.2) if _highlight_valid else Color(1.15, 0.7, 0.7)
	progress_visual.visible = snapshot.dirty > 0
	progress_visual.queue_redraw()

func _draw_progress() -> void:
	var progress: float = get_snapshot().progress
	progress_visual.draw_circle(Vector2.ZERO, 20.0, Color("314957"))
	progress_visual.draw_arc(Vector2.ZERO, 18.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, Color("b7e7d6"), 3.0, true)
	for index in 3:
		var lift := sin(_foam_time * 3.0 + index * 1.7) * 2.0 if _washing else 0.0
		progress_visual.draw_circle(Vector2((index - 1) * 8.0, lift + (3.0 if index == 1 else -1.0)), 4.0 if index == 1 else 3.0, Color("e2f4ed"))

func _exit_tree() -> void:
	_washing = false
	if is_instance_valid(controller):
		controller.unlock_action(self)
		if is_instance_valid(_zone):
			controller.unregister_drop_zone(_zone)
