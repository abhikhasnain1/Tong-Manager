# Table placement and brewing verification

The current table placement review is in `scenes/development/BrewingPreview.tscn`.
Open it and press F6. Press **G** for Organize, then drag the tray or a tea, sugar
or milk container to a clear part of the tabletop. The base outline is green for
a valid position and red for a blocked position. Release commits the exact
position; an invalid release, Escape, right-click, mode change, focus loss or
window resize returns the item. No rotation or automatic pushing is included.

Only the stove blocks ordinary table placement. Other objects reserve their base
footprints. The strip behind the stove is usable wherever a base fits. Drops must
also keep the base inside the visible window. The water/discard controls remain
accessible above placeable art and do not reserve table space. Two existing sugar
can pictures are separate texture regions with independent placement; neither
creates ingredient stock or implements taking a portion.

The populated tray carries its cups unchanged. **This is the table-only slice:**
the internal cup grid and its existing brewing/service lifecycle remain until
free tray contents and bidirectional table transfers are implemented in #103.
Press G again for Interact to use the brewing actions described below. All scene
icons, boxes and controls remain provisional. Bucket work is on hold.

```sh
godot --headless --path . --script res://tests/placement_geometry_test.gd
godot --headless --path . --script res://tests/table_placement_test.gd
godot --path . --resolution 1920x1080 --script res://tests/table_placement_input_test.gd
```

The geometry suite checks concave boundaries/exclusions, compound footprints,
exact edge contact, peer overlap, transformed geometry and stale identity safety.
The table suites check continuous scene placement, rollback and actual input
alongside moved-tray brewing and utility access. Run rendered checks at all four
sizes listed below. Tests do not replace scene/play-feel acceptance before merge.

Run from the `tong-manager` project directory with Godot 4.7 on PATH:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/brewing_contract_test.gd
godot --headless --path . --script res://tests/brewing_thermal_test.gd
godot --headless --path . --script res://tests/discard_interaction_test.gd
godot --headless --path . --script res://tests/brewing_service_review_test.gd
godot --headless --path . --script res://tests/water_supply_test.gd
godot --path . --resolution 1920x1080 --script res://tests/brewing_input_test.gd
```

The contract suite checks conserved volume, capacity, brewing states, independent
burners, drag cancellation and disappearing targets. The thermal/discard suites
cover off-stove progression, thermal mixing/cooling,
elapsed-time subdivision, disposal in every kettle state, lifecycle preservation,
and deliberate drop/cancel behavior. The service review suite
checks warm/cold sample outcomes, independent recipe/volume/cleanliness rules,
temperature evaluated at acceptance, and one review per accepted order. The water
suite checks finite daily supply, conservative transfers, valid kettle states,
scene reload conservation and deliberate new-day reset. The input
suite requires a window and sends viewport mouse events through physics picking
and actual Space key events through input handling. It checks grip anchoring,
spout targeting, stable held pose, burner seating and fixture-button focus safety.
These scripts exit after verification. Run rendered input checks at 1920×1080,
1600×900, 1366×768 and 1280×800 for the supported review sizes.

To try the loop, open `scenes/development/BrewingPreview.tscn` in Godot and press
F6, or run:

```sh
godot --path . res://scenes/development/BrewingPreview.tscn
```

The preview and normal scene start with an empty kettle. Drag the water-drum icon
onto the kettle; its readout shows the finite daily supply. Click the left dial to
cycle Off, Low, Medium, High. When water boils, click **Add tea · fixture**, then
wait for Tea ready. Tea keeps steeping off the stove and while held. Drag the
kettle by its grip so the spout aims above a cup, hold Space to pour, and release
Space to stop. The hand cursor stays on the kettle, clear of the cup. Releasing
the mouse normally returns the kettle; releasing over a burner seats it there.
Escape or right-click cancels. G toggles the existing interaction mode.

Drag a kettle or cup to **Discard** to empty its contents at any point. This keeps
the vessel and does not wash dirty cups or refund water/ingredients. Refill from
the same finite drum. Only **Reset preview · new day** restarts this development
sample with a fresh day allocation, empty kettle and clean cups.

The upper-right **SAMPLE CUSTOMER** is a preview-only black-tea order requiring
at least 150 ml and no garnishes. Drag a filled cup there: warm tea produces a
happy sample; cold tea is accepted but produces an unhappy sample and the readable
bad review “My tea was cold.” The temperature at actual handoff decides the result,
including tea that cooled after pouring. The cup returns to its tray position
marked served. **Next sample customer** creates another sample order without
refilling supplies or cleaning cups. Repeated or rejected handoffs add no review.

The current review defaults use a 45°C cold threshold, 2°C/s cup cooling and a
90-second ready-to-oversteep interval so cooling can be explored. These values,
review wording and the 150 ml sample are provisional tuning, not final recipe or
customer balancing. Discard or reset an oversteeped batch; degraded-tea eligibility
is still a separate design decision.

Tea stock and sample customers are explicit development fixtures. This scene does
not implement production ingredient inventory, customer orders, payments, a day
ledger or a reputation economy. Preview controls are disabled during any drag or
active action, and never take keyboard focus from Space-to-pour. Bucket work stays
separate. Brewing mechanics were accepted in PR #106; artwork and presentation
remain provisional. The new placement slice needs its own scene review before merge.
