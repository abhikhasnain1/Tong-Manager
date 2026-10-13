# Tong-Manager
A narrative-driven management simulation game about running a tong (tea stall) in urban Bangladesh.

This repository is public for visibility and development documentation only.

Open `tong-manager/project.godot` in Godot, then open `scenes/development/BrewingPreview.tscn` and press F6 to review placement and brewing together. Press G for Organize to move cups and ingredient containers freely between the table and tray; drag exposed tray space to carry its contents. The entire base must fit without overlapping another base. Green previews fit; red releases and Escape restore the original position.

Press U for Use: fill and use the kettle, hold Space to pour, drag cups to the sample customer or Discard area, or take individual ingredient and snack portions. Use releases on the table or tray return the cup to its original place. Click the selected mode again to return to Neutral. The six starting cups are a finite supply, not a tray capacity limit. Review controls, ingredient stock, customer targets and status markers are temporary fixtures; the bucket remains on hold.

For the integrated Khata review, open `scenes/development/InventoryPreview.tscn` and press F6. Click the closed notebook at the right of the stall, or press K, to reveal a single pantry page. The stall remains usable outside this page, and it stays open while switching Organize/Use or working at the table. Choose **Open fully** for the full notebook, then **Pantry peek** to shrink it again. The full notebook owns input while reading; switch sections with its bookmarks, click or drag anywhere along an outer page edge, or use the arrow keys. Escape, K or Close puts the notebook away (Escape cancels a held gesture first); a click outside closes the full view only. Neither view pauses the stall: heating and steeping continue. Opening and closing preserves stock and vessel contents; the preview's separate Reload control still recreates empty vessels.

The Khata currently provides page shells for Pantry, Recipes, Finance and Quests. The blank pantry grid will receive its draggable inventory in #58; these pages do not yet offer stock, recipes, accounts or quest actions. `scenes/development/KhataPreview.tscn` remains the standalone animation study with sample pages.
