## Builds the UI widgets and places them for portrait (phones, designed for
## first) or landscape (desktop/tablet: board left, panel right). Every
## button is at least 48 UI units tall (~48 CSS px, see ScreenMetrics).
## The board's size comes from the encounter (configure): its columns and
## rows, and optionally a tile size in CSS px (the cellar's 48 px tiles; it
## shrinks only if a small screen can't fit it). With a party of one the
## hero tabs are hidden and the ability panel sits right under the board.
## Presentation only: no combat rules, no input decisions.
extends CanvasLayer

const BoardView = preload("res://scripts/view/board_view.gd")
const BoardInput = preload("res://scripts/view/board_input.gd")
const ScreenMetrics = preload("res://scripts/view/screen_metrics.gd")

const GAP := 6.0
const BTN_H := 48.0
const PANEL_PAD := 6.0
const PANEL_TITLE_H := 22.0
## The selected hero's panel: title ("Tide's abilities") above its ability buttons.
const PANEL_H := PANEL_PAD * 2 + PANEL_TITLE_H + BTN_H
const FONT := 15
const SMALL_FONT := 13

var root: Control
var top_row: HBoxContainer
var top_label: Label
var restart_btn: Button
var speed_btn: Button
var end_btn: Button
var board_input
var board
var hero_row: HBoxContainer
var hero_btns: Array = []
var ability_panel: Panel  # attached under the selected hero's tab
var ability_title: Label
var ability_row: HBoxContainer
var ability_btns: Array = []
var _panel_style: StyleBoxFlat
var action_row: HBoxContainer
var wait_btn: Button
var undo_btn: Button
var cancel_btn: Button
var info_btn: Button
var info_text: RichTextLabel
var over_layer: ColorRect
var over_label: Label
var over_btn: Button
var menu_btn: Button
var portrait: bool = true
var metrics: Dictionary = {}
var cols: int = 10  # board size in tiles
var rows: int = 10
var tile_css: float = 0.0  # wanted tile size in CSS px (0: as big as fits)
var solo: bool = false  # one hero: no hero tabs
var _laying_out := false


func _ready() -> void:
	_build()
	get_tree().root.size_changed.connect(relayout)
	relayout()


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = FONT
	root.theme = th
	add_child(root)

	top_row = _row()
	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.add_theme_font_size_override("font_size", 15)
	top_label.clip_text = true
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(top_label)
	restart_btn = _button(top_row, "Restart", false)
	restart_btn.custom_minimum_size.x = 80
	speed_btn = _button(top_row, "x1", false)
	speed_btn.custom_minimum_size.x = 52
	end_btn = _button(top_row, "End Turn", false)
	end_btn.custom_minimum_size.x = 100

	board_input = BoardInput.new()
	root.add_child(board_input)
	board = BoardView.new()
	board_input.add_child(board)

	hero_row = _row()
	for i in 3:
		var b := _button(hero_row, "", true)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL_FONT + 1)
		hero_btns.append(b)
	# Abilities live in one panel joined to the selected hero's tab, titled
	# with that hero's name, so they clearly belong to that hero.
	ability_panel = Panel.new()
	ability_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.set_border_width_all(2)
	_panel_style.set_corner_radius_all(8)
	ability_panel.add_theme_stylebox_override("panel", _panel_style)
	root.add_child(ability_panel)
	ability_title = Label.new()
	ability_title.add_theme_font_size_override("font_size", SMALL_FONT + 1)
	ability_title.clip_text = true
	ability_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ability_panel.add_child(ability_title)
	ability_row = HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", GAP)
	ability_panel.add_child(ability_row)
	for i in 3:
		var b := _button(ability_row, "", true)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL_FONT)
		ability_btns.append(b)
	action_row = _row()
	wait_btn = _button(action_row, "Wait", true)
	undo_btn = _button(action_row, "Undo", true)
	cancel_btn = _button(action_row, "Cancel", true)
	info_btn = _button(action_row, "Info", true)
	info_btn.toggle_mode = true

	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.scroll_active = true
	info_text.add_theme_font_size_override("normal_font_size", 14)
	info_text.add_theme_font_size_override("bold_font_size", 15)
	root.add_child(info_text)

	over_layer = ColorRect.new()
	over_layer.color = Color(0, 0, 0, 0.75)
	over_layer.visible = false
	root.add_child(over_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	over_label = Label.new()
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_font_size_override("font_size", 40)
	box.add_child(over_label)
	over_btn = Button.new()
	over_btn.text = "Play again"
	over_btn.custom_minimum_size = Vector2(200, 56)
	over_btn.add_theme_font_size_override("font_size", 20)
	over_btn.focus_mode = Control.FOCUS_NONE
	box.add_child(over_btn)
	menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.custom_minimum_size = Vector2(200, 56)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.focus_mode = Control.FOCUS_NONE
	box.add_child(menu_btn)


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", GAP)
	root.add_child(r)
	return r


func _button(parent: Control, text: String, expand: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56, BTN_H)
	b.clip_text = true
	if expand:
		b.custom_minimum_size.x = 0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)


## Sets the board's size in tiles, the wanted tile size in CSS px (0: as
## big as fits) and whether the party is one hero (no tabs), then lays out.
func configure(board_cols: int, board_rows: int, wanted_tile_css: float, one_hero: bool) -> void:
	cols = maxi(1, board_cols)
	rows = maxi(1, board_rows)
	tile_css = wanted_tile_css
	solo = one_hero
	hero_row.visible = not solo
	relayout()


## The tile size in UI units for a board that may be at most w x h units.
func _cell_for(w: float, h: float) -> float:
	var fit := minf(w / cols, h / rows)
	if tile_css > 0.0:
		return minf(fit, tile_css / float(metrics.get("css_per_unit", 1.0)))
	return floorf(fit)


func relayout() -> void:
	if _laying_out:
		return
	_laying_out = true
	metrics = ScreenMetrics.apply(get_tree().root)
	var size: Vector2 = metrics["size"]
	var ins: Array = metrics["insets"]  # top, right, bottom, left
	var area := Rect2(ins[3] + GAP, ins[0] + GAP, size.x - ins[1] - ins[3] - GAP * 2, size.y - ins[0] - ins[2] - GAP * 2)
	portrait = area.size.x < area.size.y * 1.15
	var rows_h := BTN_H * (2 if solo else 3) + PANEL_H + GAP * 3
	var cell: float
	if portrait:
		# Top bar, board (full width), heroes, abilities, actions, info.
		cell = _cell_for(area.size.x, area.size.y - rows_h - 64)
		var bw := cell * cols
		var bh := cell * rows
		var y := area.position.y
		_place(top_row, area.position.x, y, area.size.x, BTN_H)
		y += BTN_H + GAP
		_place(board_input, area.position.x + (area.size.x - bw) * 0.5, y, bw, bh)
		y += bh + GAP
		y = _place_hero_block(area.position.x, y, area.size.x)
		_place(action_row, area.position.x, y, area.size.x, BTN_H)
		y += BTN_H + GAP
		_place(info_text, area.position.x, y, area.size.x, maxf(40.0, area.end.y - y))
	else:
		# Board on the left at full height, everything else in a column.
		cell = _cell_for(area.size.x - 300.0, area.size.y)
		var bw := cell * cols
		var bh := cell * rows
		_place(board_input, area.position.x, area.position.y + (area.size.y - bh) * 0.5, bw, bh)
		var px := area.position.x + bw + GAP * 2
		var pw := area.end.x - px
		var y := area.position.y
		_place(top_row, px, y, pw, BTN_H)
		y += BTN_H + GAP
		y = _place_hero_block(px, y, pw)
		_place(action_row, px, y, pw, BTN_H)
		y += BTN_H + GAP
		_place(info_text, px, y, pw, maxf(40.0, area.end.y - y))
	board_input.cell_size = cell
	board.set_cell_size(cell)
	_place(over_layer, 0, 0, size.x, size.y)
	_laying_out = false


## Hero tabs with the selected hero's ability panel directly below (no gap,
## so the selected tab and the panel read as one piece). Returns the next y.
func _place_hero_block(x: float, y: float, w: float) -> float:
	if not solo:
		_place(hero_row, x, y, w, BTN_H)
		y += BTN_H
	_place(ability_panel, x, y, w, PANEL_H)
	_place(ability_title, PANEL_PAD + 4, PANEL_PAD, w - PANEL_PAD * 2 - 8, PANEL_TITLE_H)
	_place(ability_row, PANEL_PAD, PANEL_PAD + PANEL_TITLE_H, w - PANEL_PAD * 2, BTN_H)
	return y + PANEL_H + GAP


## Colours the hero tabs and the ability panel. `owner` is the selected
## hero's display name ("" when none); `colors` are the tab heroes' colours.
func show_ability_owner(owner: String, owner_color: Color, selected_slot: int, colors: Array) -> void:
	var has := owner != ""
	var c := owner_color if has else Color(0.45, 0.45, 0.5)
	_panel_style.bg_color = c.darkened(0.72)
	_panel_style.border_color = c
	# The selected tab's corner joins the panel (no tabs: round corners).
	_panel_style.corner_radius_top_left = 0 if has and selected_slot == 0 and not solo else 8
	_panel_style.corner_radius_top_right = 0 if has and selected_slot == hero_btns.size() - 1 and not solo else 8
	ability_title.text = ("%s's abilities" % owner) if has else "Select a hero to see their abilities"
	ability_title.add_theme_color_override("font_color", c.lightened(0.3))
	for i in hero_btns.size():
		var b: Button = hero_btns[i]
		var hc: Color = colors[i] if i < colors.size() else Color.GRAY
		var tab := StyleBoxFlat.new()
		tab.bg_color = hc.darkened(0.72)
		tab.border_color = hc
		tab.set_border_width_all(2)
		tab.border_width_bottom = 0
		tab.corner_radius_top_left = 8
		tab.corner_radius_top_right = 8
		tab.expand_margin_bottom = 2  # overlap the panel's top border
		b.add_theme_stylebox_override("pressed", tab)
		b.add_theme_stylebox_override("hover_pressed", tab)
	for b in ability_btns:
		b.add_theme_color_override("font_color", c.lightened(0.45))
