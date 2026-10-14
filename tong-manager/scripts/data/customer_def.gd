class_name CustomerDef
extends Resource
## Profile data only. Patience progression and conversation belong to consumers.

enum UnhappyResponse { ACCEPT, REFUSE_LEAVE, REFUSE_RETRY }
enum RemakePatience { CONTINUE, RESET }

@export var id: StringName
@export var display_name_key := ""
@export var sprite_texture: Texture2D
@export var patience_seconds := 60.0
@export var dialogue_profile: StringName
@export var order_requests: Array[OrderRequestDef] = []
@export var unhappy_response: UnhappyResponse = UnhappyResponse.ACCEPT
@export var remake_patience: RemakePatience = RemakePatience.CONTINUE

var order_recipe_ids: Array[StringName]:
	get:
		var ids: Array[StringName] = []
		for request in order_requests:
			if request != null and request.kind == "tea" and request.recipe_id not in ids:
				ids.append(request.recipe_id)
		return ids
	set(_value): pass


func get_request(request_id: StringName) -> OrderRequestDef:
	for request in order_requests:
		if request != null and request.id == request_id: return request
	return null


func get_service_policy() -> Dictionary:
	return service_policy(unhappy_response, remake_patience)


static func service_policy(response: int, patience: int) -> Dictionary:
	if response not in UnhappyResponse.values() or patience not in RemakePatience.values(): return {}
	return {"unhappy_response": [&"accept", &"refuse_leave", &"refuse_retry"][response],
		"remake_patience": [&"continue", &"reset"][patience]}


func validate(catalog: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if not OrderRequestDef.valid_identity(id): errors.append("Customer needs a nonblank stable ID")
	if display_name_key.strip_edges().is_empty(): errors.append("Customer needs a display-name key")
	if not is_finite(patience_seconds) or patience_seconds <= 0.0:
		errors.append("Customer patience must be finite and positive")
	if get_service_policy().is_empty(): errors.append("Customer service response and remake patience must be valid choices")
	if order_requests.is_empty(): errors.append("Customer needs at least one order request")
	var seen: Dictionary = {}
	for request in order_requests:
		if request == null:
			errors.append("Customer has an empty request entry")
			continue
		if seen.has(request.id): errors.append("Duplicate customer request: " + String(request.id))
		seen[request.id] = true
		if OrderRequestDef.lookup(catalog, "order_requests", request.id) != request:
			errors.append("Customer request must be the shared Catalog resource: " + String(request.id))
		for error in request.validate(catalog):
			errors.append("%s: %s" % [request.id, error])
	return errors
