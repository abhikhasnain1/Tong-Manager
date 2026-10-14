# Designing customer arrivals

Open `scenes/development/CustomerQueuePreview.tscn` and press **F6**. Customers
walk up at different times. At most two occupy the counter, including anyone
still arriving or leaving. When a place is unavailable, the next visitor waits
offscreen. The schedule keeps its order and spacing instead of dropping visits
or spawning a crowd at once.

The review panel offers two short authored days and the generated demo schedule.
The authored examples deliberately use short patience so you can see a whole
sequence quickly. **Preview left/right departure** only demonstrates freeing a
place; it does not serve the customer's order. **Restart this schedule** starts
the arrivals again without refilling water, restoring stock or changing cups.
Opening either Khata view keeps arrivals and patience running.

## What controls a day

`DayConfig` contains starting supplies and a `Customer Schedule` resource.
The customer schedule controls this slice of the day. It does not yet advance
the campaign, collect payment or reset supplies between consecutive days.

| Setting | What it controls |
| --- | --- |
| Mode: Generated | Choose visitors from a customer pool, using an editable initial delay and gap. `DayConfig`'s customer count minimum/maximum control the total. |
| Mode: Authored | Use the exact list of arrival entries. The list length controls the total; the generated count minimum/maximum are ignored. |
| Max Active | How many places may be occupied at once. Default: two. Add matching scene markers before raising it. |
| Timeout Reaction Seconds | How long disappointment remains visible before a timed-out customer turns away. Default: 0.8 seconds. |
| Customer profile | Portrait, possible orders and default patience. The same profile can visit more than once. Each visit gets its own order and runtime identity. |

The normal demo is `data/balance/demo_day_1.tres`. Its generated schedule starts
after 3 seconds, spaces visitors by 15 seconds, and uses the existing 4–5 daily
total. These are tuning defaults. The stall's **Customer Queue Seed** makes
generated choices reproducible; change the seed to try a different sequence.
The queue review scene has its own **Preview Seed**, default 64, on its root.

Schedules are validated and copied when started. Editing a file during a run
does not silently rewrite that run's orders or timing. After saving resource
edits, stop the running scene and press F6 again to load the new settings.

## Edit an existing authored day

1. In Godot's **FileSystem** dock, open
   `data/examples/customer_days/authored_day_1.tres`.
2. In the Inspector, expand **Customer Schedule**. Its mode is **Authored**.
3. Expand **Arrivals**, then expand one entry. Each entry describes one visit:
   - **Id** is a unique name within this schedule, such as `morning_tea`.
   - **Due Seconds** is the earliest arrival time, measured from schedule start.
   - **Customer** selects a shared customer profile.
   - **Request** optionally fixes the order. Leave it empty to choose from that
     customer's pool. A fixed request must belong to that pool.
   - **Patience Override** changes patience for this visit only. Zero uses the
     profile's default; a positive value is measured in seconds.
4. Keep entries in chronological order. Equal times are allowed, subject to
   available places. If the counter is full, deferred arrivals keep their
   authored spacing.
5. Save the resource, run the preview and select **Authored day 1**. After a saved
   resource edit, stop the scene and run it again with F6.

Patience begins after the customer has finished walking up. A timeout disables
their serving target, briefly shows disappointment, then starts departure. It
does not fulfill an order, produce an accepted-service bad review or charge
money. The place becomes free only after departure finishes.

## Create another day without changing the existing one

1. Right-click the `data/examples/customer_days` folder in FileSystem and choose
   **Create New → Resource**. Select **DayConfig** and save a new file, such as
   `my_day_3.tres`.
2. Open the new file. Set its starting supplies and other day settings as needed.
3. At **Customer Schedule**, use the resource dropdown to create a **New
   CustomerSchedule**. Give it a stable Id such as `day_3_customers` and choose
   **Authored** mode.
4. Expand **Arrivals**, set its size, and create a **New CustomerArrivalDef** in
   each empty element. Fill in each visit as described above.
5. Drag existing profile files from `data/customers` into **Customer**, and
   existing files from `data/orders` into **Request** when you want a fixed order.
6. To try your file in the stall, select the root of `TongDayScreen.tscn` and
   assign it to **Day Config**, then run that scene with F6. Save the scene only
   if you want it to keep that assignment. The queue preview dropdown is a
   fixed review list, not the game's day-selection menu.

Each newly created schedule and entry belongs to that new day. Customer profiles
and order definitions are deliberately shared: changing a shared profile affects
every day that references it on the next start. For a different waiting time on
just one visit, use **Patience Override** rather than editing the profile.

`authored_day_2.tres` is a second independent example. Switching between example
files demonstrates reusable day authoring; it does not implement automatic
day-to-day progression or persistence of a partially played schedule.

## Counter placement and later integration

Open `TongDayScreen.tscn` and expand
`WorldRoot/CustomerLayer/CustomerQueueSlots`. Move its left and right `Marker2D`
nodes to adjust where customers stand. The queue uses these markers in order.
The `CustomerQueueManager` node controls actor scale and uses the reusable
Customer scene's motion settings. Keep customer silhouettes and order cues
clear of the counter, roof and hanging stock.

Each waiting visitor now has round order cues beside their head. A cup with a
small tea identity icon means tea; sugar and milk icons show the requested cup
additions and their abstract spoon counts. Banana and biscuit orders use the
same artwork as the pantry. The two authored examples together include all six
current requests. Optional dialogue is not required to distinguish them.

The cue reads that visit's saved `OrderState` request. Recipe edits affect newly
created orders; an active visit keeps its captured request. Cues follow their
customer, avoid fixed HUD/Peek controls and pass mouse input through. Wrong-item
feedback keeps the unfulfilled request readable; fulfillment, timeout or departure
removes the request. Feedback in automated review uses existing result fixtures,
not a real handoff command.

For presentation tuning, select `HUDLayer/RootUI/CustomerOrderOverlay` in
`TongDayScreen.tscn` to adjust screen margin and separation. The reusable
`scenes/ui/CustomerOrderBubble.tscn` exposes bubble diameter, gap, columns,
amount font size and optional font. The customer's presentation bubble position
sets its `OrderAnchor` beside the head. Test both authored days and the notebook
at the supported viewport sizes after changing placement or sizing.

Real cup/portion handoff, payment and day-end progression remain separate
integrations. The earlier `CustomerScenePreview` opts out of the live queue and
retains its original single-cue sample presentation and motion controls.
