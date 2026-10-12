class_name TrayInternalDropZone
extends DropZone

# Retired compatibility type. Production tray placement uses PlacementSurface
# and the item's TablePlaceable in Organize mode, with no cell snapping.
func accepts(_payload: HeldItemPayload) -> DropValidation:
	return DropValidation.invalid("tray.legacy_grid_disabled")
