# Cups, returns and washing

Open `scenes/development/CupReusePreview.tscn` and press **F6**. The review day contains eight drink requests and two snacks, with two customer places and long patience. There are six physical cups, so completing the drinks requires reuse. This review day deliberately accepts mistaken servings with bad reviews; customer response choices in other days remain unchanged.

## Try the complete loop

1. Select **Use**, prepare a drink and serve its cup to a customer. Cash does not change yet. After eight seconds the customer offers that same cup, now empty and dirty.
2. Drag the offered cup onto clear table/tray space or directly into the wash bucket at the lower right. The customer pays automatically and leaves. Cancel with **Esc** to return the cup to the customer without payment.
3. Alternatively, leave the offered cup for another eight seconds. The customer puts it on available table/tray space, pays and leaves. If both are full, the customer keeps it without an extra penalty until space becomes available.
4. In **Use**, drag a dirty table/tray cup into the bucket. Hold the bucket body to wash. Release to pause, then hold again to continue. Cups wash sequentially, one at a time.
5. Drag the small clean-cup pickup on the bucket onto clear table/tray space. Washing alone does not put cups back automatically. Cancelled or blocked pickup leaves the clean cup in the bucket.
6. Fill and serve the cleaned cup again. Once it is back on the table/tray, rearranging it uses **Organize**, just like the other cups.

The bucket holds six cups, including washed cups waiting for pickup. A full bucket refuses the next cup and preserves its source. Clean, filled and already served cups cannot be washed directly. Dirty cups have already been emptied by drinking. The wastebasket remains the separate place for discarding unwanted vessel contents.

Washing does not use the plastic water jar's brewing supply. Opening Khata Full cancels an active wash or world drag; Peek keeps the stall usable. Neither pauses drinking or collection clocks. Snacks still pay immediately on acceptance. Refused drinks return the same **filled** cup immediately, with no payment, ingredient refund or washing.

## Change the timings and capacity

In Godot's **FileSystem**, open these resources, edit their Inspector fields, save, and restart the review scene:

| Resource | Field | Default |
| --- | --- | --- |
| `data/balance/bucket_config.tres` | Capacity | 6 cups, dirty and clean combined |
| `data/balance/bucket_config.tres` | Wash Seconds | 2.4 seconds per cup |
| `data/balance/cup_returns.tres` | Drinking Seconds | 8 seconds |
| `data/balance/cup_returns.tres` | Attention Seconds | 8 seconds to collect before automatic placement |
| `data/balance/cup_returns.tres` | Attention Offset | Position of the offered cup relative to the customer |

These are adjustable starting values. `BucketStation` exposes **Config**, and `TongDayScreen` exposes **Cup Return Config**, so another scene can use a separate saved resource. Return timings are copied when a drink is accepted; changing them does not retime a customer already drinking. Wash duration is read from the bucket's current configuration.

The authored review schedule is `data/examples/customer_days/cup_reuse_review.tres`. It controls arrivals, requests, patience and unhappy-response overrides, using the same resources as other days. See [Customer days](customer-days.md) and [Automatic payment](payments.md).

## State and ownership

Each cup remains the same object through serving, consumption, return, washing and reuse. A committed destination takes custody before its source releases it. Invalid drops and cancellation keep the source's cup. The controller permits free placement in Use only while extracting a cup from the customer or bucket; it does not change ordinary Organize rules.

An accepted cup receipt becomes payable only after the cup reaches table, tray or bucket. Income uses the saved order quote and is recorded once. A reset or replacement ledger cannot receive an old unpaid cup's sale. Customer removal or restarting the schedule retains the cup in the same screen; it is recovered onto available space. Detaching and re-adding that same screen cancels an unfinished pickup safely.

Cups and brewing contents remain scene-local, as before. Destroying and recreating the entire scene reconstructs them; this is not save/load persistence. Shared supplies and already recorded money keep their existing run behavior. Day progression, reputation aggregation and wash-water depletion are separate work.
