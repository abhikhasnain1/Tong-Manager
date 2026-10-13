extends Control

# Presentation shells only. Stock export, ledger and other page content have
# separate owners; these pages never mutate the run or invent sample balances.
const INK := Color("493d30")
const SOFT_INK := Color("85735d")
var page_index := 0
var paper: Texture2D
var _font: Font = ThemeDB.fallback_font
var _title_font := SystemFont.new()


func configure(index: int, texture: Texture2D) -> void:
	page_index = index
	paper = texture
	size = Vector2(480, 660)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_font.font_names = PackedStringArray(["Georgia", "Noto Serif", "serif"])
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 660), Color("f0e4c8"))
	if paper != null:
		draw_texture_rect(paper, Rect2(0, 0, 480, 660), false)
	var section := page_index / 2
	var right := page_index % 2 == 1
	var titles := [["Pantry", "Ready to serve"], ["Recipes", "Preparation notes"],
		["Day's accounts", "The ledger"], ["Requests", "Notes to keep"]]
	draw_string(_font, Vector2(44, 55), "TONG KHATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SOFT_INK)
	draw_string(_title_font, Vector2(44, 108), titles[section][1 if right else 0], HORIZONTAL_ALIGNMENT_LEFT, -1, 29, INK)
	draw_line(Vector2(44, 137), Vector2(436, 137), Color(0.38, 0.29, 0.20, 0.28), 1)
	if section == 0:
		# The agreed grid is a page layout, never a return to table slots.
		for row in range(3):
			for column in range(3):
				draw_rect(Rect2(49 + column * 130, 172 + row * 126, 121, 116), Color(0.40, 0.31, 0.23, 0.16), false, 1)
	else:
		for y in range(185, 581, 30):
			draw_line(Vector2(44, y), Vector2(436, y), Color(0.35, 0.27, 0.20, 0.15), 1)
		if section == 2:
			draw_string(_font, Vector2(52, 174), "Entry", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, SOFT_INK)
			draw_string(_font, Vector2(285, 174), "In", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, SOFT_INK)
			draw_string(_font, Vector2(382, 174), "Out", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, SOFT_INK)
			draw_line(Vector2(266, 152), Vector2(266, 575), Color(0.35, 0.27, 0.20, 0.15), 1)
			draw_line(Vector2(353, 152), Vector2(353, 575), Color(0.35, 0.27, 0.20, 0.15), 1)
	draw_string(_font, Vector2(220, 615), str(page_index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, SOFT_INK)
