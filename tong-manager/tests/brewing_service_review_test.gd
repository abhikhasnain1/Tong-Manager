extends SceneTree

const Review := preload("res://scripts/gameplay/brewing_service_review.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func cup_at(temperature: float) -> Dictionary:
	return {
		"available": true, "clean": true, "recipe_id": &"black_tea",
		"garnish_count": 0, "volume_ml": 150.0,
		"temperature": temperature, "cold_threshold": 45.0,
	}

func run() -> void:
	var review := Review.new()
	var cup := cup_at(80.0)
	var warm := review.accept(&"warm_order", cup)
	check(bool(warm.accepted) and bool(warm.fulfilled), "Matching warm tea fulfills an ordinary order")
	check(not bool(warm.cold) and not bool(warm.unhappy) and not bool(warm.bad_review), "Warm sample has no cold-service penalty")
	check(review.accepted_count() == 1 and review.bad_review_count() == 0, "Warm service recorded once")
	var cold := review.accept(&"cold_order", cup_at(25.0))
	check(bool(cold.accepted) and bool(cold.fulfilled), "Cold tea fulfills an otherwise-valid ordinary order")
	check(bool(cold.unhappy) and bool(cold.bad_review) and cold.reason == &"cold_tea", "Accepted cold tea records unhappy customer and bad review")
	check(review.accepted_count() == 2 and review.bad_review_count() == 1, "Cold service still counts as served")
	check(not bool(review.accept(&"cold_order", cup_at(25)).accepted), "Duplicate callback cannot accept an order twice")
	check(review.accepted_count() == 2 and review.bad_review_count() == 1, "Duplicate callback cannot add another review")
	var copy := review.accepted_result(&"cold_order")
	copy.bad_review = false
	check(review.bad_review_count() == 1, "Presentation cannot mutate the stored service outcome")
	var exact_threshold := review.inspect(&"threshold_order", cup_at(45.0))
	check(bool(exact_threshold.accepted) and bool(exact_threshold.cold), "Configured cold boundary is inclusive and does not reject service")
	var cooler_threshold := cup_at(45.0)
	cooler_threshold.cold_threshold = 40.0
	check(not bool(review.inspect(&"tuned_order", cooler_threshold).cold), "Cold boundary is supplied tuning, not hardcoded in the evaluator")
	var cooling_cup := cup_at(80.0)
	check(not bool(review.inspect(&"cooling_order", cooling_cup).cold), "Hover sees currently warm tea")
	check(review.accepted_count() == 2, "Hover evaluation does not fulfill an order")
	cooling_cup.temperature = 30.0
	var cooled := review.accept(&"cooling_order", cooling_cup)
	check(bool(cooled.cold) and bool(cooled.bad_review), "Service evaluates the new temperature at handoff, not the earlier hover")
	cooling_cup.temperature = 80.0
	check(bool(review.accepted_result(&"cooling_order").cold), "Later cup changes do not rewrite historical review")
	var accepted_before := review.accepted_count()
	var reviews_before := review.bad_review_count()
	var rejected_cases: Array[Dictionary] = [
		{"field": "recipe_id", "value": &"water", "reason": &"wrong_recipe"},
		{"field": "garnish_count", "value": 1, "reason": &"wrong_recipe"},
		{"field": "volume_ml", "value": 149.0, "reason": &"too_little_tea"},
		{"field": "clean", "value": false, "reason": &"dirty_cup"},
		{"field": "available", "value": false, "reason": &"cup_unavailable"},
		{"field": "volume_ml", "value": NAN, "reason": &"invalid_volume"},
		{"field": "temperature", "value": NAN, "reason": &"invalid_temperature"},
		{"field": "cold_threshold", "value": INF, "reason": &"invalid_temperature"},
	]
	for index in rejected_cases.size():
		var invalid := cup_at(25.0)
		var case: Dictionary = rejected_cases[index]
		invalid[case.field] = case.value
		var rejected := review.accept(StringName("rejected_%d" % index), invalid)
		check(not bool(rejected.accepted) and rejected.reason == case.reason, "Independent validation rejects %s without treating cold as the reason" % case.field)
	check(review.accepted_count() == accepted_before and review.bad_review_count() == reviews_before, "Rejected attempts do not create served orders or reviews")
	check(not bool(review.accept(&"", cup_at(25)).accepted), "Missing order identity cannot create a review")
	check(not bool(review.accept(&"invalid_order", cup_at(25), 0.0).accepted), "Invalid order volume cannot be fulfilled")
	check(not warm.has("payment") and not cold.has("payment") and not cold.has("reputation"), "Outcome does not invent finance or reputation mutations")
	if failures.is_empty():
		print("PASS: %d brewing service review checks" % checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d brewing service review checks" % [failures.size(), checks])
		quit(1)
