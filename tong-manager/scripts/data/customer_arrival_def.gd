class_name CustomerArrivalDef
extends Resource
## One authored visit. Zero patience inherits the selected profile's value.

@export var id: StringName
@export_range(0.0, 3600.0, 0.1, "or_greater") var due_seconds := 0.0
@export var customer: CustomerDef
@export var request: OrderRequestDef
@export_range(0.0, 600.0, 0.1, "or_greater") var patience_override := 0.0
