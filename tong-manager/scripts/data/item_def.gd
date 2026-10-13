class_name ItemDef
extends Resource

@export var id: StringName
@export var display_name_key: String
@export var category: StringName
@export var icon: Texture2D
@export var unit: StringName
@export var stack_size: int
@export var cost: int
@export var sell_price: int

@export_group("Portion presentation")
@export var pantry_enabled := false
@export var pantry_order := 0
@export var portion_label := ""
@export_enum("auto", "teabag", "spoon", "banana", "biscuit", "icon") var portion_visual := "auto"
@export var portion_color := Color("fff9ee")


func supports_portions() -> bool:
	return not id.is_empty() and unit in [&"teabag", &"spoonful", &"piece"]


func get_portion_label() -> String:
	return portion_label if not portion_label.strip_edges().is_empty() else String(id).capitalize()


func get_portion_name() -> String:
	var label := get_portion_label().to_lower()
	match unit:
		&"teabag": return "one teabag of %s" % label
		&"spoonful": return "one spoonful of %s" % label
		&"piece": return "one %s" % label
	return "one %s of %s" % [unit, label]


func get_portion_visual() -> String:
	if portion_visual != "auto":
		return portion_visual
	match unit:
		&"teabag": return "teabag"
		&"spoonful": return "spoon"
	return "icon"
