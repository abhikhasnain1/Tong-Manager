class_name KhataInventoryPage
extends Control
## Shared-stock presentation only. Book input forwarding owns all extraction.

signal content_changed

const SLOT_SCENE := preload("res://scenes/ui/khata/KhataItemSlot.tscn")
const INK := Color("493d30")
const SOFT_INK := Color("85735d")
const ITEMS_PER_PAGE := 5
const GRID_RECT := Rect2(44, 170, 376, 326)
const ROW_HEIGHT := 154.0
const COLUMN_GAP := 12.0
const ROW_GAP := 18.0

var page_index := 0
var paper: Texture2D
var item_page_index := 0
var page_count: int:
	get: return maxi(1, ceili(float(_items.size()) / ITEMS_PER_PAGE))
var _inventory: PortionStockProvider
var _items: Array[ItemDef] = []
var _items_configured := false
var _slots: Dictionary[StringName, KhataItemSlot] = {}
var _grid: GridContainer
var _hovered_item: StringName = &""
var _interaction_enabled := true
var _font: Font = ThemeDB.fallback_font
var _title_font := SystemFont.new()


func _init() -> void:
	size = Vector2(480, 660)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_title_font.font_names = PackedStringArray(["Georgia", "Noto Serif", "serif"])


func configure(index: int, texture: Texture2D) -> void:
	page_index = index
	paper = texture
	size = Vector2(480, 660)
	_ensure_grid()
	_grid.visible = page_index == 1
	if page_index != 1:
		_hovered_item = &""
	_refresh_stock()
	queue_redraw()
	content_changed.emit()


func configure_items(entries: Array[ItemDef]) -> void:
	_items.clear()
	var ids: Array[StringName] = []
	for item in entries:
		if item != null and item.supports_portions() and item.pantry_enabled and not ids.has(item.id):
			_items.append(item)
			ids.append(item.id)
	_items_configured = true
	item_page_index = clampi(item_page_index, 0, page_count - 1)
	_rebuild_grid()


func get_item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for item in _items: ids.append(item.id)
	return ids


func item_unit(id: StringName) -> StringName:
	for item in _items:
		if item.id == id: return item.unit
	return &""


func navigation_rect(direction: int) -> Rect2:
	if page_index != 1 or page_count <= 1 or direction not in [-1, 1]:
		return Rect2()
	return Rect2(280 if direction < 0 else 384, 548, 40, 40)


func navigation_at(local_point: Vector2) -> int:
	if not _interaction_enabled or not local_point.is_finite(): return 0
	for direction: int in [-1, 1]:
		if navigation_rect(direction).has_point(local_point): return direction
	return 0


func change_item_page(direction: int) -> bool:
	var next := item_page_index + direction
	if page_index != 1 or not _interaction_enabled or direction not in [-1, 1] or next < 0 or next >= page_count:
		return false
	item_page_index = next
	_rebuild_grid()
	return true


func bind_inventory(provider: PortionStockProvider) -> void:
	_disconnect_inventory()
	_inventory = provider
	_connect_inventory()
	_refresh_stock()


func item_at(local_point: Vector2) -> StringName:
	if page_index != 1 or not _interaction_enabled or not is_finite(local_point.x) or not is_finite(local_point.y):
		return &""
	for id: StringName in _slots:
		if item_rect(id).has_point(local_point):
			return id
	return &""


func item_rect(id: StringName) -> Rect2:
	if page_index != 1 or not _slots.has(id):
		return Rect2()
	var slot: KhataItemSlot = _slots[id]
	var row := slot.get_parent() as Control
	return Rect2(_grid.position + row.position + slot.position, slot.size)


func item_display(id: StringName) -> Dictionary:
	if _slots.has(id):
		return _slots[id].display_snapshot()
	for item in _items:
		if item.id != id: continue
		var bound := is_instance_valid(_inventory)
		var total: int = _inventory.remaining(id) if bound else 0
		var available: int = _inventory.available(id) if bound else 0
		var status := "Unavailable" if not bound else ("Out of stock" if total == 0 else ("%d held" % (total - available) if available < total else ""))
		return {"item_id": id, "label": item.get_portion_label(), "unit": item.unit,
			"remaining": total, "available": available, "stock_bound": bound,
			"status": status, "hovered": false, "interaction_enabled": _interaction_enabled}
	return {}


func set_hovered_item(id: StringName) -> void:
	var next := id if page_index == 1 and _interaction_enabled and _slots.has(id) else &""
	if next == _hovered_item:
		return
	_hovered_item = next
	for key: StringName in _slots:
		_slots[key].set_hovered(key == _hovered_item)
	queue_redraw()
	content_changed.emit()


func set_interaction_enabled(value: bool) -> void:
	if _interaction_enabled == value:
		return
	_interaction_enabled = value
	if not value:
		_hovered_item = &""
	for key: StringName in _slots:
		_slots[key].set_interaction_enabled(value)
		_slots[key].set_hovered(key == _hovered_item)
	queue_redraw()
	content_changed.emit()


func _enter_tree() -> void:
	_connect_inventory()
	_refresh_stock()


func _exit_tree() -> void:
	_disconnect_inventory()
	_hovered_item = &""
	for slot: KhataItemSlot in _slots.values():
		slot.set_hovered(false)


func _connect_inventory() -> void:
	if is_inside_tree() and is_instance_valid(_inventory) and not _inventory.changed.is_connected(_refresh_stock):
		_inventory.changed.connect(_refresh_stock)


func _disconnect_inventory() -> void:
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(_refresh_stock):
		_inventory.changed.disconnect(_refresh_stock)


func _refresh_stock() -> void:
	var changed := false
	var bound := is_instance_valid(_inventory)
	for id: StringName in _slots:
		var total: int = _inventory.remaining(id) if bound else 0
		var free: int = _inventory.available(id) if bound else 0
		changed = _slots[id].set_stock(total, free, bound) or changed
	if changed:
		queue_redraw()
		content_changed.emit()


func _ensure_grid() -> void:
	if is_instance_valid(_grid):
		return
	if not _items_configured:
		var tree := Engine.get_main_loop() as SceneTree
		var catalog := tree.root.get_node_or_null("Catalog") if tree != null else null
		if catalog != null:
			_items = catalog.get_pantry_items()
		_items_configured = true
	_grid = GridContainer.new()
	_grid.name = "ItemGrid"
	_grid.columns = 1
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.position = GRID_RECT.position
	_grid.size = GRID_RECT.size
	_grid.add_theme_constant_override("v_separation", int(ROW_GAP))
	add_child(_grid)
	_grid.visible = page_index == 1
	var start := item_page_index * ITEMS_PER_PAGE
	var count := mini(ITEMS_PER_PAGE, _items.size() - start)
	for row_index in range(2 if count > 3 else 1):
		var columns := mini(3, count) if row_index == 0 else count - 3
		if columns <= 0: continue
		var row := GridContainer.new()
		row.name = "Ingredients" if row_index == 0 else "ReadyItems"
		row.columns = columns
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(GRID_RECT.size.x, ROW_HEIGHT)
		row.add_theme_constant_override("h_separation", int(COLUMN_GAP))
		_grid.add_child(row)
		row.position = Vector2(0, row_index * (ROW_HEIGHT + ROW_GAP))
		row.size = Vector2(GRID_RECT.size.x, ROW_HEIGHT)
		var cell_width := (GRID_RECT.size.x - COLUMN_GAP * (row.columns - 1)) / row.columns
		for column in range(row.columns):
			var index := start + (column if row_index == 0 else 3 + column)
			var item := _items[index]
			var slot := SLOT_SCENE.instantiate() as KhataItemSlot
			slot.name = String(item.id)
			slot.configure(item.id, item.get_portion_label(), item.unit, item.icon)
			row.add_child(slot)
			slot.position = Vector2(column * (cell_width + COLUMN_GAP), 0)
			slot.size = Vector2(cell_width, ROW_HEIGHT)
			slot.set_interaction_enabled(_interaction_enabled)
			slot.resized.connect(_on_slot_resized)
			_slots[item.id] = slot


func _rebuild_grid() -> void:
	_hovered_item = &""
	_slots.clear()
	if is_instance_valid(_grid):
		remove_child(_grid)
		_grid.queue_free()
	_grid = null
	_ensure_grid()
	_refresh_stock()
	queue_redraw()
	content_changed.emit()


func _on_slot_resized() -> void:
	if is_inside_tree():
		content_changed.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 660), Color("f0e4c8"))
	if paper != null:
		draw_texture_rect(paper, Rect2(0, 0, 480, 660), false)
	if page_index != 1:
		return
	draw_string(_font, Vector2(44, 55), "KHATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SOFT_INK)
	draw_string(_title_font, Vector2(44, 108), "Pantry", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, INK)
	draw_line(Vector2(44, 137), Vector2(436, 137), Color(0.38, 0.29, 0.20, 0.28), 1)
	draw_string(_font, Vector2(46, 157), "In stock", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SOFT_INK)
	draw_string(_font, Vector2(260, 157), "One portion per grab", HORIZONTAL_ALIGNMENT_RIGHT, 158, 14, SOFT_INK)
	var hint := ""
	if _slots.has(_hovered_item):
		var slot: KhataItemSlot = _slots[_hovered_item]
		hint = String(slot.display_snapshot().status)
		if hint.is_empty():
			hint = "%s · 1 %s" % [slot.item_label, slot.unit]
	draw_string(_font, Vector2(46, 535), hint, HORIZONTAL_ALIGNMENT_LEFT, 374, 16, SOFT_INK)
	if page_count > 1:
		for direction: int in [-1, 1]:
			var rect := navigation_rect(direction)
			var enabled: bool = _interaction_enabled and item_page_index + direction >= 0 and item_page_index + direction < page_count
			var ink := INK if enabled else Color(SOFT_INK, 0.4)
			var center := rect.get_center()
			var arrow := PackedVector2Array([center + Vector2(-direction * 5, -9), center + Vector2(direction * 5, 0), center + Vector2(-direction * 5, 9)])
			draw_polyline(arrow, ink, 2, true)
		draw_string(_font, Vector2(328, 574), "%d / %d" % [item_page_index + 1, page_count], HORIZONTAL_ALIGNMENT_CENTER, 48, 14, SOFT_INK)
	draw_string(_font, Vector2(220, 615), str(page_index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, SOFT_INK)
