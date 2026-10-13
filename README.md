# Tong-Manager
A narrative-driven management simulation game about running a tong (tea stall) in urban Bangladesh.

This repository is public for visibility and development documentation only.

Open `tong-manager/project.godot` in Godot, then open `scenes/development/BrewingPreview.tscn` and press F6 to review placement and brewing together. Press G for Organize to move cups and ingredient containers freely between the table and tray; drag exposed tray space to carry its contents. The entire base must fit without overlapping another base. Green previews fit; red releases and Escape restore the original position.

Press U for Use: fill and use the kettle, hold Space to pour, drag cups to the sample customer or Discard area, or take individual ingredient and snack portions. Use releases on the table or tray return the cup to its original place. Click the selected mode again to return to Neutral. The six starting cups are a finite supply, not a tray capacity limit. Review controls, ingredient stock, customer targets and status markers are temporary fixtures; the bucket remains on hold.

For the integrated Khata review, open `scenes/development/InventoryPreview.tscn` and press F6. Click the closed notebook at the right of the stall, or press K. Switch sections with the bookmarks; click or drag anywhere along an outer page edge to turn, or use the arrow keys. Escape, K, the close button, or a click outside closes it. The stall keeps running while the notebook is open, including heating and steeping. Opening and closing preserves stock and vessel contents; the preview's separate Reload control still recreates empty vessels.

The Khata currently provides page shells for Pantry, Recipes, Finance and Quests. The blank pantry grid will receive its draggable inventory in #58; these pages do not yet offer stock, recipes, accounts or quest actions. `scenes/development/KhataPreview.tscn` remains the standalone animation study with sample pages.
