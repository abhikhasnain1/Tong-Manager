extends Node

@export var item_folder_path: String = "res://data/items"
@export var recipe_folder_path: String = "res://data/recipes"
@export var customer_folder_path: String = "res://data/customers"
@export var balance_folder_path: String = "res://data/balance"

var items: Dictionary = {}
var recipes: Dictionary = {}
var customers: Dictionary = {}
var tool_defs: Dictionary = {}
var day_configs: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	items.clear()
	recipes.clear()
	customers.clear()
	tool_defs.clear()
	day_configs.clear()

	_load_id_resources(item_folder_path, items, "item")
	_load_id_resources(recipe_folder_path, recipes, "recipe")
	_load_id_resources(customer_folder_path, customers, "customer")
	_load_named_resources(balance_folder_path, tool_defs, "tool_def", "tool")
	_load_named_resources(balance_folder_path, day_configs, "day_config", "day config")

	print(
		"Catalog loaded: %d items, %d recipes, %d customers, %d tool defs, %d day configs"
		% [items.size(), recipes.size(), customers.size(), tool_defs.size(), day_configs.size()]
	)


func get_item(id: StringName) -> Resource:
	return _get_resource(items, id, "item")


func get_recipe(id: StringName) -> Resource:
	return _get_resource(recipes, id, "recipe")


func get_tool_def(id: StringName) -> Resource:
	return _get_resource(tool_defs, id, "tool def")


func get_day_config(id: StringName) -> Resource:
	return _get_resource(day_configs, id, "day config")


func _load_id_resources(folder_path: String, target: Dictionary, label: String) -> void:
	for resource in _load_resources_from_folder(folder_path, label):
		var id_value = resource.get("id")
		if id_value == null or String(id_value).is_empty():
			push_warning("Catalog skipped %s resource with missing id." % label)
			continue

		var resource_id := StringName(id_value)
		if target.has(resource_id):
			_report_duplicate(label, resource_id)
			continue

		target[resource_id] = resource


func _load_named_resources(folder_path: String, target: Dictionary, script_file_name: String, label: String) -> void:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_warning("Catalog could not open %s folder: %s" % [label, folder_path])
		return

	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue

		var resource_path := folder_path.path_join(file_name)
		var resource := load(resource_path) as Resource
		if resource == null:
			push_warning("Catalog skipped non-resource file: %s" % resource_path)
			continue

		var script: Script = resource.get_script()
		if script == null or script.resource_path.get_file() != "%s.gd" % script_file_name:
			continue

		var resource_id := StringName(file_name.get_basename())
		if target.has(resource_id):
			_report_duplicate(label, resource_id)
			continue

		target[resource_id] = resource


func _load_resources_from_folder(folder_path: String, label: String) -> Array[Resource]:
	var loaded_resources: Array[Resource] = []
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_warning("Catalog could not open %s folder: %s" % [label, folder_path])
		return loaded_resources

	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue

		var resource_path := folder_path.path_join(file_name)
		var resource := load(resource_path) as Resource
		if resource == null:
			push_warning("Catalog skipped non-resource file: %s" % resource_path)
			continue

		loaded_resources.append(resource)

	return loaded_resources


func _get_resource(source: Dictionary, id: StringName, label: String) -> Resource:
	if source.has(id):
		return source[id] as Resource

	push_warning("Catalog missing %s id: %s" % [label, id])
	return null


func _report_duplicate(label: String, id: StringName) -> void:
	var message: String = "Catalog duplicate %s id: %s" % [label, id]
	push_error(message)
	assert(false, message)
