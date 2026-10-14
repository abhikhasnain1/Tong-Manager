# Automatic payment

Open `scenes/development/PaymentPreview.tscn` and press **F6**. It starts on **Payment · unhappy responses**, using `data/examples/customer_days/payment_response_review.tres`. In **Use**, drop a prepared cup, banana or biscuit onto a waiting customer. Accepted snacks pay the saved order price immediately. Accepted cup servings pay when the dirty cup reaches table, tray or bucket after drinking; the cash HUD updates and two small coins travel toward it, each playing the selected coin sound. There is no collection button.

Correct deliveries are accepted. Wrong items, cold tea, poor brews and short pours use that visit's designer-selected **Unhappy Response**:

| Response | Customer and payment |
| --- | --- |
| Accept | Accepts unhappily and pays the saved quote: snacks immediately, cups after dirty return. |
| Refuse Leave | Returns the item and leaves without paying. |
| Refuse Retry | Returns the item, keeps the same order and waits for a remake; no payment yet. |

Both refusals return the same filled cup to its previous position, preserving contents, ingredient counts and brew history. They do not refund ingredients, empty or wash the cup. A refused untouched snack releases its reservation without consuming stock. This immediate refusal return is independent of accepted drinks' dirty-cup return and washing. Empty cups, cancelled drags and timeout without service also produce no payment or reward cue. Each real attempt retains its quality reasons; review aggregation is not implemented.

## Try the response schedule

The first customer on the left requests plain tea and waits for a remake while keeping remaining patience. The second, on the right, requests a banana and leaves unpaid after an unhappy delivery. Later visits demonstrate the other combinations:

| Visit | Request | Unhappy response | Remake patience |
| --- | --- | --- | --- |
| 1 | Plain tea, no sugar | Refuse Retry | Continue |
| 2 | Banana | Refuse Leave | Inherited; unused when leaving |
| 3 | Tea with sugar | Accept | Inherited; unused when accepted |
| 4 | Biscuit | Refuse Retry | Reset |
| 5 | Milk tea with sugar | Refuse Leave | Inherited; unused when leaving |
| 6 | Milk tea, no sugar | Accept | Inherited; unused when accepted |

Visits are due at 1, 7, 13, 19, 25 and 31 seconds, but later arrivals wait for a free place. Each has a 180-second patience allowance. Offer water or a wrong snack to see the response, then make a correct delivery to a waiting customer. Compare the ledger panel before and after each attempt. The review values are editable examples, not final balancing.

The review panel reads actual cash, income, expenses and the latest ledger entry. Restarting its customer schedule preserves money, stock and served cups. Recreating a stall scene in the same running game also preserves money/history. Stopping and running the project again starts a new run; this is not save/load persistence. Existing explicit development resets start a fresh ledger along with supplies. The Khata Finance page and day-end screen remain later consumers of this ledger.

## Set a customer's response in the Inspector

1. In **FileSystem**, open `data/customers/customer_a.tres` or `customer_b.tres`.
2. Set **Unhappy Response** to `ACCEPT`, `REFUSE_LEAVE` or `REFUSE_RETRY`.
3. Set **Remake Patience** to `CONTINUE` to keep time remaining, or `RESET` to restart that visit's full patience allowance after each new refusal. The defaults are Accept and Continue.
4. To change only one authored visit, open its DayConfig, expand **Customer Schedule → Arrivals**, then the entry. **Unhappy Response Override** and **Remake Patience Override** use **Inherit (-1)** for the profile setting; select another value to override it. **Patience Override** separately changes the allowance in seconds; zero inherits the profile duration.
5. Save, stop the running scene and press F6 again. Active visits keep their copied response, patience and quoted order; editing a resource does not rewrite them. These are authored choices, not random rolls.

Khata never pauses patience. On `TongDayScreen.tscn`'s **CustomerQueueManager**, **Refused Reaction Seconds** controls the brief unhappy reaction before Refuse Leave departs (default 0.25 seconds). A retry keeps the order cue and allows a new delivery attempt. Replaying an old attempt cannot reset patience again.

## Money and coin controls

- `DayConfig.starting_cash` supplies opening cash once per run. It does not count as sales income. Loading a different customer schedule does not replace the run's opening cash.
- Recipe `price` and ready-item `sell_price` determine an order's quoted price when that order is created. Editing catalog prices later does not rewrite a waiting customer's quote.
- Open `data/balance/payment_feedback.tres` to tune duration, arc, coin size, colors, amount text, reduced motion and sound. `TongDayScreen.payment_feedback_config` can use another resource.
- **Sound Stream** (`sound_stream`) selects the audio asset, defaulting to `assets/audio/sfx/coin_drop.mp3`. Replace it in the Inspector to change the effect; use a non-looping stream. The bundled file is the supplied `freesound_gamestudio-drop-coin-384921.mp3` copied without conversion or trimming.
- **Coin Launch Stagger Seconds** (`coin_launch_stagger_seconds`, default 0.11) spaces the two launches. Each launch plays the selected sound independently, including in reduced motion.
- **Sound Base Pitch** (`sound_base_pitch`, default 1.0), **Sound Pitch Step Semitones** (`sound_pitch_step_semitones`, default 2.0) and **Sound Pitch Cycle** (`sound_pitch_cycle`, default 4) give successive coins a short repeating pitch variation. Each overlapping coin has an independent sound voice; a later coin does not retune one already playing.
- Sound respects its configured bus and Master mute; **Sound Enabled** can disable it independently. Motion and audio never own the payment itself. Refusals and duplicate receipts emit no reward sounds.

## Shared authority

`GameState.finance` owns one `FinanceState`. Its read-only `cash_on_hand`, `day_income`, `day_expenses`, `transaction_log` and `get_snapshot()` expose the same balances to HUD, future Khata finance and day-end code. Opening cash is separate from income; net earnings are income minus expenses.

`record_income(source_id, amount, metadata, aliases)` and `record_expense(...)` accept positive whole-taka amounts and return true only for a new committed transaction. Reused or conflicting identities, invalid values, arithmetic overflow and unaffordable expenses are refused without changing history. Expenses are an API foundation; this slice adds no shop, rent, debt or other expense gameplay. Returned records are deep copies.

`CustomerPayments` lives under GameState. Only payable accepted fulfillment queues a copied receipt. Snacks become payable on acceptance; actual cup servings become payable after the same dirty cup reaches a valid return destination. The handoff captures the payment owner, ledger binding and generation before callbacks can remove the customer or scene. Deferred settlement credits it once using both order and handoff identities. Refusal attempts stay in the same order's history but never queue payment. A corrected remake can fulfill and pay once; refusal-and-leave closes without fulfillment. Once queued, changing scenes cannot lose a payable sale; an explicit run reset invalidates old queued receipts. An old receipt cannot pay after reset or replacement of its ledger, including switching away and back. Payment cues belong to the live originating screen, so leaving the scene may suppress the cue but not the money.

See [Cup reuse](cup-reuse.md) for drinking, dirty return, full-table waiting, washing and the scene-local persistence boundary. Full day progression, save/load and review aggregation remain separate work.
