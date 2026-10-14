class_name CupReturnConfig
extends Resource
## Accepted-drink presentation and collection timing; no stock or wash-water cost.

@export_range(0.0, 120.0, 0.25, "or_greater") var drinking_seconds := 8.0
@export_range(0.0, 120.0, 0.25, "or_greater") var attention_seconds := 8.0
@export var attention_offset := Vector2(62.0, -154.0)


func safe_drinking_seconds() -> float:
	return maxf(0.0, drinking_seconds) if is_finite(drinking_seconds) else 8.0


func safe_attention_seconds() -> float:
	return maxf(0.0, attention_seconds) if is_finite(attention_seconds) else 8.0
