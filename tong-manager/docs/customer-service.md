# Customer serving

Open `scenes/development/CustomerHandoffPreview.tscn` and press **F6**. Its authored schedule visits all six order types, with two waiting places and three minutes of patience per customer. The normal Tong scene uses the same handoff system with its own day schedule.

## Try the scene

1. Select **Use**. Prepare tea with the existing water, stove, teabag and spoon interactions. Drag a non-empty cup onto any visible part of a waiting customer and release. The customer's outline shows the target; roof, counter and foreground hanging items still block what they cover.
2. Drag a banana or biscuit from its hanging source to a customer. Try the same from the pantry in both Peek and Full views. Each accepted snack spends one piece from the shared supply.
3. Try a wrong snack, extra or missing sugar/milk, a short pour, cold tea, water, underbrewed tea and oversteeped tea. They are all served. The request disappears and the customer reacts unhappily before leaving. Correct service produces a happy reaction.
4. Try an empty cup, cancel a drag, or release after a customer leaves. Nothing is served or spent. A cup returns to its previous position.

The kettle can now pour any non-empty liquid state. Ingredient placement still follows the selected ingredient policy: the default teabag goes in the boiling kettle, and sugar/milk go in cups. This change does not add cup steeping, mixing different liquids, or refilling brewed tea with water.

The review's **Restart this schedule** restarts customers only. Supplies, prepared contents and served cups remain as they are. Rerunning the scene reconstructs scene-local cups/kettle/history, as before; shared stock/water retain their existing run behavior. This is not save/load persistence.

## What can be tuned

- Desired recipes live in `data/recipes/`. Ingredient counts, minimum serving amount, batch dose and maximum batch size are comparison data. Missing/extra ingredients or poor quality cause review reasons rather than refusing delivery.
- Preparation permissions remain in the selected `IngredientPolicy`; see [Ingredient rules](ingredient-rules.md).
- Brewing and cold thresholds remain in `BrewingConfig`. Cold is assessed at release using the cup's current temperature.
- Arrival spacing, requested orders and patience remain in `CustomerSchedule`; see [Customer days](customer-days.md). The review schedule is `data/examples/customer_days/service_review.tres`.
- `CustomerQueueManager.served_reaction_seconds` controls the short reaction before departure.

## Ownership and integration

`CustomerService` binds the queue's live customer and saved order to a full-body `CustomerServiceZone`. `ServiceEvaluation` assesses a detached contents snapshot. Wrong deliveries still create an accepted `ServiceResult`, with all factual reasons on that one outcome. Review grouping, scores and reputation are later design work.

At pour time, cups retain each distinct contributing brew state, batch infusion and mixed-ingredient doses, whether boiling water was used, and original batch volume. Later kettle changes or known top-ups cannot erase earlier poor or unknown contributions. Actual cup ingredients include direct spoonfuls and fractions carried from a mixed kettle. Water keeps its own liquid color, and hover markers warn when a cup contains underbrewed or oversteeped tea.

Ready servings use `IngredientPortion.commit()`. Cups were paid for in ingredients during preparation, so serving does not debit those ingredients again. The order/result and cup ownership are committed before presentation callbacks. Duplicate attempts cannot fulfil or consume twice.

A served cup moves into the screen-owned `CustomerService/ServedCups` holder. It retains its object identity, contents and assigned order; its table footprint and interaction targets are released. Customer departure, queue restart and detaching/re-adding the same screen preserve it. Dirty return and washing remain separate work.

`CustomerService.service_accepted(record)` publishes once after successful input cleanup. `get_records()` returns copied records containing handoff/order/customer IDs, the saved request, its quoted price, actual result and retained cup instance ID. This is the integration point for automatic payment in #68; this slice does not change cash or play a payment cue. Payment consumers must deduplicate on the handoff/order identity.

The older `CustomerScenePreview` uses labelled synthetic presentation tokens and historical rejection samples. Use `CustomerHandoffPreview` to test the current production serving policy.
