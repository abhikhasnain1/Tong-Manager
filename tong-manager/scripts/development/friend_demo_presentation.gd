class_name FriendDemoPresentation
extends Node2D

# Opt-in artwork and drawing changes. No physics, inventory or input authority.
const FLAME_ART: Texture2D = preload("res://assets/art/toolkit/stove_flames.png")

@export_range(0.0, 300.0, 1.0) var roof_hook_y := 150.0
@export var roof_hook_overrides: Dictionary = {"BiscuitBag":95.0}
@export_range(1.0, 1.6, 0.05) var ready_portion_scale := 1.3
@export var rope_color := Color("b6a17b")
@export var hook_color := Color("554c40")

var _screen: Node
var _world: Node2D
var _controller: InteractionController
var _burners: Array[Dictionary] = []
var _held_visual: WeakRef
var _held_original_scale := 1.0


func _enter_tree() -> void:
	_restore_after_enter.call_deferred()


func _restore_after_enter() -> void:
	if _live(_screen) and not _live(_controller):
		configure(_screen)


func configure(screen: Node) -> void:
	_release_presentation()
	_screen = screen
	if not _live(_screen):
		return
	_world = _screen.get_node_or_null("WorldRoot") as Node2D
	_controller = _screen.get_node_or_null("InteractionController") as InteractionController
	z_as_relative = false
	z_index = 31
	if _live(_controller):
		_controller.drag_started.connect(_on_drag_started)
		if _controller.current_payload != null:
			_on_drag_started(_controller.current_payload, _controller.current_drag_node)
	var stove := _screen.get_node_or_null("WorldRoot/ToolLayer/StoveStation") as Stove
	if _live(stove):
		for burner in stove.burners:
			if not _live(burner):
				continue
			_burners.append({"owner":weakref(burner), "previous":burner.flame_art})
			burner.flame_art = FLAME_ART
	queue_redraw()


func _on_drag_started(payload: HeldItemPayload, drag_node: Node2D) -> void:
	_restore_held_visual()
	if payload == null or payload.metadata.get("category") != &"ready_item" or not drag_node is IngredientPortionVisual:
		return
	var visual := drag_node as IngredientPortionVisual
	_held_visual = weakref(visual)
	_held_original_scale = visual.ready_item_scale
	visual.ready_item_scale = ready_portion_scale


func _process(_delta: float) -> void:
	# The real bodies remain on their original joints. Only the visible cord's
	# endpoints are redrawn to match world fitting and the simulated attachment.
	queue_redraw()


func get_roof_links() -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	if not _live(_screen) or not _live(_world) or not _world.is_visible_in_tree():
		return links
	var sources: Variant = _screen.get("hanging_sources")
	if not sources is Array:
		return links
	for value in sources:
		if not is_instance_valid(value):
			continue
		var source := value as HangingSourceBody
		if not _live(source) or not source.is_visible_in_tree() or not _live(source.anchor) or not _live(source.body):
			continue
		var pin_world := source.anchor.global_position
		var pin_authored := _world.to_local(pin_world)
		var hook_y := float(roof_hook_overrides.get(String(source.name), roof_hook_y))
		var roof_world := _world.to_global(Vector2(pin_authored.x, hook_y))
		var local_scale := absf(_world.global_scale.x) / maxf(absf(global_scale.x), 0.001)
		links.append({"source":source, "roof":to_local(roof_world), "pin":to_local(pin_world), "scale":local_scale})
	return links


func _draw() -> void:
	for link in get_roof_links():
		var roof: Vector2 = link.roof
		var pin: Vector2 = link.pin
		var width: float = maxf(float(link.scale), 0.1)
		# A small tied hook attaches the existing string to the roof. Drawing
		# ends at the physical pin; the artwork below it is still physics-driven.
		draw_line(roof, pin, hook_color, 4.0 * width, true)
		draw_line(roof + Vector2(width, 0), pin + Vector2(width, 0), rope_color, 1.6 * width, true)
		draw_arc(roof + Vector2(0, -3.0 * width), 6.0 * width, -PI, PI * 0.65, 14, hook_color, 3.0 * width, true)
		draw_arc(pin, 3.0 * width, 0.0, TAU, 12, rope_color, 1.8 * width, true)


func _restore_held_visual() -> void:
	if _held_visual != null:
		var visual := _held_visual.get_ref() as IngredientPortionVisual
		if is_instance_valid(visual):
			visual.ready_item_scale = _held_original_scale
	_held_visual = null


func _release_presentation() -> void:
	_restore_held_visual()
	if is_instance_valid(_controller) and _controller.drag_started.is_connected(_on_drag_started):
		_controller.drag_started.disconnect(_on_drag_started)
	_controller = null
	for entry in _burners:
		var burner := (entry.owner as WeakRef).get_ref() as Burner
		if is_instance_valid(burner) and burner.flame_art == FLAME_ART:
			burner.flame_art = entry.previous as Texture2D
	_burners.clear()
	_world = null


func _exit_tree() -> void:
	_release_presentation()


func _live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()
