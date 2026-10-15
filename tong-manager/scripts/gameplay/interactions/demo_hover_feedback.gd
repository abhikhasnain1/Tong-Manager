class_name DemoHoverFeedback
extends Node
## Optional presentation for the compact demonstration. Never owns an input event.

const OUTLINE := preload("res://assets/shaders/demo_hover_outline.gdshader")
const FIXED_TARGETS := [
	"WorldRoot/ToolLayer/KettleStation", "WorldRoot/ToolLayer/StoveStation",
	"WorldRoot/ToolLayer/StoveStation/DialA", "WorldRoot/ToolLayer/StoveStation/DialB",
	"WorldRoot/ToolLayer/BucketStation", "WorldRoot/ToolLayer/WaterDrum",
	"WorldRoot/DropZoneRoot/DiscardArea", "WorldRoot/ToolLayer/KhataStation/KhataHotspot",
]

@export_range(1.0, 1.15, 0.005) var item_pop_scale := 1.04
@export_range(1.0, 1.2, 0.005) var utility_pop_scale := 1.08
@export_range(1.0, 5.0, 0.25) var stroke_pixels := 2.5

var _screen: WeakRef
var _controller: WeakRef
var _entries: Array[Dictionary] = []
var _hovered: WeakRef
var _applied: Array[Dictionary] = []
var _lifted: Dictionary = {}
var _focused := true
var _refresh_elapsed := 0.0


func configure(screen: Node2D) -> void:
	_clear_feedback()
	_screen = weakref(screen) if is_instance_valid(screen) else null
	var controller := screen.get_node_or_null("InteractionController") if is_instance_valid(screen) else null
	_controller = weakref(controller) if controller is InteractionController else null
	process_priority = 100
	refresh_targets()


func refresh_targets() -> void:
	_entries.clear()
	var screen := _get_screen()
	if screen == null: return
	for node in get_tree().get_nodes_in_group(&"table_placeables"):
		var handle := node as TablePlaceable
		if handle != null and _live(handle.item) and screen.is_ancestor_of(handle.item):
			_add_target(handle.item, false, handle)
	for path in FIXED_TARGETS:
		var owner_node := screen.get_node_or_null(path) as Node2D
		if owner_node != null:
			_add_target(owner_node, path.contains("BucketStation") or path.contains("WaterDrum")
				or path.contains("DiscardArea") or path.contains("KhataHotspot"))
	_refresh_elapsed = 0.0


func get_hovered_owner() -> Node2D:
	var owner_node: Variant = _hovered.get_ref() if _hovered != null else null
	return owner_node as Node2D if _live(owner_node) else null


func get_utility_at(pointer: Vector2) -> Node2D:
	var selected: Dictionary = {}
	for entry in _entries:
		var owner_node: Variant = (entry.owner as WeakRef).get_ref()
		if not bool(entry.utility) or not _eligible(entry, owner_node, null): continue
		if not _contains(entry, pointer): continue
		if selected.is_empty() or _in_front(entry, selected): selected = entry
	return null if selected.is_empty() else (selected.owner as WeakRef).get_ref() as Node2D


func _process(delta: float) -> void:
	update_feedback(delta)


func update_feedback(delta: float, viewport_pointer := Vector2.INF) -> void:
	var screen := _get_screen()
	var controller := _get_controller()
	if screen == null or controller == null or not screen.is_visible_in_tree() or not _focused:
		_clear_feedback()
		return
	_refresh_elapsed += maxf(delta, 0.0)
	if _refresh_elapsed >= 0.3: refresh_targets()
	var pointer := viewport_pointer if viewport_pointer.is_finite() else get_viewport().get_mouse_position()
	if controller.is_world_input_blocked() or controller.is_pointer_over_ui_at(pointer):
		_clear_feedback()
		return
	var selected: Dictionary = {}
	var held: Node2D = controller.current_drag_node if controller.is_dragging() else null
	for entry in _entries:
		var owner_node: Variant = (entry.owner as WeakRef).get_ref()
		if not _eligible(entry, owner_node, held): continue
		if owner_node == held:
			selected = entry
			break
		if held != null: continue
		if controller.has_active_action():
			if controller.action_owner == owner_node:
				selected = entry
				break
			continue
		if not _contains(entry, pointer): continue
		if selected.is_empty() or _in_front(entry, selected): selected = entry
	var next: Node2D = null if selected.is_empty() else (selected.owner as WeakRef).get_ref() as Node2D
	if next == null or next != get_hovered_owner():
		_clear_feedback()
		if next != null:
			_hovered = weakref(next)
			_apply(selected)
	if next != null: _update_materials(next, bool(selected.utility))


func _add_target(owner_node: Node2D, utility: bool, handle: TablePlaceable = null) -> void:
	for entry in _entries:
		if (entry.owner as WeakRef).get_ref() == owner_node: return
	var sprites: Array[WeakRef] = []
	_collect_sprites(owner_node, owner_node, sprites)
	if sprites.is_empty(): return
	_entries.append({"owner": weakref(owner_node), "sprites": sprites, "utility": utility,
		"handle": weakref(handle) if handle != null else null})


func _collect_sprites(node: Node, owner_node: Node2D, output: Array[WeakRef]) -> void:
	if node != owner_node:
		# A tray's contents, stove dials and stored cups are separate owners.
		if node is Cup or node is StoveDial or node.get_node_or_null("PlacementHandle") is TablePlaceable:
			return
		if node.name in [&"Cups", &"Contents", &"CleanPickup"]: return
	if node is Sprite2D: output.append(weakref(node))
	for child in node.get_children(): _collect_sprites(child, owner_node, output)


func _eligible(entry: Dictionary, owner_node: Variant, held: Node2D) -> bool:
	if not _live(owner_node) or not owner_node.is_visible_in_tree(): return false
	if owner_node == held: return true
	if owner_node is Cup and (owner_node.returning_to_surface or not owner_node.input_pickable): return false
	var handle: Variant = (entry.handle as WeakRef).get_ref() if entry.handle != null else null
	if handle != null and (not _live(handle.surface) or not handle.surface.is_registered(owner_node)):
		return false
	return true


func _contains(entry: Dictionary, pointer: Vector2) -> bool:
	for reference: WeakRef in entry.sprites:
		var sprite := reference.get_ref() as Sprite2D
		if not _live(sprite) or not sprite.is_visible_in_tree() or sprite.texture == null or sprite.modulate.a <= 0.0 or sprite.self_modulate.a <= 0.0:
			continue
		var projection := sprite.get_global_transform_with_canvas()
		if is_zero_approx(projection.determinant()): continue
		if sprite.is_pixel_opaque(projection.affine_inverse() * pointer): return true
	return false


func _in_front(candidate: Dictionary, current: Dictionary) -> bool:
	var a := (candidate.owner as WeakRef).get_ref() as Node2D
	var b := (current.owner as WeakRef).get_ref() as Node2D
	var za := _effective_z(a)
	var zb := _effective_z(b)
	if za != zb: return za > zb
	if a.is_ancestor_of(b): return false
	if b.is_ancestor_of(a): return true
	var common := a.get_parent()
	while common != null and not common.is_ancestor_of(b): common = common.get_parent()
	if common is Node2D and common.y_sort_enabled:
		var ar := _sorted_branch(a, common)
		var br := _sorted_branch(b, common)
		var ay: float = common.to_local(ar.global_position).y
		var by: float = common.to_local(br.global_position).y
		if ay != by: return ay > by
		return ar.is_greater_than(br)
	return a.is_greater_than(b)


func _sorted_branch(owner_node: Node2D, common: Node2D) -> Node2D:
	var result := owner_node
	var ancestor := owner_node.get_parent()
	while ancestor != null and ancestor != common:
		if ancestor is Node2D and not ancestor.y_sort_enabled: result = ancestor
		ancestor = ancestor.get_parent()
	return result


func _effective_z(node: CanvasItem) -> int:
	var value := _base_z(node)
	var ancestor := node.get_parent() as CanvasItem
	while _base_z_relative(node) and ancestor != null:
		value += _base_z(ancestor)
		node = ancestor
		ancestor = node.get_parent() as CanvasItem
	return value


func _base_z(node: CanvasItem) -> int:
	return int(_lifted.z_index) if not _lifted.is_empty() and (_lifted.owner as WeakRef).get_ref() == node else node.z_index


func _base_z_relative(node: CanvasItem) -> bool:
	return bool(_lifted.z_relative) if not _lifted.is_empty() and (_lifted.owner as WeakRef).get_ref() == node else node.z_as_relative


func _apply(entry: Dictionary) -> void:
	if bool(entry.utility):
		var owner_node := (entry.owner as WeakRef).get_ref() as Node2D
		_lifted = {"owner": entry.owner, "z_index": owner_node.z_index, "z_relative": owner_node.z_as_relative}
		owner_node.z_as_relative = false
		owner_node.z_index = 125
	for reference: WeakRef in entry.sprites:
		var sprite := reference.get_ref() as Sprite2D
		if not _live(sprite): continue
		var material := ShaderMaterial.new()
		material.shader = OUTLINE
		material.set_shader_parameter("outline_enabled", sprite.name != &"ContentsOverlay")
		_applied.append({"sprite": reference, "original": sprite.material, "material": material})
		sprite.material = material


func _update_materials(owner_node: Node2D, utility: bool) -> void:
	var pivot := owner_node.get_global_transform_with_canvas().origin
	for entry in _applied:
		var sprite := (entry.sprite as WeakRef).get_ref() as Sprite2D
		if not _live(sprite): continue
		var projection := sprite.get_global_transform_with_canvas()
		if is_zero_approx(projection.determinant()): continue
		var material: ShaderMaterial = entry.material
		material.set_shader_parameter("pop_pivot", projection.affine_inverse() * pivot)
		material.set_shader_parameter("pop_scale", utility_pop_scale if utility else item_pop_scale)
		material.set_shader_parameter("outline_texels", Vector2(stroke_pixels / maxf(projection.x.length(), 0.001),
			stroke_pixels / maxf(projection.y.length(), 0.001)))


func _clear_feedback() -> void:
	for entry in _applied:
		var sprite := (entry.sprite as WeakRef).get_ref() as Sprite2D
		if not is_instance_valid(sprite): continue
		if sprite.material == entry.material: sprite.material = entry.original
	if not _lifted.is_empty():
		var owner_node := (_lifted.owner as WeakRef).get_ref() as Node2D
		if is_instance_valid(owner_node) and owner_node.z_index == 125 and not owner_node.z_as_relative:
			owner_node.z_index = _lifted.z_index
			owner_node.z_as_relative = _lifted.z_relative
	_lifted.clear()
	_applied.clear()
	_hovered = null


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_focused = false
		_clear_feedback()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN]:
		_focused = true


func _exit_tree() -> void:
	_clear_feedback()


func _get_screen() -> Node2D:
	var value: Variant = _screen.get_ref() if _screen != null else null
	return value as Node2D if _live(value) else null


func _get_controller() -> InteractionController:
	var value: Variant = _controller.get_ref() if _controller != null else null
	return value as InteractionController if _live(value) else null


static func _live(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node and value.is_inside_tree() and not value.is_queued_for_deletion()
