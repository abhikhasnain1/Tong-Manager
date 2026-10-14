# Customer scene and motion

Open `scenes/development/CustomerScenePreview.tscn` and press **F6** to review
the customer scene in the stall. This is a presentation review with sample
orders. The normal stall uses the same reusable Customer instances.

1. Watch the customers walk up. Use **Turn and leave** to see their quick turn
   followed by the back-facing walk. Both complete in the same amount of time.
2. In **Use** mode, drag a sample from the review panel onto a customer's head,
   arm or body. Only the visible silhouette highlights. Empty space, the roof,
   the counter and foreground hanging stock do not serve a customer behind them.
3. A requests tea; B requests a banana. Warm tea and the requested banana show a
   happy reaction. Cold tea is accepted but shows an unhappy cold/bad-review
   reaction. A wrong item leaves that customer waiting for a corrected sample.
4. Toggle **Optional dialogue**, **Reduced motion**, or one/two sample customers.
   Use **Replay arrival / new samples** for a fresh pair of orders.
5. Open the Khata and confirm its full view blocks world drops. Its pantry peek
   leaves the uncovered stall available. Existing brewing and placement still
   work normally.

These sample tokens never consume supplies, empty cups or pay money. Real
customer handoff and order matching are a later integration. The one/two sample
choice does not set the number of customers permitted in a day or queue.

## Editing the appearance

`scenes/gameplay/customers/Customer.tscn` is a reusable lower-center-anchored
`Node2D`. Instances in `TongDayScreen` replace the former static portraits.
Move or scale the instances to adjust the composition. Foreground hanging
positions are authored on the Banana and Biscuits sprites in that scene;
their existing pinned bodies still own sway and portion extraction.

The Customer Inspector exposes its definition, presentation settings, automatic
arrival, optional dialogue and reduced motion. Presentation settings control
the visual size, walk duration, depth, turn and bob. Defaults retain the
approved 1.15-second complete arrival/departure, a turn lasting the smaller of
0.42 seconds or 30% of that duration, and two small bobs of 1.1% visual height.
The departure bob starts after the turn. The back-facing pose stays still as
the whole figure recedes; no arm-cycle animation is required.

When making one customer's settings different, duplicate its presentation
resource in the Inspector before editing the copy. Shared resources deliberately
apply the same settings to every instance using them.

## Integration boundary

The Customer binds `CustomerDef` and `OrderState`. Its serve region and
`contains_serve_point()` provide a precise target, and its presentation methods
accept the existing `ServiceResult` identity. Repeated or mismatched outcomes
cannot replay the reaction. An accepted cold result fulfills the order with
an unhappy/bad-review cue; a rejection remains waiting.

`CustomerScenePreview` registers a separate sample-only DropZone adapter with
the existing interaction controller. It accepts only tokens created by that
preview. Physical cups, pantry exports and hanging portions cannot use it as
a production service endpoint. Spawning/queue management, active-order bubble
integration, real stock/cup handoff and payment remain separate features.
