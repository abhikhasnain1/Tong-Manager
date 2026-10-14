# Authoring ingredient rules

The rules in `data/balance/ingredient_policy.tres` are the shipped defaults. They are design data, separate from vessel bookkeeping and recipe goals. Physical containers and both pantry views use the same selected policy and stock transaction.

## Change a rule in the Inspector

A **policy** is a settings file containing a list called **Rules**. Each rule is a smaller set of settings for one ingredient in one vessel: for example, teabags in the kettle. Godot calls these settings objects *resources*.

For an experiment, copy the whole settings file:

1. In Godot's **FileSystem** panel, find `res://data/balance/ingredient_policy.tres`. Right-click it, choose **Duplicate**, and give the copy a different name, such as `ingredient_policy_duplicate.tres`. If you have already made this copy, use it.
2. Double-click the copied file in **FileSystem** to show it in the **Inspector**. Check that you opened the copy, not `ingredient_policy.tres`.
3. Expand **Rules**, then click the resource in entry **0** to show the teabag settings. Confirm that **Item Id** is `black_tea` and **Vessel Kind** is `kettle`. In the shipped policy, entry **1** is sugar in cups and entry **2** is milk in cups.
4. As a first experiment, change **Max Portions** from **1** to **5**. Keep **Quantity** at **1**: that is how many units one drag carries. Click the **save icon at the top of the Inspector**, then choose **Save** to save the copied settings file.
5. Open `scenes/gameplay/tong/TongDayScreen.tscn`. Select the root **TongDayScreen** node in the **Scene** tree. Drag your copied `.tres` file from **FileSystem** onto **Ingredient Policy** in the Inspector. Save the scene. This changes which settings this scene uses; editing a copy alone does not activate it.
6. Press **F6** to run that scene. Select **Use**, fill and boil the kettle, and try adding several bags. The changed rule should permit five bags and reject the sixth, while still requiring boiling liquid for each addition. To return to the shipped defaults, assign the original `ingredient_policy.tres` to **Ingredient Policy** and save the scene again.

**No extra "Make Unique" step is needed for this file-copy workflow.** The three rules are stored inside the policy file, so copying that file also copies their settings. Editing the copy does not edit the original file. Scenes assigned to the same policy file do share its settings.

"Make Unique" is Godot's term for replacing a shared resource with a separate copy. It matters when you reuse an existing resource in the Inspector and want to edit it independently. Copying only the outer settings object there can leave its inner rule objects shared. That is a different operation from duplicating the complete policy file in **FileSystem**. If a future policy links to rules saved in separate `.tres` files, copy those rule files too and assign the copies; copying the policy file alone would keep those links.

Use the field reference below for further changes. To allow an ingredient in both kettle and cup, give it one rule for each destination. Keep at most one enabled rule for each ingredient/vessel pair. Check successful, rejected and cancelled drops from a physical source and both pantry views. Invalid settings reject the drop with an explanation and preserve stock.

The review sandbox at `scenes/development/IngredientRulesPreview.tscn` has four selectable examples. Open it and press **F6**. Switching examples deliberately empties vessels and resets the day supplies. The examples never change the shipped policy. The normal scene continues to use the current defaults.

| Field | Meaning |
| --- | --- |
| `enabled` | Whether this rule is available. Missing or disabled rules reject the item in that vessel. |
| `item_id`, `unit` | Catalog identity and gameplay unit; they must match the held portion. |
| `quantity` | Units required in one drop. Keep this at 1 for the current one-portion source gestures. |
| `vessel_kind` | `kettle` or `cup`. |
| `effect` | `mix` records units without brewing; `infuse` starts or adds to a kettle batch. |
| `output_liquid_id` | The liquid produced by infusion, such as `black_tea` or a new `coffee` identity. Required for `infuse`; leave empty for `mix`. |
| `restart_steeping` | Whether a subsequent infusion restarts the batch clock. Normally additional bags preserve progress. Only valid for `infuse`. |
| `allowed_stages` | Exact stage names where a drop is allowed. An empty list permits none. |
| `allow_empty` | Allow additions before there is liquid. `mix` can record a dry addition; `infuse` still needs liquid to brew. |
| `allow_repeated` | Whether the same ingredient can be added while an amount is already present. |
| `max_portions` | Maximum amount currently in this vessel: -1 is unlimited, 0 disables additions, a positive number caps them. |
| `allowed_liquid_ids` | Permitted existing liquid bases. An empty list accepts any base. Empty vessels are controlled by `allow_empty`. |
| `requires_boiling` | Require the vessel's configured boiling temperature. Turning it off permits cooler additions, subject to the temperature range. |
| `minimum_temperature`, `maximum_temperature` | Inclusive temperature range for adding this item. |
| `minimum_volume_ml` | Minimum liquid present before adding this item. |
| `max_batch_volume_ml` | Kettle batch allowance, independent of physical capacity. -1 removes this rule limit; it never enlarges the vessel. |

Kettle stages are `empty`, `water`, `heating`, `boiling`, `steeping`, `liquor_ready`, and `oversteeped`. Cup stages are `clean`, `in_use`, `filled`, `served`, and `dirty`. Allowing a stage authorizes an ingredient drop; it does not wash a cup, make an oversteeped batch ready, or change serving eligibility.

## Examples

`data/examples/ingredient_rules/five_teabags.tres` changes only the teabag rule's `max_portions` from 1 to 5. Each accepted bag is counted and consumes one stock unit. The sixth is rejected. Each bag still requires boiling liquid; adding a bag does not automatically restart steeping.

`no_teabags.tres` sets the cap to 0. Bags are rejected without stock loss. This does not make water become tea automatically. Automatic brewing without an ingredient would be a separate mechanic.

`mixing_and_stages.tres` demonstrates changing several permissions together: infusion may begin at 20°C, sugar may be mixed into the kettle while steeping or ready, and milk only while ready. Cup rules are unchanged. These are demonstration settings, not new default design decisions.

For a ground-coffee item, author an ItemDef with `unit = spoonful`, add a kettle `infuse` rule with its item ID and `output_liquid_id = coffee`, and list the stages, temperatures and existing liquids it should accept. The generic brewing and pouring path carries the chosen liquid identity. A cup rule can then permit sugar in `coffee` as well as `black_tea`.

For a piece ingredient, use `unit = piece` and an ordinary `mix` or kettle `infuse` rule. Pieces are not restricted to snack handoffs. Without a matching vessel rule, current bananas and biscuits still cannot be added to a cup or kettle. See [portion items and source artwork](portion-items.md) for catalog, stock, icons, additional pantry pages and scene bindings.

## Contents, effects and recipes

Infused portions are integer batch counts in the kettle. They stay with the batch through partial pours and clear when the kettle is emptied. Mixed portions are abstract units: adding a spoonful changes neither measured liquid volume nor temperature. When a mixed kettle is poured, mixed units move in proportion to the liquid. For example, one sugar spoonful in 500 ml contributes 0.5 sugar units to a 250 ml cup, leaving 0.5 in the kettle. A full cup accepts only the fraction corresponding to the liquid it receives. Direct cup additions remain whole portions and combine with inherited fractions in `get_ingredient_amounts()`.

Emptying a vessel clears its ingredient amounts and liquid without refunding stock. Snapshots returned by the vessel query methods are copies. Consumers such as future contents badges and recipe checking should use these snapshots, not the legacy boolean `contains_tea` or direct-only `relish_item_ids` array. The plain-tea sample already rejects mixed ingredients inherited from a kettle.

Recipe resources describe the desired result: ingredient quantities and units, batch requirements, and serving amounts. They do not impose the legal addition cap. A policy may allow five bags while a recipe still asks for one, leaving later recipe checking able to recognise mistakes. Changing a recipe alone does not change which gestures a vessel accepts. Brewing speed, oversteep timing and thermal tuning remain in `BrewingConfig`; capacity remains on the vessel/tool data.

Current defaults remain one teabag in boiling kettle water up to 1500 ml, sugar and milk in clean empty cups or unserved black-tea cups, and repeated spoonfuls allowed. The existing recipe defaults remain one required bag or spoon where applicable, a 250 ml target cup and 225 ml minimum serving amount.

The supported effects are kettle infusion and kettle/cup mixing. Cup infusion is rejected explicitly; adding a bag with a cup `mix` rule records the bag but does not start a cup brewing clock. New mechanics such as cup steeping, liquid-volume ingredients, different unit systems, or removing individual bags still need implementation. This layer makes existing mechanics configurable without pretending those mechanics already exist.

## Verification

`designer_ingredient_rules_test.gd` checks alternative policies through stock transactions, including limits, stages, cool infusion, output identities, repeat timing, mixtures and callback-time revalidation. `configurable_vessel_test.gd` checks counted contents and conservative transfers. `portion_catalog_test.gd` and its rendered input companion check authoring extra items and additional pantry groups. The existing ingredient command and input suites verify the unchanged default loop.
