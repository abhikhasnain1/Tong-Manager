class_name BucketConfig
extends Resource

@export_range(1, 32, 1, "or_greater") var capacity: int = 6
# Total held time for one captured batch, independent of its cup count.
@export_range(0.1, 30.0, 0.1, "or_greater") var wash_seconds: float = 2.4
@export_range(0.01, 1.0, 0.01) var first_output_fraction: float = 0.2
@export_range(0.0, 3.0, 0.05, "or_greater") var output_travel_seconds: float = 0.35

func is_valid() -> bool:
	return (capacity > 0 and is_finite(wash_seconds) and wash_seconds > 0.0
		and is_finite(first_output_fraction) and first_output_fraction > 0.0 and first_output_fraction <= 1.0
		and is_finite(output_travel_seconds) and output_travel_seconds >= 0.0)
