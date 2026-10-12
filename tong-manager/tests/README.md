# Brewing verification

Run from the `tong-manager` project directory with Godot 4.7 on PATH:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/brewing_contract_test.gd
godot --path . --resolution 1920x1080 --script res://tests/brewing_input_test.gd
```

The contract suite checks conserved volume, capacity, brewing states, independent
burners, drag cancellation and disappearing targets. The input suite requires a
window and sends viewport mouse events through physics picking and actual Space
key events through input handling. It checks grip anchoring, spout-based targeting
of all six cups, stable held pose and burner seating. It exits after verification.

To try the loop, open `scenes/development/BrewingPreview.tscn` in Godot and press
F6, or run:

```sh
godot --path . res://scenes/development/BrewingPreview.tscn
```

The preview seeds 750 ml of water. Click the left dial to cycle Off, Low, Medium,
High. When water boils, click Add tea leaves, then wait for Tea ready. Drag the
kettle by its grip so the spout aims above a cup, hold Space to pour, and release
Space to stop. The hand cursor remains on the kettle, clear of the cup. Releasing the
mouse returns the kettle; releasing over a burner seats it there. Escape or
right-click cancels. G toggles the existing interaction mode.

The normal service scene starts with an empty kettle. Water-source and inventory
connections are separate follow-up work. Preview supplies never change inventory.
Temporary lid/dial art and procedural steam/flames still need visual acceptance.
