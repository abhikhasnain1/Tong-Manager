class_name KhataPreviewPage
extends Node2D

# Standalone page artwork for the turning-page study. Every entry is a sample;
# this node neither reads nor changes inventory, recipes, money or day state.
const PAGE_SIZE := Vector2(480, 660)
const INK := Color("493b30")
const SOFT_INK := Color("81705b")
const NOTE_INK := Color("725241")
const RULE := Color(0.37, 0.45, 0.47, 0.15)
const MARGIN_INK := Color(0.62, 0.34, 0.30, 0.18)
const ICON_PATHS := {
	&"tea": "res://assets/art/icons/tea_box_ready_provisional.png",
	&"milk": "res://assets/art/icons/condensed_milk_can_ready_provisional.png",
	&"sugar": "res://assets/art/icons/sugar_can_ready_provisional.png",
	&"banana": "res://assets/art/icons/banana_ready_provisional.png",
	&"biscuits": "res://assets/art/icons/biscuits_ready_provisional.png",
}

static var _icon_cache: Dictionary = {}
var page_index: int = 0
var paper_texture: Texture2D
var _font := SystemFont.new()
var _note_font := SystemFont.new()


func _init() -> void:
	_font.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "serif"])
	_font.font_weight = 400
	_font.fallbacks = [ThemeDB.fallback_font]
	_note_font.font_names = _font.font_names
	_note_font.font_italic = true
	_note_font.fallbacks = [ThemeDB.fallback_font]
	_cache_icons()


func configure(index: int, texture: Texture2D) -> void:
	page_index = clampi(index, 0, 5)
	paper_texture = texture
	queue_redraw()


func _cache_icons() -> void:
	if not _icon_cache.is_empty():
		return
	for key: StringName in ICON_PATHS:
		var texture := load(ICON_PATHS[key]) as Texture2D
		if texture == null:
			continue
		var pixels := texture.get_image()
		if pixels == null or pixels.is_empty():
			continue
		if pixels.is_compressed() and pixels.decompress() != OK:
			continue
		var used := pixels.get_used_rect()
		if not used.has_area():
			continue
		var cropped := AtlasTexture.new()
		cropped.atlas = texture
		cropped.region = Rect2(used)
		_icon_cache[key] = cropped


func _draw() -> void:
	# Paper must remain opaque on a lifted sheet, even if the source has alpha.
	draw_rect(Rect2(Vector2.ZERO, PAGE_SIZE), Color("f0e4c8"))
	if paper_texture != null:
		draw_texture_rect(paper_texture, Rect2(Vector2.ZERO, PAGE_SIZE), false)
	for y in range(162, 581, 30):
		draw_line(Vector2(44, y), Vector2(436, y), RULE, 1.0)
	draw_line(Vector2(44, 134), Vector2(44, 580), MARGIN_INK, 1.0)
	_text("SAMPLE CONTENTS  /  PAGE STUDY", Vector2(44, 55), 12, SOFT_INK)
	match clampi(page_index, 0, 5):
		0: _draw_pantry()
		1: _draw_ready_items()
		2: _draw_recipe_notes()
		3: _draw_preparation_notes()
		4: _draw_finance()
		5: _draw_day_notes()
	# Keep the lower-right 55px square empty for the page-corner fold.
	draw_string(_font, Vector2(220, 615), str(page_index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, SOFT_INK)


func _heading(title: String, subtitle: String) -> void:
	_text(title, Vector2(44, 99), 31)
	_text(subtitle, Vector2(45, 125), 16, SOFT_INK, true)
	draw_line(Vector2(44, 140), Vector2(436, 140), Color(0.38, 0.29, 0.20, 0.28), 1.0)


func _draw_pantry() -> void:
	_heading("Pantry", "A few familiar things for the stall")
	_stock_row(&"tea", "Tea", "teabags", "6", 183)
	_stock_row(&"milk", "Milk", "spoon portions", "12", 300)
	_stock_row(&"sugar", "Sugar", "spoon portions", "12", 417)
	_paragraph("Sample stock only. These numbers belong to the page study.", Vector2(58, 545), 350, 18, 25, true)


func _stock_row(icon: StringName, title: String, unit: String, amount: String, y: float) -> void:
	_icon(icon, Rect2(61, y - 23, 72, 84))
	_text(title, Vector2(155, y + 6), 24)
	_text(unit, Vector2(156, y + 34), 17, SOFT_INK, true)
	draw_string(_font, Vector2(363, y + 9), amount, HORIZONTAL_ALIGNMENT_RIGHT, 60, 28, INK)
	_text("sample", Vector2(371, y + 34), 12, SOFT_INK)
	draw_line(Vector2(154, y + 63), Vector2(428, y + 63), Color(0.40, 0.31, 0.23, 0.20), 1.0)


func _draw_ready_items() -> void:
	_heading("Ready to serve", "From the hanging bunches and bag")
	_icon(&"banana", Rect2(72, 164, 119, 126))
	_text("Bananas", Vector2(217, 210), 26)
	_text("6 pieces", Vector2(219, 241), 20)
	_text("sample count", Vector2(219, 268), 15, SOFT_INK, true)
	_icon(&"biscuits", Rect2(83, 324, 98, 148))
	_text("Biscuits", Vector2(217, 377), 26)
	_text("8 pieces", Vector2(219, 408), 20)
	_text("sample count", Vector2(219, 435), 15, SOFT_INK, true)
	_paragraph("Small things, close at hand.", Vector2(59, 521), 360, 21, 29, true)
	_paragraph("A visual stock list, with illustrative quantities.", Vector2(59, 554), 350, 17, 24, true)


func _draw_recipe_notes() -> void:
	_heading("Recipe notes", "A place to keep the familiar cups")
	_text("Plain black tea", Vector2(59, 186), 24)
	_paragraph("Tea, a kettle, a waiting cup.", Vector2(59, 218), 352, 20, 28, true)
	_text("Milk tea", Vector2(59, 303), 24)
	_paragraph("Leave room here for the milk notes.", Vector2(59, 335), 352, 20, 28, true)
	_text("Something sweet", Vector2(59, 422), 24)
	_paragraph("A note beside the sugar jar.", Vector2(59, 454), 352, 20, 28, true)
	_paragraph("Sample headings only. Ingredients, amounts and recipe rules are not specified here.", Vector2(59, 536), 354, 17, 24)


func _draw_preparation_notes() -> void:
	_heading("At the stove", "An opening-page reminder")
	_note_entry("Water for the morning", "A little space to jot down the day's starting supplies.", 181)
	_note_entry("Cups within reach", "Keep the working table easy to arrange.", 300)
	_note_entry("Watch the kettle", "Room for a short note beside the brewing routine.", 419)
	_text("Sample preparation notes", Vector2(60, 568), 18, SOFT_INK, true)


func _note_entry(title: String, note: String, y: float) -> void:
	draw_rect(Rect2(59, y - 15, 13, 13), Color(0.35, 0.29, 0.23, 0.65), false, 1.0)
	_text(title, Vector2(86, y), 22)
	_paragraph(note, Vector2(86, y + 32), 333, 19, 27, true)


func _draw_finance() -> void:
	_heading("Day's accounts", "Illustrative ledger · values in taka")
	_text("Entry", Vector2(59, 184), 18, SOFT_INK)
	_right_text("In", 319, 184, 18, SOFT_INK)
	_right_text("Out", 424, 184, 18, SOFT_INK)
	draw_line(Vector2(58, 197), Vector2(430, 197), Color(0.39, 0.31, 0.23, 0.32), 1.0)
	draw_line(Vector2(270, 166), Vector2(270, 480), RULE, 1.0)
	draw_line(Vector2(346, 166), Vector2(346, 480), RULE, 1.0)
	_ledger_row("Opening cash", "100", "—", 234)
	_ledger_row("Supplies", "—", "20", 284)
	_ledger_row("Tea sales", "30", "—", 334)
	_ledger_row("Ready items", "10", "—", 384)
	draw_line(Vector2(58, 418), Vector2(430, 418), Color(0.39, 0.31, 0.23, 0.45), 1.0)
	_text("Balance", Vector2(59, 458), 24)
	_right_text("120", 424, 458, 27)
	_paragraph("Sample entries for the ledger layout. No sales or payments are recorded by this preview.", Vector2(59, 536), 356, 18, 25, true)


func _ledger_row(title: String, incoming: String, outgoing: String, y: float) -> void:
	_text(title, Vector2(59, y), 20)
	_right_text(incoming, 319, y, 21)
	_right_text(outgoing, 424, y, 21)


func _draw_day_notes() -> void:
	_heading("Notes for tomorrow", "The little things worth remembering")
	_paragraph("The first cups went quickly.", Vector2(59, 194), 360, 22, 30, true)
	_paragraph("Keep the tea box near the tray.", Vector2(59, 283), 360, 22, 30, true)
	_paragraph("Ask about the next delivery.", Vector2(59, 373), 360, 22, 30, true)
	_paragraph("Leave a little room to move things around.", Vector2(59, 463), 354, 22, 30, true)
	_text("Sample notes · no saved day history", Vector2(59, 568), 17, SOFT_INK)


func _icon(key: StringName, bounds: Rect2) -> void:
	var texture := _icon_cache.get(key) as Texture2D
	if texture == null:
		return
	var factor := minf(bounds.size.x / texture.get_width(), bounds.size.y / texture.get_height())
	var dimensions := texture.get_size() * factor
	draw_texture_rect(texture, Rect2(bounds.position + (bounds.size - dimensions) * 0.5, dimensions), false, Color(1, 1, 1, 0.94))


func _text(text: String, at: Vector2, size: int = 20, color: Color = INK, handwritten: bool = false) -> void:
	draw_string(_note_font if handwritten else _font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _right_text(text: String, right: float, y: float, size: int = 20, color: Color = INK) -> void:
	draw_string(_font, Vector2(right - 67, y), text, HORIZONTAL_ALIGNMENT_RIGHT, 67, size, color)


func _paragraph(text: String, at: Vector2, width: float, size: int, line_height: float, handwritten: bool = false) -> void:
	var font: Font = _note_font if handwritten else _font
	var line := ""
	var baseline := at
	for word in text.split(" "):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			_text(line, baseline, size, NOTE_INK if handwritten else SOFT_INK, handwritten)
			baseline.y += line_height
			line = word
		else:
			line = candidate
	if not line.is_empty():
		_text(line, baseline, size, NOTE_INK if handwritten else SOFT_INK, handwritten)
