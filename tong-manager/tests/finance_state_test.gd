extends SceneTree
## One financial authority, with copied receipts and coordinated explicit resets.

var checks := 0
var failures: Array[String] = []
var notifications := {"transactions": 0, "changes": 0}
var reentry_ledger: FinanceState
var game_state: Node
var reset_config: Resource
var reset_observations: Array[Dictionary] = []


func _init() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func on_transaction(_record: Dictionary) -> void:
	notifications.transactions += 1


func on_changed() -> void:
	notifications.changes += 1


func verify_balances_and_identity() -> void:
	var ledger := FinanceState.new()
	ledger.transaction_recorded.connect(on_transaction)
	ledger.changed.connect(on_changed)
	notifications = {"transactions": 0, "changes": 0}
	check(not ledger.initialized and ledger.generation == 0 and ledger.transaction_log.is_empty(), "New finance is uninitialized")
	check(not ledger.record_income(&"before_start", 10) and not ledger.record_expense(&"before_start", 1), "No transactions before initialization")
	for invalid: Variant in [-1, 1.0, 1.5, "100", null, true, NAN, INF]:
		check(not ledger.can_reset(invalid) and not ledger.reset(invalid), "Invalid opening cash rejected without coercion: " + str(invalid))
	check(notifications == {"transactions": 0, "changes": 0}, "Rejected initialization is silent")
	check(ledger.reset(100) and ledger.initialized and ledger.generation == 1, "Explicit initialization creates a generation")
	check(ledger.cash_on_hand == 100 and ledger.day_income == 0 and ledger.day_expenses == 0, "Starting cash is neither income nor expense")
	check(notifications == {"transactions": 0, "changes": 1} and ledger.transaction_log.is_empty(), "Initialization changes the view without creating a transaction")
	var metadata := {"order_id": &"order_a", "quality": {"bad_review": true, "reasons": [&"cold_tea"]}}
	var aliases: Array = [&"handoff:one"]
	check(ledger.record_income(&"order:a", 20, metadata, aliases), "First accepted source commits income")
	check(ledger.cash_on_hand == 120 and ledger.day_income == 20 and ledger.day_expenses == 0, "Income changes cash and income exactly once")
	var original := ledger.get_transaction(&"order:a")
	check(original == ledger.get_transaction(&"handoff:one") and original.amount == 20 and original.kind == &"income", "Primary and handoff alias resolve the same immutable receipt")
	check(original.cash_after == 120 and original.generation == 1, "Receipt snapshots balance and generation")
	metadata.quality.reasons.append(&"altered")
	aliases.append(&"later_alias")
	check(ledger.get_transaction(&"order:a") == original and ledger.get_transaction(&"later_alias").is_empty(), "Caller mutation cannot rewrite recorded metadata or aliases")
	var before := notifications.duplicate()
	for duplicate: Array in [[&"order:a", 20, []], [&"order:a", 999, [&"unused_alias"]], [&"handoff:one", 20, []], [&"new_order", 20, [&"handoff:one"]]]:
		check(not ledger.record_income(duplicate[0], duplicate[1], {}, duplicate[2]), "Repeated or conflicting identity rejected")
	check(not ledger.record_expense(&"order:a", 1), "Income and expense share one identity namespace")
	check(notifications == before and ledger.transaction_log.size() == 1, "Duplicate/conflict attempts never publish or append")
	check(ledger.get_transaction(&"unused_alias").is_empty(), "A failed duplicate cannot claim fresh aliases")
	check(ledger.record_expense(&"purchase:a", 30, {"note": "supplies"}, [&"receipt:a"]), "Expense foundation commits an affordable purchase")
	check(ledger.cash_on_hand == 90 and ledger.day_income == 20 and ledger.day_expenses == 30, "Expense changes only cash and expense totals")
	check(not ledger.record_expense(&"overdraft", 91) and ledger.cash_on_hand == 90, "Expense cannot create debt")
	check(ledger.record_expense(&"remaining_cash", 90) and ledger.cash_on_hand == 0, "Expense may spend exactly remaining cash")
	check(not ledger.record_expense(&"empty_wallet", 1), "Zero balance cannot be overdrawn")
	check(ledger.get_transaction(&"missing").is_empty() and ledger.get_transaction(null).is_empty(), "Unknown/invalid receipt lookup is empty")
	var copied := ledger.transaction_log
	copied[0].metadata.quality.reasons.clear()
	copied[0].amount = 1000
	copied.clear()
	var snapshot := ledger.get_snapshot()
	snapshot.transaction_log[0].aliases.clear()
	snapshot.cash_on_hand = 999
	check(ledger.get_transaction(&"order:a") == original and ledger.get_transaction(&"handoff:one") == original, "All nested getter containers are independent copies")
	ledger.cash_on_hand = 999
	ledger.day_income = 999
	ledger.day_expenses = 999
	ledger.generation = 999
	ledger.initialized = false
	ledger.transaction_log = []
	check(ledger.cash_on_hand == 0 and ledger.day_income == 20 and ledger.day_expenses == 120 and ledger.generation == 1 and ledger.initialized and ledger.transaction_log.size() == 3,
		"Public property assignments cannot bypass ledger authority")
	ledger.transaction_recorded.disconnect(on_transaction)
	ledger.changed.disconnect(on_changed)


func verify_invalid_records() -> void:
	var ledger := FinanceState.new()
	ledger.reset(100)
	var before := ledger.get_snapshot()
	for value: Variant in [0, -1, 1.0, 1.5, true, null, "10", NAN, INF]:
		check(not ledger.record_income(&"invalid_amount", value) and not ledger.record_expense(&"invalid_amount", value), "Money must be a positive integer without coercion: " + str(value))
	for value: Variant in ["", " ", " leading", "trailing ", 12, true, null]:
		check(not ledger.record_income(value, 1), "Stable source identity required: " + str(value))
	for aliases: Array in [[&""], [&"income"], [&"alias", &"alias"], [12], [" alias"]]:
		check(not ledger.record_income(&"income", 1, {}, aliases), "Aliases require distinct valid identities")
	var resource := Resource.new()
	var node := Node.new()
	for invalid: Variant in [resource, node, Callable(self, "run"), NAN, INF, Vector2.ONE]:
		check(not ledger.record_income(&"bad_metadata", 1, {"nested": [invalid]}), "Live or nonfinite metadata rejected")
	check(not ledger.record_income(&"bad_key", 1, {12: "invalid"}), "Receipt metadata keys are textual")
	var cycle: Array = []
	cycle.append(cycle)
	check(not ledger.record_income(&"cycle", 1, {"value": cycle}), "Cyclic metadata cannot enter immutable history")
	cycle.clear()
	node.free()
	check(ledger.get_snapshot() == before, "All invalid records leave every ledger field untouched")
	check(ledger.record_income(&"finite_metadata", 1, {"nested": [null, true, 12, 0.5, &"ready"], "empty": {}}), "Finite primitive nested receipt metadata supported")


func verify_overflow() -> void:
	var ledger := FinanceState.new()
	check(ledger.reset(FinanceState.MAX_MONEY), "Maximum integer starting cash remains exact")
	check(not ledger.record_income(&"cash_overflow", 1), "Cash overflow rejected before arithmetic")
	check(ledger.record_expense(&"all_cash", FinanceState.MAX_MONEY), "Maximum affordable expense remains exact")
	check(ledger.record_income(&"all_income", FinanceState.MAX_MONEY), "Maximum income remains exact")
	var before := ledger.get_snapshot()
	check(not ledger.record_expense(&"expense_total_overflow", 1), "Expense-total overflow rejected despite sufficient cash")
	check(ledger.get_snapshot() == before, "Overflow failure cannot wrap or append")
	check(ledger.reset(0), "Explicit fresh ledger resets previous totals")
	check(ledger.record_income(&"maximum_income", FinanceState.MAX_MONEY) and ledger.record_expense(&"release_cash", 1), "Income total may reach maximum independently of cash")
	check(not ledger.record_income(&"income_total_overflow", 1), "Income-total overflow rejected despite cash headroom")
	check(ledger.cash_on_hand == FinanceState.MAX_MONEY - 1 and ledger.day_income == FinanceState.MAX_MONEY, "Overflow guard preserves exact integer values")


func observe_transaction(record: Dictionary) -> void:
	notifications.transactions += 1
	check(reentry_ledger.is_committing() and reentry_ledger.cash_on_hand == 15 and reentry_ledger.day_income == 5, "Transaction callback sees committed totals under guard")
	check(reentry_ledger.get_transaction(&"handoff:guarded") == record and reentry_ledger.transaction_log.size() == 1, "Transaction callback sees committed aliases and history")
	check(not reentry_ledger.reset(999) and not reentry_ledger.begin_reset(999), "Notification cannot erase its own accepted transaction")
	check(not reentry_ledger.record_income(&"another", 1) and not reentry_ledger.record_expense(&"another", 1), "Notification cannot interleave another transaction")
	check(not reentry_ledger.finish_reset(), "A transaction notification cannot finish a nonexistent reset")
	record.metadata.nested.append(&"tampered")
	record.amount = 999


func observe_guarded_change() -> void:
	notifications.changes += 1
	check(reentry_ledger.is_committing(), "Changed notification is guarded until all observers finish")
	check(not reentry_ledger.reset(999) and not reentry_ledger.record_income(&"nested_change", 1), "Changed notification cannot recursively reset or add money")


func verify_notification_reentry() -> void:
	reentry_ledger = FinanceState.new()
	reentry_ledger.reset(10)
	notifications = {"transactions": 0, "changes": 0}
	reentry_ledger.transaction_recorded.connect(observe_transaction)
	reentry_ledger.changed.connect(observe_guarded_change)
	check(reentry_ledger.record_income(&"order:guarded", 5, {"nested": [&"original"]}, [&"handoff:guarded"]), "Guarded transaction commits once")
	check(notifications == {"transactions": 1, "changes": 1} and not reentry_ledger.is_committing(), "One coherent pair of notifications, then guard releases")
	check(reentry_ledger.get_transaction(&"order:guarded").metadata.nested == [&"original"], "Signal payload mutation cannot rewrite authoritative metadata")
	reentry_ledger.transaction_recorded.disconnect(observe_transaction)
	var generation := reentry_ledger.generation
	check(reentry_ledger.reset(7), "Reset publishes through the same guard")
	check(reentry_ledger.generation == generation + 1 and reentry_ledger.transaction_log.is_empty() and reentry_ledger.cash_on_hand == 7, "Reset creates a fresh generation without old income/history")
	check(notifications == {"transactions": 1, "changes": 2}, "Reset never publishes a payment transaction")
	reentry_ledger.changed.disconnect(observe_guarded_change)
	var reset_owner := RefCounted.new()
	check(not reentry_ledger.begin_reset(8), "Coordinated reset requires a retained completion capability")
	check(reentry_ledger.begin_reset(8, reset_owner) and reentry_ledger.is_committing(), "Coordinated reset may stage balances without notifying")
	check(not reentry_ledger.record_income(&"during_reset", 1) and not reentry_ledger.reset(9), "Staged reset remains protected across other authority notifications")
	check(not reentry_ledger.finish_reset() and not reentry_ledger.finish_reset(RefCounted.new()) and reentry_ledger.is_committing(), "Unrelated callbacks cannot release a pending reset guard")
	check(reentry_ledger.finish_reset(reset_owner, false) and not reentry_ledger.finish_reset(reset_owner), "Staged reset finishes only once with its original capability")
	check(reentry_ledger.record_income(&"order:guarded", 5, {}, [&"handoff:guarded"]), "A deliberate new generation permits a new run's reused identities")
	check(reentry_ledger.get_transaction(&"order:guarded").generation == reentry_ledger.generation, "Reused identity belongs to current generation only")
	reentry_ledger = null


func observe_reset(_value: Variant = null) -> void:
	reset_observations.append({"cash": game_state.finance.cash_on_hand, "income": game_state.finance.day_income,
		"expenses": game_state.finance.day_expenses, "generation": game_state.finance.generation,
		"history": game_state.finance.transaction_log.size(), "sugar": game_state.inventory.remaining(&"sugar"),
		"water": game_state.water_supply.remaining_ml,
		"nested_reset": game_state.reset_demo_state(reset_config),
		"direct_reset": game_state.finance.reset(999),
		"premature_finish": game_state.finance.finish_reset(),
		"foreign_finish": game_state.finance.finish_reset(RefCounted.new()),
		"payment": game_state.finance.record_income(&"during_demo_reset", 1)})


func observe_game_transaction(_record: Dictionary) -> void:
	var before_inventory: Dictionary = game_state.inventory.quantities
	var before_water: float = game_state.water_supply.remaining_ml
	check(not game_state.reset_demo_state(reset_config), "Payment notification cannot trigger a partial demo reset")
	check(game_state.inventory.quantities == before_inventory and game_state.water_supply.remaining_ml == before_water, "Rejected reset leaves both supply authorities untouched")


func verify_game_state() -> void:
	game_state = root.get_node("GameState")
	var config: Resource = load("res://data/balance/demo_day_1.tres").duplicate(true)
	config.starting_cash = 37
	config.starting_inventory = {&"sugar": 3, &"black_tea": 2}
	config.daily_water_ml = 700.0
	check(game_state.ensure_finance(config), "First finance initialization uses actual DayConfig")
	var ledger: FinanceState = game_state.finance
	check(ledger.cash_on_hand == 37 and ledger.generation == 1, "Custom opening cash wins over demo default")
	check(ledger.record_income(&"preserved_order", 20, {}, [&"preserved_handoff"]), "Run earns real income")
	var other: Resource = config.duplicate(true)
	other.starting_cash = 999
	check(game_state.ensure_finance(other) and game_state.finance == ledger and ledger.cash_on_hand == 57 and ledger.generation == 1, "Repeated ensure never resets or replaces finance")
	check(game_state.ensure_inventory(config), "Run initializes independent portion authority")
	game_state.ensure_water_day(config)
	reset_config = config
	ledger.transaction_recorded.connect(observe_game_transaction)
	check(ledger.record_income(&"guarded_game_order", 1), "Payment succeeds after refusing recursive whole-run reset")
	ledger.transaction_recorded.disconnect(observe_game_transaction)
	var before := ledger.get_snapshot()
	var scene := load("res://scenes/gameplay/tong/TongDayScreen.tscn") as PackedScene
	for index in range(2):
		var screen := scene.instantiate()
		screen.customer_queue_enabled = false
		root.add_child(screen)
		await process_frame
		screen.queue_free()
		await process_frame
		check(game_state.finance == ledger and ledger.get_snapshot() == before, "Screen recreation retains the same cash and complete transaction history")
	var invalid: Resource = config.duplicate(true)
	invalid.starting_cash = -1
	var supply_before: Dictionary = game_state.inventory.quantities
	var day_before: int = game_state.water_supply.day_id
	check(not game_state.reset_demo_state(invalid), "Invalid starting cash rejects the entire coordinated reset")
	check(ledger.get_snapshot() == before and game_state.inventory.quantities == supply_before and game_state.water_supply.day_id == day_before, "Invalid finance cannot reset supplies or advance the day")
	config.starting_cash = 60
	config.starting_inventory = {&"sugar": 2, &"black_tea": 1}
	config.daily_water_ml = 900.0
	reset_observations.clear()
	game_state.inventory.changed.connect(observe_reset)
	game_state.water_supply.remaining_changed.connect(observe_reset)
	ledger.changed.connect(observe_reset)
	check(game_state.reset_demo_state(config), "Explicit demo reset stages all three authorities")
	game_state.inventory.changed.disconnect(observe_reset)
	game_state.water_supply.remaining_changed.disconnect(observe_reset)
	ledger.changed.disconnect(observe_reset)
	check(reset_observations.size() == 3, "Each authority publishes one reset notification")
	for observed in reset_observations:
		check(observed.cash == 60 and observed.income == 0 and observed.expenses == 0 and observed.history == 0 and observed.generation == 2
			and observed.sugar == 2 and observed.water == 900.0 and not observed.nested_reset and not observed.direct_reset
			and not observed.premature_finish and not observed.foreign_finish and not observed.payment,
			"Every observer sees coherent reset balances/history and cannot reenter reset/payment")
	check(game_state.finance == ledger and game_state.water_supply.day_id == day_before + 1 and not ledger.is_committing(), "Reset preserves identities and releases guard after notifications")
	check(ledger.get_transaction(&"preserved_order").is_empty() and ledger.generation == 2, "Old queued generation is distinguishable from the new run")


func run() -> void:
	verify_balances_and_identity()
	verify_invalid_records()
	verify_overflow()
	verify_notification_reentry()
	await verify_game_state()
	print("FINANCE_STATE: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
