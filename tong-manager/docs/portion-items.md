# Adding portion items and source artwork

Item identity and presentation live in `data/items/*.tres` using `ItemDef`. The catalog discovers those resources at startup. No central list of the five current pantry items needs to be edited.

This authoring path reuses the supported units (`teabag`, `spoonful`, `piece`) and existing gameplay effects. New effects or a new kind of unit need code. Item presentation alone does not authorize a vessel or customer to accept it; configure the corresponding [ingredient rule](ingredient-rules.md) separately. Production snack handoff remains a separate customer feature.

## Add an item

1. Duplicate an existing `ItemDef` resource into `data/items`, or create a new `ItemDef` in the Inspector. Give it a unique `id` and the appropriate `unit`.
2. Set `portion_label` to its short singular display name. Existing price, cost, category and translation-key fields remain separate metadata.
3. Assign `icon`. Enable `pantry_enabled` and set `pantry_order` to place the item in the notebook. Equal orders sort by ID. An item can have a physical source while staying out of the pantry.
4. Choose `portion_visual`: `auto` uses a teabag, spoon, or the item's icon according to unit. `portion_color` colors a spoonful. The current banana and biscuit styles are optional drawn presentation styles, not item identities. Missing piece artwork gets a neutral labelled token.
5. Add the item's integer starting quantity to the chosen `DayConfig.starting_inventory`. An omitted quantity starts at zero. Changes take effect on a new run or an explicit new-day reset; reopening a scene never replenishes stock.

The accepted five items retain their first-page 3+2 arrangement. Additional items appear in groups of five using small arrows inside the pantry paper. Peek and Full share the same group selection. Only visible cells can begin a pickup. Each grab still carries one portion; a recipe asking for five teabags takes five gestures.

Do not enable existing ginger, lemon or honey entries merely to test this workflow. Their gameplay support and default availability are separate design decisions.

## Bind existing scene artwork

`TongDayScreen.source_layout` references a `PortionSourceLayout`; the shipped layout is `data/balance/portion_sources_level_1.tres`. Duplicate it for a custom scene before editing shared resources.

For a movable container, add a `PortionSourceBinding` to `physical_sources`:

- `node_path`: path from the Tong scene to the authored item.
- `item_id`: the corresponding catalog ID. The source reads its unit from `ItemDef`.
- `input_area_path`: item-relative hit-area path, normally `PlacementBody`.
- `placement_handle_path`: item-relative free-placement adapter, normally `PlacementHandle`.

Artwork, hit shape and placement footprint still need to be authored in the scene. A binding does not create them or change their size. Multiple pictures may use one item ID and therefore one shared stock balance.

For a fixed hanging source, add a `HangingSourceBinding` to `hanging_sources`:

- `art_path`: path from the Tong scene to the authored `Sprite2D`.
- `node_name` and `item_id`: the suspended source's name and stock identity.
- `region`: the rectangle of source pixels used for this suspended picture.
- `pivot`: its pin position in the authored picture's pixel coordinates.

The default resource preserves the four containers, two banana bunches and biscuit bag with their existing regions and pivots. Sharing an item ID preserves shared depletion and cancellation behavior; duplicating a picture does not create more stock.

## Check the result

Open normal `TongDayScreen` or `InventoryPreview`. Verify the label/icon/unit, pagination in both notebook views, shared physical/pantry quantity, successful drop, invalid drop and Escape cancellation. `InventoryPreview` uses real inventory while its sample customer and ready-item handoff remain labelled review fixtures. Use its explicit reset only when you intend to replenish the configured day.

`tests/portion_catalog_test.gd` exercises temporary extra items, preserved default layout, bounded pagination, source rebinding, shared unit lookup and cancellation. It adds no shipped items.
