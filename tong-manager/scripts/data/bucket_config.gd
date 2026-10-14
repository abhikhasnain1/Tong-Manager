class_name BucketConfig
extends Resource

@export_range(1, 32, 1, "or_greater") var capacity: int = 6
@export_range(0.1, 30.0, 0.1, "or_greater") var wash_seconds: float = 2.4

func is_valid() -> bool:
	return capacity > 0 and is_finite(wash_seconds) and wash_seconds > 0.0
