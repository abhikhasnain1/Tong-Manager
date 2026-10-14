class_name OrderRequestDef
extends Resource
## An editable request for one drink or one ready-item piece, never a bundle.

const RECIPE_SCRIPT: Script = preload("res://scripts/data/recipe_def.gd")

@export var id: StringName
@export_enum("tea", "ready_item") var kind := "tea"
@export var recipe_id: StringName
@export var item_id: StringName
@export var quantity := 1


func validate(catalog: Node, require_unlocked := true) -> PackedStringArray:
	var errors: Array[String] = []
	if not valid_identity(id): errors.append("Request needs a nonblank stable ID")
	if quantity != 1: errors.append("Requests support exactly one serving or piece")
	if not is_instance_valid(catalog):
		errors.append("Catalog is unavailable")
		return PackedStringArray(errors)
	match kind:
		"tea":
			if not valid_identity(recipe_id) or not item_id.is_empty():
				errors.append("Tea requests need only a recipe ID")
			else:
				_validate_recipe(catalog, require_unlocked, errors)
		"ready_item":
			if not valid_identity(item_id) or not recipe_id.is_empty():
				errors.append("Ready-item requests need only an item ID")
			else:
				var item := lookup(catalog, "items", item_id) as ItemDef
				if item == null:
					errors.append("Unknown ready item: " + String(item_id))
				elif item.id != item_id or item.category != &"ready_item" or item.unit != &"piece":
					errors.append("Ready items must resolve to their own ready_item identity and piece unit")
				elif item.sell_price <= 0:
					errors.append("Ready items need a positive sell price")
		_:
			errors.append("Unsupported request kind: " + kind)
	return PackedStringArray(errors)


func snapshot(catalog: Node, require_unlocked := true) -> Dictionary:
	if not validate(catalog, require_unlocked).is_empty(): return {}
	var data := {
		"id": id, "kind": StringName(kind), "recipe_id": recipe_id, "item_id": item_id,
		"quantity": quantity, "unit": &"cup" if kind == "tea" else &"piece",
	}
	if kind == "ready_item":
		var item := lookup(catalog, "items", item_id) as ItemDef
		data.merge({"display_name_key": item.display_name_key, "icon": item.icon, "price": item.sell_price})
	else:
		var recipe := lookup(catalog, "recipes", recipe_id)
		var liquid := lookup(catalog, "items", recipe.get("brewed_liquid_id")) as ItemDef
		data.merge({"display_name_key": recipe.get("display_name_key"), "icon": liquid.icon,
			"price": recipe.get("price")})
		for field in ["output_item_id", "brewed_liquid_id", "base_item_ids", "relish_item_ids",
			"kettle_portion_counts", "kettle_portion_units", "cup_portion_counts", "cup_portion_units",
			"batch_requires_boiling_water", "max_batch_volume_ml", "target_serving_volume_ml",
			"minimum_serving_volume_ml"]:
			data[field] = recipe.get(field)
	# Dictionaries/arrays are owned by this snapshot. Art remains a shared resource.
	return data.duplicate(true)


func _validate_recipe(catalog: Node, require_unlocked: bool, errors: Array[String]) -> void:
	var recipe := lookup(catalog, "recipes", recipe_id)
	if recipe == null:
		errors.append("Unknown recipe: " + String(recipe_id))
		return
	if recipe.get_script() != RECIPE_SCRIPT:
		errors.append("Recipe must use the recipe definition resource")
		return
	if recipe.get("id") != recipe_id:
		errors.append("Recipe identity does not match its catalog key")
	if not bool(recipe.get("production_supported")):
		errors.append("Recipe is not supported for production orders")
	if require_unlocked and not bool(recipe.get("unlocked_by_default")):
		errors.append("Recipe is locked for the current level")
	if int(recipe.get("price")) <= 0: errors.append("Recipe needs a positive price")
	if not valid_identity(StringName(recipe.get("output_item_id"))):
		errors.append("Recipe needs a finished output identity")
	var bases: Array = recipe.get("base_item_ids")
	var relishes: Array = recipe.get("relish_item_ids")
	_validate_item_ids(catalog, bases, "base", errors)
	_validate_item_ids(catalog, relishes, "relish", errors)
	if bool(recipe.get("batch_requires_boiling_water")) and &"water" not in bases:
		errors.append("A boiling-water recipe needs its measured water base")
	var liquid_id := StringName(recipe.get("brewed_liquid_id"))
	var liquid := lookup(catalog, "items", liquid_id) as ItemDef
	if not valid_identity(liquid_id) or liquid == null or liquid.id != liquid_id or liquid_id not in bases:
		errors.append("Brewed liquid must resolve through the recipe's catalog base identities")
	var kettle_counts: Dictionary = recipe.get("kettle_portion_counts")
	var kettle_units: Dictionary = recipe.get("kettle_portion_units")
	var cup_counts: Dictionary = recipe.get("cup_portion_counts")
	var cup_units: Dictionary = recipe.get("cup_portion_units")
	if kettle_counts.is_empty(): errors.append("Tea recipe needs a batch ingredient")
	_validate_portions(catalog, kettle_counts, kettle_units, "kettle", errors)
	_validate_portions(catalog, cup_counts, cup_units, "cup", errors)
	for ingredient in kettle_counts:
		if ingredient not in bases: errors.append("Kettle portion is missing from recipe bases: " + String(ingredient))
	for ingredient in cup_counts:
		if ingredient not in relishes: errors.append("Cup portion is missing from recipe relishes: " + String(ingredient))
	for ingredient in relishes:
		if not cup_counts.has(ingredient): errors.append("Recipe relish has no desired cup amount: " + String(ingredient))
	for ingredient in bases:
		if ingredient != &"water" and not kettle_counts.has(ingredient):
			errors.append("Recipe base has no desired batch amount: " + String(ingredient))
	var minimum := float(recipe.get("minimum_serving_volume_ml"))
	var target := float(recipe.get("target_serving_volume_ml"))
	var batch := float(recipe.get("max_batch_volume_ml"))
	if (not is_finite(minimum) or not is_finite(target) or not is_finite(batch)
		or minimum <= 0.0 or minimum > target or target > batch):
		errors.append("Serving volumes must be finite and positive, with minimum <= target <= batch")


func _validate_item_ids(catalog: Node, ids: Array, label: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for ingredient in ids:
		var item := lookup(catalog, "items", ingredient) as ItemDef
		if not valid_identity(StringName(ingredient)) or item == null or item.id != ingredient:
			errors.append("Unknown recipe %s item: %s" % [label, ingredient])
		if ingredient == &"water" and item != null and item.unit != &"ml":
			errors.append("Water retains its measured ml unit")
		if seen.has(ingredient): errors.append("Duplicate recipe %s item: %s" % [label, ingredient])
		seen[ingredient] = true


func _validate_portions(catalog: Node, counts: Dictionary, units: Dictionary, label: String, errors: Array[String]) -> void:
	for ingredient in counts:
		var item := lookup(catalog, "items", ingredient) as ItemDef
		if item == null or item.id != ingredient or not item.supports_portions() or item.category == &"ready_item":
			errors.append("Unknown or non-ingredient %s portion: %s" % [label, ingredient])
		if typeof(counts[ingredient]) != TYPE_INT or int(counts[ingredient]) <= 0:
			errors.append("Desired %s portion amounts must be positive integers" % label)
		if item != null and (not units.has(ingredient) or units[ingredient] != item.unit):
			errors.append("Desired %s portion unit does not match the catalog: %s" % [label, ingredient])
	for ingredient in units:
		if not counts.has(ingredient): errors.append("%s portion unit has no matching amount: %s" % [label, ingredient])


static func valid_identity(value: StringName) -> bool:
	var text := String(value)
	return not text.is_empty() and text == text.strip_edges()


static func lookup(catalog: Node, collection: String, resource_id: StringName) -> Resource:
	if not is_instance_valid(catalog): return null
	var resources: Variant = catalog.get(collection)
	return resources.get(resource_id) as Resource if resources is Dictionary else null
