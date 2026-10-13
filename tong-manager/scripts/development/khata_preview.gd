extends "res://scripts/ui/khata/khata_book.gd"
## Isolated visual study; sample pages never read or change production state.

const PreviewPage = preload("res://scripts/development/khata_preview_page.gd")


func _init() -> void:
	standalone = true
	section_titles = ["Stock", "Notes", "Ledger"]
	section_colors = [Color("91a878"), Color("bd916b"), Color("7994a1")]
	page_factory = _make_sample_page


func _make_sample_page(index: int, paper: Texture2D) -> Node:
	var page := PreviewPage.new()
	page.configure(index, paper)
	return page
