# Hanging sources, portions, placement and brewing verification

## Production inventory contract

Run `godot --headless --path . --script res://tests/inventory_state_test.gd` from
the project directory after the editor import. The suite checks resource-driven
integer stock, defensive snapshots, unit validation, reservation availability,
safe mutations, overflow, exact-once commit, rollback and synchronous callbacks.
Physical and future Khata contract adapters use the same authority; the test
also injects it into existing physical sources to verify cancellation, removal,
scene recreation and no refund on disposal. Explicit demo reset is tested with
the separate measured-water authority, including invalid and reentrant resets.

These are stock and adapter checks. They do not complete the Khata shell/export,
final recipe destinations or doses, customer handoff, payments or persistence.
The existing ingredient targets remain provisional review behavior, and
`BrewingPreview.tscn` keeps its separate finite development stock fixture.

For the visible inventory review, open
`scenes/development/InventoryPreview.tscn` and press **F6**. This scene injects
the real `GameState.inventory` into the accepted physical portions and displays
shared on-hand/available counts. Its kettle/cup destinations and sample handoffs
still use provisional review targets; they are not the completed #59/#66 commands.
**Reload** recreates the scene and vessels while preserving current stock and
water. **Reset · new day** deliberately replenishes both from `DayConfig` and
invalidates old portions. Neither operation implements persistence or day scheduling.

Run `godot --headless --path . --script res://tests/inventory_preview_test.gd`
for the real review scene's stock, cancellation, modal, removal and reload checks.
Run the same script without `--headless` at the four review sizes below; an
optional PNG path after `--` captures the initial stock panel and scene.

## Brewing interaction fixture

The isolated interaction fixture is in `scenes/development/BrewingPreview.tscn`.
Open it and press F6. The scene starts in **Neutral**, with passive hover but no
extraction, rearrangement or tool actions. Select the top **Organize** button (or
press **G**), then drag the tray, a cup or a tea,
sugar or milk container to a clear part of the tabletop. The base outline is green for
a valid position and red for a blocked position. Release commits the exact
position; an invalid release, Escape, right-click, mode change, focus loss or
window resize returns the item. No rotation or automatic pushing is included.

Only the stove blocks ordinary table placement. Other objects reserve their base
footprints. The strip behind the stove is usable wherever a base fits. Drops must
also keep the base inside the visible window. The water/discard controls remain
accessible above placeable art and do not reserve table space. Two existing sugar
can pictures have independent placement and share one sugar stock balance.

Cups and ingredient containers can also move freely onto and off the tray. Their
complete bases must fit inside its usable interior; a base crossing the rim is
invalid. Exact edge contact is allowed. The populated tray carries its contents
with their arrangement, size and state unchanged, while table-owned items stay
still. The starting six cups are an owned supply, not a six-slot placement limit.
Select **Use** (or press **U**) to brew, take a portion, serve or discard. Releasing
a cup in Use does not rearrange it. Clicking the selected mode again, or pressing
its shortcut again, returns to Neutral. Switching mode cancels the current gesture.
These defaults and the working labels remain adjustable after scene review.
All scene icons, boxes and controls remain provisional.
Bucket work is on hold.

Brush the hanging banana bunches or biscuit bag to nudge them in **any mode**.
The two banana bunches have independent fixed pins and share one banana stock.
The bag hangs from its loop. Motion follows the pointer, is limited and damped,
and settles when left alone. Organize keeps these sources attached.
In **Use**, click and drag a separate banana or biscuit piece to the labelled
**PREVIEW HANDOFF** in the middle. Release there to consume exactly one piece;
release elsewhere, Escape or right-click returns it. Holding a piece suppresses
new brush impulses, while existing sway continues. UI/modal coverage blocks new
brushing and extraction. The source pictures remain present even when empty;
the stock readout and hover hint identify depletion. All of this art is provisional.

In Use, the tea box yields **one teabag**; sugar and condensed milk yield **one
spoonful**. The source remains where it was placed, including on a moved tray.
Release over a highlighted vessel to apply the portion. The review fixture accepts
a teabag in a kettle of boiling water without existing tea, and sugar/milk in a cup
containing black tea. An invalid or cancelled attempt consumes nothing. The nearest
invalid vessel is shown as invalid instead of redirecting to a valid neighbour.

`BrewingPreview` injects its own finite test stock: 6 teabags, 12 sugar spoonfuls and 12
milk spoonfuls, 6 bananas and 8 biscuits. Reservations temporarily reduce the available count; cancellation
returns them and successful application consumes once. The normal scene has the
same source/target interfaces but no portion provider yet. This does not complete
shared production inventory or recipes. Milk currently adds an abstract garnish,
without changing liquid volume/temperature; the existing three-garnish limit is a
review fixture rule. Exact doses, other destinations and recipe rules remain open.
Ground-tea/coffee jars are not included.

```sh
godot --headless --path . --script res://tests/placement_geometry_test.gd
godot --headless --path . --script res://tests/table_placement_test.gd
godot --headless --path . --script res://tests/tray_transfer_test.gd
godot --headless --path . --script res://tests/ingredient_portion_test.gd
godot --headless --path . --script res://tests/ready_portion_test.gd
godot --headless --path . --script res://tests/hanging_source_physics_test.gd
godot --headless --path . --script res://tests/controller_ui_coverage_test.gd
godot --path . --resolution 1920x1080 --script res://tests/table_placement_input_test.gd
godot --path . --resolution 1920x1080 --script res://tests/tray_transfer_input_test.gd
godot --path . --resolution 1920x1080 --script res://tests/interaction_intent_input_test.gd
godot --path . --resolution 1920x1080 --script res://tests/hanging_source_input_test.gd
```

The geometry suite checks concave boundaries/exclusions, compound footprints,
exact edge contact, peer overlap, transformed geometry, stale identity safety and
cleanup when a drag's original owner is detached or destroyed.
The table suites check continuous scene placement, rollback and actual input
alongside moved-tray brewing and utility access. The transfer suites cover cups
and all whole ingredient sources in both directions, preserved size and contents,
mixed populated trays, rim/occupied drops, cancellation, removed objects, dynamic
cup setup, action-only Use releases, pouring, disposal and sample service
after relocation. Overlapping filled cups verify separate bases, inherited liquid
depth and real front-object picking in both placement orders. The rendered
transfer script accepts optional initial, mixed-tray and overlapping-cup PNG paths
after `--` for visual review. Run rendered checks at all four
sizes listed below. Tests do not replace scene/play-feel acceptance before merge.

The portion contract suite checks shared stock, reservations, exact-once commit,
synchronous callback reentry, lifecycle cancellation and development/normal scene
separation. The intent input suite tests real top-control clicks, G/U, stationary
hover updates, source extraction, targets, UI/modal coverage and moved sources.
It accepts initial, held-portion and final PNG paths after `--`. Intent input tests
align the window mouse with injected events; run rendered suites one at a time.
Modal input blocking cancels gestures without deciding future simulation pause policy.

The hanging suites check real fixed joints, independent bounded/damped sway,
direction and speed, stationary-pointer rest, viewport transforms, UI/modal
occlusion, Use extraction from moving art, shared banana stock, finite depletion,
cancellation and lifecycle cleanup. The rendered hanging suite accepts initial,
held-piece and handoff PNG paths after `--`. Its preview handoff only records test
counts: it does not implement customer eligibility, orders, money or production stock.
The UI coverage suite checks transformed and clipped controls, input filters and
canvas layers so a fast sweep cannot nudge a source hidden behind a panel.

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

The preview and normal scene start with an empty kettle. Select **Use**, then drag the water-drum icon
onto the kettle; its readout shows the finite daily supply. Click the left dial to
cycle Off, Low, Medium, High. When water boils, drag one teabag from the tea box
onto the kettle's highlighted mouth, then
wait for Tea ready. Tea keeps steeping off the stove and while held. Drag the
kettle by its grip so the spout aims above a cup, hold Space to pour, and release
Space to stop. The hand cursor stays on the kettle, clear of the cup. Releasing
the mouse normally returns the kettle; releasing over a burner seats it there.
Escape or right-click cancels. Try dragging one milk or sugar spoonful onto a tea
cup; the top hint reports the result. To try the plain-black-tea sample order,
use a cup without these garnishes.

Drag a kettle or cup to **Discard** to empty its contents at any point. This keeps
the vessel and does not wash dirty cups or refund water/ingredients. Refill from
the same finite drum. Only **Reset · new day** restarts this development
sample with a fresh day allocation, finite ingredient stock, empty kettle and clean
cups. Reset returns to Neutral and preserves arranged positions.

The upper-right **SAMPLE CUSTOMER** is a preview-only black-tea order requiring
at least 150 ml and no garnishes. Drag a filled cup there: warm tea produces a
happy sample; cold tea is accepted but produces an unhappy sample and the readable
bad review “My tea was cold.” The temperature at actual handoff decides the result,
including tea that cooled after pouring. The cup returns to its previous surface and position
marked served. **Next sample** creates another sample order without
refilling supplies or cleaning cups. Repeated or rejected handoffs add no review.

The current review defaults use a 45°C cold threshold, 2°C/s cup cooling and a
90-second ready-to-oversteep interval so cooling can be explored. These values,
review wording and the 150 ml sample are provisional tuning, not final recipe or
customer balancing. Discard or reset an oversteeped batch; degraded-tea eligibility
is still a separate design decision.

Ingredient stock and sample customers are explicit development fixtures. This scene does
not implement production ingredient inventory, customer orders, payments, a day
ledger or a reputation economy. Preview controls are disabled during any drag or
active action, and never take keyboard focus from Space-to-pour. Bucket work stays
separate. Brewing mechanics were accepted in PR #106; artwork and presentation
remain provisional. Ingredient and hanging interactions were accepted in PRs #110
and #111; shared-inventory review uses the separate scene described above.
