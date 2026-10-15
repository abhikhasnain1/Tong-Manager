# Customer and order data

Open `scenes/development/CustomerOrdersPreview.tscn` in Godot and press **F6**.
This is a **development data preview**. Its controls simulate handoff results;
they are not the final customer interface or a playable customer queue.

## What to review

1. Switch between Customer A and Customer B. Each profile has editable patience
   and an order pool; no patience timer runs in this scene.
2. Try all six requests: the four supported tea recipes, one banana and one
   biscuit. Each order asks for one serving or one piece, not a combined meal.
3. On a tea order, choose **Accept cold tea**. The order becomes served, while
   the result records an unhappy customer and a bad review.
4. Choose **Replay last result**. It must leave the recorded history unchanged.
   Further attempts also cannot fulfill an already-served order again.
5. Choose **New order**, then **Reject wrong item**. It stays pending and has no
   accepted-service review. Accept a correct result afterward to fulfill it.
6. Try the banana and biscuit orders. They use the same item IDs and icons as
   the pantry and hanging sources, and have no tea-temperature controls.
7. Choose **Check invalid reference**. An isolated copy with a missing recipe
   or item is rejected; the saved definition and active order remain unchanged.

Changing customer/request or choosing **New order** makes a new isolated order
with a fresh ID. It does not reset the day or change inventory, daily water,
vessels, cash or production outcomes. The preview displays numeric recipe data
for inspection; those numbers are not proposed player-facing status markers.

## Change customer settings

In the FileSystem dock, open `data/customers/customer_a.tres` or
`customer_b.tres`. The Inspector exposes:

- **Id**: stable identity. Keep it unique when creating another profile.
- **Display Name Key**: translation key; the preview falls back to a readable ID
  while translations are absent.
- **Sprite Texture**: optional existing portrait artwork.
- **Patience Seconds**: a positive duration; 60 seconds is a review default,
  not a final balance decision. The live queue starts it after arrival.
- **Dialogue Profile**: optional reference for a future dialogue consumer.
- **Order Requests**: the requests this customer is allowed to make.
- **Unhappy Response**: `ACCEPT`, `REFUSE_LEAVE` or `REFUSE_RETRY`. A correct
  delivery always accepts. For a bad-quality/wrong delivery these choices mean
  pay normally, leave unpaid, or wait for a remake unpaid, respectively.
- **Remake Patience**: `CONTINUE` keeps time remaining; `RESET` restores the
  visit's full allowance after a new retry refusal. Defaults are Accept and Continue.

To restrict a customer to tea, remove the banana/biscuit entries from that
customer's **Order Requests** array. Removing an array entry does not delete
the shared request file or remove it from another customer. Keep at least one
valid request. Save and rerun F6 to see the edited profile.

To override only one authored visit, open its DayConfig and expand **Customer
Schedule → Arrivals → entry**. Set **Unhappy Response Override** and/or
**Remake Patience Override**; **Inherit (-1)** uses the profile. **Patience
Override** separately changes the allowance in seconds (zero inherits). These
settings are copied for the visit, not randomly selected. Stop and rerun after
saved resource edits. Khata never pauses patience. See [Customer days](customer-days.md)
and [Automatic payment](payments.md) for the live review and examples.

## Author an order request

The six starter definitions live in `data/orders/`. A tea request points to a
recipe; a ready-item request points to an existing item:

| Kind | Set | Leave empty | Current quantity |
| --- | --- | --- | --- |
| `tea` | Recipe Id, such as `cha_no_sugar` | Item Id | 1 cup |
| `ready_item` | Item Id, such as `banana` | Recipe Id | 1 piece |

For another request, duplicate a suitable `.tres` in the FileSystem dock, give
the new resource a unique **Id**, and save it under `data/orders/`. Then drag
that file into a customer's **Order Requests** array. Catalog loads resources
from that folder at startup. Every pool entry references its shared Catalog
resource; do not create an unrelated embedded request with the same ID.

Editing a shared request changes it for every customer whose pool includes
that file. To change only one customer's request, duplicate the request file,
give the copy a new ID, and replace only that customer's array entry with the
copy. To change only which requests a customer permits, edit its array instead.

Tea prices, desired ingredient amounts/units and serving volumes come from
the referenced `data/recipes/*.tres`. Ready-item prices, icons and piece units
come from `data/items/*.tres`. Requests do not maintain duplicate prices or
recipe requirements. An unsupported/locked recipe, missing ingredient,
incorrect unit, invalid serving volume or invalid ready item fails validation.
Unused ginger/lemon reference recipes do not invalidate these six requests.
There is no new unlock system for ready items.

Ingredient action permissions remain separate from order requirements; see
[ingredient rules](ingredient-rules.md). Being allowed to add an extra
spoonful does not change what a customer requested. Only one-serving/piece
requests are supported in this slice; quantity changes and bundles need
consumer support before they can become playable rules.

## Data ownership and integration

`Catalog.create_order(order_id, customer_id, request_id, created_time)` validates
the selected customer's pool and returns an `OrderState`, or `null` on invalid
input. The queue owner supplies unique order IDs and retains the
authoritative state. Catalog is a definition registry, not an active-order
registry or random order selector.

The order copies request identity, ingredient requirements, price, serving
metadata and the resolved response/patience policy when created. Later definition edits affect new orders; they do not
rewrite existing ones. Returned dictionaries and nested arrays are copies.
Textures remain shared artwork resources. The derived `order_recipe_ids`
property is for tea-only readers; `order_requests` is the editable authority.

The isolated-fixture `ServiceResult.create(...)` records an already-evaluated accepted/rejected
decision and the tea's cold condition at handoff. It does **not** inspect a cup
or decide whether ingredients match. Accepted cold tea is fulfilled and records
`unhappy`, `bad_review` and `cold_tea`. Rejection records a reason without
fulfillment or an accepted-service review. Warm tea and ready-item acceptance
do not inherit the cold-tea consequence. No numerical rating or price penalty
is implied.

`OrderState.record_result(result)` requires matching customer/order/kind
identity and a new handoff ID. Refuse Retry records an attempt without fulfilling
or closing the order; a new delivery gets a fresh handoff ID under that same
order. Refuse Leave closes the order without fulfillment; acceptance closes and
fulfills it. `get_results()` preserves all attempt facts, while
`get_terminal_result()` distinguishes accepted completion from leaving unpaid.
Duplicate/conflicting IDs and further results after closure are ignored. Retrying
the same command must reuse its stable ID rather than invent another attempt.
These guarantees apply within the retained authoritative
`OrderState`; recreating an order with the same ID is not a persistence or
cross-process deduplication mechanism.

Customer visuals, queue/patience, order bubbles and real serving now consume
these snapshots. Production serving uses `ServiceEvaluation` and
`ServiceResult.create_evaluated(...)`: any structurally valid non-empty cup or
ready snack can be offered. Mismatch and brew quality become recorded reasons;
the captured unhappy response selects Accept, Refuse Leave or Refuse Retry.
Refusal retains bad-review facts for that attempt without deciding an aggregate
score or grouped review. Both refusals return the original filled cup unchanged;
an untouched snack releases its reserved unit without consumption. Payment only
follows accepted fulfillment. See [Customer serving](customer-service.md). The accepted/rejected
constructor above remains available to isolated component fixtures.

Automatic payment consumes the committed service receipt through the shared run
ledger; see [Automatic payment](payments.md). The isolated order-data preview
still never changes cash. Day-end feedback (#73), the Khata Finance page (#74),
review aggregation and preference dialogue remain separate. Accepted cup servings
now pay after dirty return; snacks pay on acceptance. See [Cup reuse](cup-reuse.md)
for collection, batch washing and progressive automatic return to tray/table space.
