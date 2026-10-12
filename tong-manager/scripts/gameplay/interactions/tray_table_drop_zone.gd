class_name TrayTableDropZone
extends DropZone

# Historical scene compatibility only. TablePlaceable owns the production path.
func is_relevant_to(_payload: HeldItemPayload) -> bool:
	return false

func accepts(_payload: HeldItemPayload) -> DropValidation:
	return DropValidation.invalid("placement.legacy_zone_retired")
