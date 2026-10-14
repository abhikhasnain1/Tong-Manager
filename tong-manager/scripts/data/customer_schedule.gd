class_name CustomerSchedule
extends Resource
## Compiles authored resources into a detached, seeded plan for one queue run.

enum Mode { GENERATED, AUTHORED }

@export var id: StringName
@export var mode: Mode = Mode.GENERATED
@export_range(1, 20, 1, "or_greater") var max_active := 2
@export_range(0.0, 3600.0, 0.1, "or_greater") var first_delay_seconds := 3.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var gap_seconds := 15.0
@export_range(0.0, 10.0, 0.1, "or_greater") var timeout_reaction_seconds := 0.8
@export var customer_pool: Array[CustomerDef] = []
@export var arrivals: Array[CustomerArrivalDef] = []


func validate(day: Resource, catalog: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if not OrderRequestDef.valid_identity(id): errors.append("Schedule needs a stable ID")
	if mode not in [Mode.GENERATED, Mode.AUTHORED]: errors.append("Unknown schedule mode")
	if max_active <= 0: errors.append("Capacity must be positive")
	if not _nonnegative(timeout_reaction_seconds): errors.append("Timeout reaction must be finite and nonnegative")
	if not is_instance_valid(catalog):
		errors.append("A live Catalog is required")
		return errors
	if day == null: errors.append("A DayConfig is required")
	if mode == Mode.GENERATED:
		if not _nonnegative(first_delay_seconds) or not _nonnegative(gap_seconds): errors.append("Arrival timing must be finite and nonnegative")
		if day != null:
			var minimum: Variant = day.get("customer_count_min")
			var maximum: Variant = day.get("customer_count_max")
			if typeof(minimum) != TYPE_INT or typeof(maximum) != TYPE_INT or minimum < 0 or maximum < minimum:
				errors.append("Generated customer count range is invalid")
			elif not is_finite(first_delay_seconds + float(maxi(0, maximum - 1)) * gap_seconds):
				errors.append("Generated arrival times overflow")
		if customer_pool.is_empty(): errors.append("Generated schedule needs a customer pool")
		var seen: Dictionary = {}
		for profile in customer_pool:
			errors.append_array(_profile_errors(profile, catalog))
			if profile == null: continue
			if seen.has(profile.id): errors.append("Duplicate generated customer: " + String(profile.id))
			seen[profile.id] = true
	elif mode == Mode.AUTHORED:
		var seen: Dictionary = {}
		var previous := 0.0
		for entry in arrivals:
			if entry == null:
				errors.append("Authored arrival cannot be empty")
				continue
			if not OrderRequestDef.valid_identity(entry.id) or seen.has(entry.id): errors.append("Authored arrival IDs must be nonblank and unique")
			seen[entry.id] = true
			if not _nonnegative(entry.due_seconds) or entry.due_seconds < previous: errors.append("Authored arrival times must be finite, nonnegative and chronological")
			previous = entry.due_seconds
			if not _nonnegative(entry.patience_override): errors.append("Patience override must be finite and nonnegative")
			if entry.unhappy_response_override not in [-1, 0, 1, 2]: errors.append("Unknown authored unhappy-response override")
			if entry.remake_patience_override not in [-1, 0, 1]: errors.append("Unknown authored remake-patience override")
			errors.append_array(_profile_errors(entry.customer, catalog))
			if entry.request != null:
				if entry.customer == null or entry.customer.get_request(entry.request.id) != entry.request:
					errors.append("Authored request must belong to this customer's shared request pool")
	return errors


func compile(day: Resource, catalog: Node, seed_value: int, run_id: StringName) -> Dictionary:
	var errors := validate(day, catalog)
	if not OrderRequestDef.valid_identity(run_id): errors.append("Run needs a stable ID")
	if not errors.is_empty(): return {"ok": false, "errors": errors, "entries": []}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var count: int = arrivals.size() if mode == Mode.AUTHORED else random.randi_range(day.customer_count_min, day.customer_count_max)
	var entries: Array[Dictionary] = []
	for index in count:
		var authored: CustomerArrivalDef = arrivals[index] if mode == Mode.AUTHORED else null
		var profile: CustomerDef = authored.customer if authored != null else customer_pool[random.randi_range(0, customer_pool.size() - 1)]
		var request: OrderRequestDef = authored.request if authored != null else null
		if request == null: request = profile.order_requests[random.randi_range(0, profile.order_requests.size() - 1)]
		var entry_id := authored.id if authored != null else StringName("generated_%03d" % (index + 1))
		var visit_id := StringName("%s/%s" % [run_id, entry_id])
		var response: int = authored.unhappy_response_override if authored != null and authored.unhappy_response_override >= 0 else profile.unhappy_response
		var patience: int = authored.remake_patience_override if authored != null and authored.remake_patience_override >= 0 else profile.remake_patience
		entries.append({
			"entry_id": entry_id, "visit_id": visit_id, "order_id": StringName(String(visit_id) + "/order"),
			"customer_id": profile.id, "request_id": request.id,
			"due_seconds": authored.due_seconds if authored != null else first_delay_seconds + float(index) * gap_seconds,
			"patience_seconds": authored.patience_override if authored != null and authored.patience_override > 0.0 else profile.patience_seconds,
			"service_policy": CustomerDef.service_policy(response, patience),
			"profile": {"id": profile.id, "display_name_key": profile.display_name_key,
				"sprite_texture": profile.sprite_texture, "patience_seconds": profile.patience_seconds,
				"dialogue_profile": profile.dialogue_profile, "unhappy_response": profile.unhappy_response,
				"remake_patience": profile.remake_patience},
			"request": request.snapshot(catalog).duplicate(true),
		})
	return {"ok": true, "errors": errors, "entries": entries, "max_active": max_active,
		"id": id, "mode": mode, "total": count, "timeout_reaction_seconds": timeout_reaction_seconds}


static func _nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0


static func _profile_errors(profile: CustomerDef, catalog: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if profile == null:
		errors.append("Arrival needs a customer")
		return errors
	if OrderRequestDef.lookup(catalog, "customers", profile.id) != profile:
		errors.append("Customer must be the shared Catalog resource: " + String(profile.id))
	if profile.sprite_texture == null: errors.append("Customer needs visible front artwork")
	for error in profile.validate(catalog): errors.append("%s: %s" % [profile.id, error])
	return errors
