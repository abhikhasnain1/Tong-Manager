# Khata motion preview

Open `KhataPreview.tscn` in Godot 4.7 and press **F6** (Run Current Scene).

- Click the cover, or press Enter/Space, to open.
- Click or drag a lower page corner. Release a short drag to let the sheet return;
  drag farther across the spine to complete the turn.
- Use the left/right arrows or Stock/Notes/Ledger tabs to browse six sample pages.
- Escape/right-click cancels a held turn. Escape, Space or Close khata closes the book.
- Use Slow motion (S) to inspect the bend and reverse face. Sound (M) toggles the rustle.

This is a standalone visual study for review before the production Khata shell.
Its stock counts, notes, ledger, three sections and page arrangement are illustrative.
It does not implement inventory, recipes, transactions, world input blocking, export,
simulation pause policy or persistence. The normal gameplay scene is unchanged.

The supplied red cover and open-spread paper are reused as runtime texture regions.
Page content is rendered into six SubViewports, then mapped onto a bending sheet;
writing and icons turn with the paper. The cover label keeps its original proportions.
The current system serif font falls back when Georgia is unavailable. Typography,
sound mix, artwork, layout and motion timing remain provisional.

Run the rendered preview checks from the Godot project directory:

```sh
godot --path . --resolution 1280x800 --script res://tests/khata_motion_preview_test.gd
```

An optional directory after `--` receives screenshots. These checks cover opening,
page bounds, click/drag navigation, reverse turns, tab traversal, cancellation,
focus/resize interruption, close-during-turn and reopening. They are not acceptance
tests for the future inventory or Khata integration.
