class_name PlacementSurface
extends Node2D

# Numerical area tolerance in surface-local square units, not gameplay spacing.
# Shared edges have zero area and are allowed; no footprint is padded or shrunk.
const AREA_EPSILON := 0.0001
const LINEAR_EPSILON := 0.000001
const TRANSFORM_EPSILON := 0.000000000001

@export var usable_polygon: PackedVector2Array = PackedVector2Array()
@export_node_path("Node2D") var placement_parent_path: NodePath

# Weak identity plus copied geometry prevents stale instance IDs and caller edits
# from changing reservations. A drag leaves its old committed polygons occupied.
var _items: Dictionary = {}
var _vacated_positions := PackedVector2Array()


func get_placement_parent() -> Node2D:
	if not _live(self) or placement_parent_path.is_empty():
		return null
	var parent := get_node_or_null(placement_parent_path) as Node2D
	return parent if _live(parent) else null


func register_item(item: Node2D, local_footprints: Array[PackedVector2Array]) -> bool:
	_purge_invalid_items()
	if not _live(item) or not _live(self) or not _valid_footprints(local_footprints):
		return false
	var candidates := _transform_footprints(item, local_footprints)
	if not _validate_candidates(item, candidates).is_valid:
		return false
	_items[item.get_instance_id()] = {
		"item": weakref(item),
		"footprints": _copy_polygons(local_footprints),
		"committed": _copy_polygons(candidates),
	}
	return true


func is_registered(item: Node2D) -> bool:
	_purge_invalid_items()
	return _has_identity(item)


func validate_item(item: Node2D) -> DropValidation:
	_purge_invalid_items()
	if not _live(self) or not _live(item):
		return DropValidation.invalid("placement.unavailable")
	if not _has_identity(item):
		return DropValidation.invalid("placement.unregistered")
	return _validate_candidates(item, get_candidate_polygons(item))


func validate_candidate(item: Node2D, local_footprints: Array[PackedVector2Array]) -> DropValidation:
	# Preview a possible destination without registering the item, changing its
	# current reservation, or releasing its reservation on another surface.
	if not _live(self) or not _live(item):
		return DropValidation.invalid("placement.unavailable")
	return _validate_candidates(item, project_footprints(item, local_footprints))


func project_footprints(item: Node2D, local_footprints: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	# Surface-local preview geometry is independent of registration and fit.
	if not _live(self) or not _live(item) or not _valid_footprints(local_footprints):
		return []
	var candidates := _transform_footprints(item, local_footprints)
	if not _valid_footprints(candidates):
		return []
	return candidates


func commit_item(item: Node2D) -> bool:
	# Revalidate at commit; an invalid move never releases the prior reservation.
	if not validate_item(item).is_valid:
		return false
	_remember_vacancy(_items[item.get_instance_id()]["committed"])
	_items[item.get_instance_id()]["committed"] = get_candidate_polygons(item)
	return true


func unregister_item(item: Node2D) -> void:
	_purge_invalid_items()
	if _has_identity(item):
		_remember_vacancy(_items[item.get_instance_id()]["committed"])
		_items.erase(item.get_instance_id())


func get_vacated_positions() -> PackedVector2Array:
	return _vacated_positions.duplicate()


func _remember_vacancy(polygons: Array[PackedVector2Array]) -> void:
	# A just-freed cup position may fit exactly between neighbours. Keep its
	# continuous coordinates so automatic returns need not hit a sampled grid.
	for polygon in polygons:
		if polygon.is_empty(): continue
		var center := Vector2.ZERO
		for point in polygon: center += point
		center /= polygon.size()
		_vacated_positions.append(center)
	while _vacated_positions.size() > 64: _vacated_positions.remove_at(0)


func get_candidate_polygons(item: Node2D) -> Array[PackedVector2Array]:
	_purge_invalid_items()
	if not _live(self) or not _has_identity(item):
		return []
	return _transform_footprints(item, _items[item.get_instance_id()]["footprints"])


func get_committed_polygons(item: Node2D) -> Array[PackedVector2Array]:
	_purge_invalid_items()
	if not _has_identity(item):
		return []
	return _copy_polygons(_items[item.get_instance_id()]["committed"])


func get_free_regions() -> Array[PackedVector2Array]:
	# Broad-phase search regions only; every returned position still uses the
	# exact footprint validator, including any hole contours from clipping.
	_purge_invalid_items()
	var regions: Array[PackedVector2Array] = [usable_polygon.duplicate()]
	var blockers: Array[PackedVector2Array] = []
	var exclusions := get_node_or_null("Exclusions")
	if exclusions != null and not _collect_exclusions(exclusions, blockers): return []
	for record: Dictionary in _items.values():
		blockers.append_array(_copy_polygons(record.committed))
	for blocker in blockers:
		var next: Array[PackedVector2Array] = []
		for region in regions:
			next.append_array(Geometry2D.clip_polygons(region, blocker))
		regions = next
		if regions.is_empty(): break
	return regions


func _validate_candidates(item: Node2D, candidates: Array[PackedVector2Array]) -> DropValidation:
	if not _valid_transform(global_transform) or not _valid_polygon(usable_polygon) or not _valid_footprints(candidates):
		return DropValidation.invalid("placement.invalid_geometry")
	var exclusions: Array[PackedVector2Array] = []
	var exclusion_root := get_node_or_null("Exclusions")
	if exclusion_root != null and not _collect_exclusions(exclusion_root, exclusions):
		return DropValidation.invalid("placement.invalid_geometry")
	for polygon in candidates:
		# Difference catches edges crossing a concave boundary even when every
		# footprint vertex is inside. Boolean outputs may include hole contours.
		if _filled_area(Geometry2D.clip_polygons(polygon, usable_polygon)) > AREA_EPSILON:
			return DropValidation.invalid("placement.outside_surface")
		for exclusion in exclusions:
			if _overlap_area(polygon, exclusion) > AREA_EPSILON:
				return DropValidation.invalid("placement.blocked")
		for record: Dictionary in _items.values():
			var peer := (record["item"] as WeakRef).get_ref() as Node2D
			# Candidate previews are read-only: ignore stale peers without purging
			# the reservation dictionary as the mutating APIs normally do.
			if not _live(peer) or peer == item:
				continue
			for peer_polygon: PackedVector2Array in record["committed"]:
				if _overlap_area(polygon, peer_polygon) > AREA_EPSILON:
					return DropValidation.invalid("placement.overlap")
	return DropValidation.valid()


func _collect_exclusions(parent: Node, polygons: Array[PackedVector2Array]) -> bool:
	for child in parent.get_children():
		if child is Polygon2D:
			var shape := child as Polygon2D
			if not _valid_transform(shape.global_transform) or not shape.offset.is_finite() or not _valid_polygon(shape.polygon):
				return false
			var relative := _relative_transform(shape) * Transform2D(0.0, shape.offset)
			var polygon := relative * shape.polygon
			if not _valid_polygon(polygon):
				return false
			polygons.append(polygon)
		if not _collect_exclusions(child, polygons):
			return false
	return true


func _transform_footprints(item: Node2D, footprints: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if not _valid_transform(global_transform) or not _valid_transform(item.global_transform):
		return []
	var relative := _relative_transform(item)
	if not _valid_transform(relative):
		return []
	var result: Array[PackedVector2Array] = []
	for polygon in footprints:
		result.append(relative * polygon)
	return result


func _relative_transform(item: Node2D) -> Transform2D:
	# Cancel a shared Node2D ancestor symbolically instead of multiplying its
	# scaled global matrix by an approximate inverse. This is equivalent to
	# surface^-1 * item globally, but keeps exact authored edge contacts stable
	# when the whole workstation is resized. Stop at top-level/bare-node breaks.
	var item_ancestors: Dictionary = {}
	var ancestor := item
	var item_to_ancestor := Transform2D.IDENTITY
	while ancestor != null:
		item_ancestors[ancestor] = item_to_ancestor
		if ancestor.is_set_as_top_level():
			break
		item_to_ancestor = ancestor.transform * item_to_ancestor
		ancestor = ancestor.get_parent() as Node2D
	ancestor = self
	var surface_to_ancestor := Transform2D.IDENTITY
	while ancestor != null:
		if item_ancestors.has(ancestor) and _valid_transform(surface_to_ancestor):
			return surface_to_ancestor.affine_inverse() * (item_ancestors[ancestor] as Transform2D)
		if ancestor.is_set_as_top_level():
			break
		surface_to_ancestor = ancestor.transform * surface_to_ancestor
		ancestor = ancestor.get_parent() as Node2D
	# Different transform roots (including Control parents) still use Godot's
	# complete global transform semantics rather than assuming common ancestry.
	return global_transform.affine_inverse() * item.global_transform


func _has_identity(item: Node2D) -> bool:
	if not _live(item) or not _items.has(item.get_instance_id()):
		return false
	return (_items[item.get_instance_id()]["item"] as WeakRef).get_ref() == item


func _purge_invalid_items() -> void:
	for id: int in _items.keys():
		var item := (_items[id]["item"] as WeakRef).get_ref() as Node2D
		if not _live(item) or item.get_instance_id() != id:
			_items.erase(id)


func _live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


func _valid_transform(value: Transform2D) -> bool:
	return value.is_finite() and is_finite(value.determinant()) and absf(value.determinant()) > TRANSFORM_EPSILON


func _valid_footprints(polygons: Array[PackedVector2Array]) -> bool:
	if polygons.is_empty():
		return false
	for polygon in polygons:
		if not _valid_polygon(polygon):
			return false
	return true


func _valid_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	for index in polygon.size():
		if not polygon[index].is_finite() or polygon[index].distance_squared_to(polygon[(index + 1) % polygon.size()]) <= LINEAR_EPSILON * LINEAR_EPSILON:
			return false
	var area := _signed_area(polygon)
	if not is_finite(area) or absf(area) <= AREA_EPSILON:
		return false
	# Boolean operations expect simple contours. Reject bow ties, repeated
	# non-neighbouring points and overlapping edges before calling the engine.
	for first in polygon.size():
		var first_next := (first + 1) % polygon.size()
		for second in range(first + 1, polygon.size()):
			var second_next := (second + 1) % polygon.size()
			if first_next == second or second_next == first:
				continue
			if _segments_touch(polygon[first], polygon[first_next], polygon[second], polygon[second_next]):
				return false
	return true


func _segments_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := (b - a).cross(c - a)
	var ab_d := (b - a).cross(d - a)
	var cd_a := (d - c).cross(a - c)
	var cd_b := (d - c).cross(b - c)
	if ((ab_c > LINEAR_EPSILON and ab_d < -LINEAR_EPSILON) or (ab_c < -LINEAR_EPSILON and ab_d > LINEAR_EPSILON)) and ((cd_a > LINEAR_EPSILON and cd_b < -LINEAR_EPSILON) or (cd_a < -LINEAR_EPSILON and cd_b > LINEAR_EPSILON)):
		return true
	return (
		(absf(ab_c) <= LINEAR_EPSILON and _between(c, a, b))
		or (absf(ab_d) <= LINEAR_EPSILON and _between(d, a, b))
		or (absf(cd_a) <= LINEAR_EPSILON and _between(a, c, d))
		or (absf(cd_b) <= LINEAR_EPSILON and _between(b, c, d))
	)


func _between(point: Vector2, a: Vector2, b: Vector2) -> bool:
	return point.x >= minf(a.x, b.x) - LINEAR_EPSILON and point.x <= maxf(a.x, b.x) + LINEAR_EPSILON and point.y >= minf(a.y, b.y) - LINEAR_EPSILON and point.y <= maxf(a.y, b.y) + LINEAR_EPSILON


func _overlap_area(first: PackedVector2Array, second: PackedVector2Array) -> float:
	return _filled_area(Geometry2D.intersect_polygons(first, second))


func _filled_area(contours: Array[PackedVector2Array]) -> float:
	# Geometry2D emits outer and hole contours with opposite winding. Summing
	# signed areas subtracts holes; summing absolute areas would count them twice.
	var total := 0.0
	for contour in contours:
		total += _signed_area(contour)
	return absf(total)


func _signed_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var total := 0.0
	var origin := polygon[0]
	for index in range(1, polygon.size() - 1):
		total += (polygon[index] - origin).cross(polygon[index + 1] - origin)
	return total * 0.5


func _copy_polygons(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon in polygons:
		result.append(polygon.duplicate())
	return result
