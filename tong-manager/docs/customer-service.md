# Customer serving

Open `scenes/development/CustomerHandoffPreview.tscn` and press **F6**. Its authored schedule visits all six order types, with two waiting places and three minutes of patience per customer. Its shared profiles default to **Accept**, so unhappy deliveries still complete service in that example. The normal Tong scene uses the same handoff system with its own day schedule. Use `PaymentPreview.tscn` to review all three authored responses and remake patience; see [Automatic payment](payments.md).

## Try the scene

1. Select **Use**. Prepare tea with the existing water, stove, teabag and spoon interactions. Drag a non-empty cup onto any visible part of a waiting customer and release. The customer's outline shows the target; roof, counter and foreground hanging items still block what they cover.
2. Drag a banana or biscuit from its hanging source to a customer. Try the same from the pantry in both Peek and Full views. Each accepted snack spends one piece from the shared supply.
3. Try a wrong snack, extra or missing sugar/milk, a short pour, cold tea, water, underbrewed tea and oversteeped tea. These are eligible attempts, with factual quality reasons. **Accept** completes the order and pays normally despite unhappiness. **Refuse Leave** returns the item and leaves unpaid. **Refuse Retry** returns it and waits for the same order to be remade. Correct service produces a happy reaction and normal payment for every policy.
4. Try an empty cup, cancel a drag, or release after a customer leaves. Nothing is served or spent. A cup returns to its previous position.

The kettle can now pour any non-empty liquid state. Ingredient placement still follows the selected ingredient policy: the default teabag goes in the boiling kettle, and sugar/milk go in cups. This change does not add cup steeping, mixing different liquids, or refilling brewed tea with water.

Both refusals restore the same filled cup to its previous position. Contents, ingredients and brew history remain; there is no refund, emptying or automatic washing. A refused untouched banana/biscuit releases its reservation without consuming stock. Each new drag is a new attempt; repeating the old command cannot return or consume twice. Immediate refusal is separate from the held dirty-return/washing flow.

The review's **Restart this schedule** restarts customers only. Supplies, prepared contents, served cups and money remain as they are. Recreating the scene reconstructs scene-local cups/kettle/service history, as before; shared stock, water and finance keep their existing run behavior. Stopping and restarting the process begins a new run. This is not save/load persistence.

## What can be tuned

- Desired recipes live in `data/recipes/`. Ingredient counts, minimum serving amount, batch dose and maximum batch size are comparison data. Missing/extra ingredients or poor quality create reasons for the selected unhappy response.
- Preparation permissions remain in the selected `IngredientPolicy`; see [Ingredient rules](ingredient-rules.md).
- Brewing and cold thresholds remain in `BrewingConfig`. Cold is assessed at release using the cup's current temperature.
- Arrival spacing, requested orders and patience remain in `CustomerSchedule`; see [Customer days](customer-days.md). The review schedule is `data/examples/customer_days/service_review.tres`.
- `CustomerQueueManager.served_reaction_seconds` controls the short reaction before departure.
- Customer profiles expose **Unhappy Response** (Accept, Refuse Leave, Refuse Retry) and **Remake Patience** (Continue or Reset). Authored arrival entries can override either; **Inherit (-1)** uses the profile. Continue keeps remaining time; Reset restores the visit allowance after a new retry refusal. Khata pauses neither. See [Inspector steps](payments.md#set-a-customers-response-in-the-inspector).
- `CustomerQueueManager.refused_reaction_seconds` controls Refuse Leave's brief reaction before departure (default 0.25 seconds).

## Ownership and integration

`CustomerService` binds the queue's live customer and saved order to a full-body `CustomerServiceZone`. `ServiceEvaluation` assesses a detached contents snapshot. `ServiceResult.create_evaluated()` combines those facts with the visit's captured response policy. Each attempt retains its reasons, including on refusal. Retry preserves one order and its earlier attempts; acceptance or Refuse Leave makes it terminal. Review grouping, scores and reputation are later design work.

At pour time, cups retain each distinct contributing brew state, batch infusion and mixed-ingredient doses, whether boiling water was used, and original batch volume. Later kettle changes or known top-ups cannot erase earlier poor or unknown contributions. Actual cup ingredients include direct spoonfuls and fractions carried from a mixed kettle. Water keeps its own liquid color, and hover markers warn when a cup contains underbrewed or oversteeped tea.

Accepted ready servings use `IngredientPortion.commit()`; refused ready portions only release the reservation. Cup ingredients were consumed during preparation, so serving or returning does not debit or refund them. The order/result and cup ownership are committed before presentation callbacks. Duplicate attempts cannot fulfil, return or consume twice.

A served cup moves into the screen-owned `CustomerService/ServedCups` holder. It retains its object identity, contents and assigned order; its table footprint and interaction targets are released. Customer departure, queue restart and detaching/re-adding the same screen preserve it. Dirty return and washing remain separate work.

`CustomerService.service_resolved(record)` publishes each real response once after input cleanup; `service_accepted(record)` additionally publishes accepted fulfillment only. `get_records()` returns copied attempt records containing handoff/order/customer IDs, the saved request, its quote, result and served/returned cup identity. The run-owned `CustomerPayments` receives only payable accepted receipts before presentation callbacks and credits once. See [Automatic payment](payments.md) for its ledger, cue, reset boundary and review scene.

The older `CustomerScenePreview` uses labelled synthetic presentation tokens and historical rejection samples. Use `CustomerHandoffPreview` to test the current production serving policy.
