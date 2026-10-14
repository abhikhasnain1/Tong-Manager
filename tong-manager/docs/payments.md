# Automatic payment

Open `scenes/development/PaymentPreview.tscn` and press **F6**. In **Use**, drop a prepared cup, banana or biscuit onto a waiting customer. The recorded order price is paid automatically, the cash HUD updates, and two small coins travel toward the cash display with a short chime. There is no collection button.

Wrong items, cold tea, poor brews and short pours still pay the normal quoted price. They keep their dissatisfied service result; payment adds no fine, discount or refund. Empty cups, cancelled drags and customers who time out without service produce no payment.

The review panel reads actual cash, income, expenses and the latest ledger entry. Restarting its customer schedule preserves money, stock and served cups. Recreating a stall scene in the same running game also preserves money/history. Stopping and running the project again starts a new run; this is not save/load persistence. Existing explicit development resets start a fresh ledger along with supplies. The Khata Finance page and day-end screen remain later consumers of this ledger.

## Designer controls

- `DayConfig.starting_cash` supplies opening cash once per run. It does not count as sales income. Loading a different customer schedule does not replace the run's opening cash.
- Recipe `price` and ready-item `sell_price` determine an order's quoted price when that order is created. Editing catalog prices later does not rewrite a waiting customer's quote.
- `data/balance/payment_feedback.tres` controls duration, arc, coin size, colors, amount text, reduced motion and sound. `TongDayScreen.payment_feedback_config` can use another resource. Sound respects its configured bus and Master mute; it can be disabled independently. Motion and audio never own the payment itself.

## Shared authority

`GameState.finance` owns one `FinanceState`. Its read-only `cash_on_hand`, `day_income`, `day_expenses`, `transaction_log` and `get_snapshot()` expose the same balances to HUD, future Khata finance and day-end code. Opening cash is separate from income; net earnings are income minus expenses.

`record_income(source_id, amount, metadata, aliases)` and `record_expense(...)` accept positive whole-taka amounts and return true only for a new committed transaction. Reused or conflicting identities, invalid values, arithmetic overflow and unaffordable expenses are refused without changing history. Expenses are an API foundation; this slice adds no shop, rent, debt or other expense gameplay. Returned records are deep copies.

`CustomerPayments` lives under GameState. The serving authority queues a copied receipt before callbacks can remove the customer or scene. Deferred settlement credits it once using both order and handoff identities. Changing scenes cannot lose that accepted sale; an explicit run reset invalidates old queued receipts. An old receipt cannot pay again after reset. Payment cues belong to the live originating screen, so leaving the scene may suppress the cue but not the money.

Full day progression, save/load, review aggregation, cup returns, washing and bucket mechanics remain separate work.
