## Builds the UI widgets and places them for portrait (phones, designed for
## first) or landscape (desktop/tablet: board left, panel right). Every
## button is at least 48 UI units tall (~48 CSS px, see ScreenMetrics).
## Presentation only: no combat rules, no input decisions.
extends CanvasLayer

const BoardView = preload("res://scripts/view/board_view.gd")
const BoardInput = preload("res://scripts/view/board_input.gd")
const ScreenMetrics = preload("res://scripts/view/screen_metrics.gd")

const GAP := 6.0
const BTN_H := 48.0
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
var ability_row: HBoxContainer
var ability_btns: Array = []
var action_row: HBoxContainer
var wait_btn: Button
var undo_btn: Button
var cancel_btn: Button
var info_btn: Button
var info_text: RichTextLabel
var over_layer: ColorRect
var over_label: Label
var over_btn: Button
var portrait: bool = true
var metrics: Dictionary = {}
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
	ability_row = _row()
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


func relayout() -> void:
	if _laying_out:
		return
	_laying_out = true
	metrics = ScreenMetrics.apply(get_tree().root)
	var size: Vector2 = metrics["size"]
	var ins: Array = metrics["insets"]  # top, right, bottom, left
	var area := Rect2(ins[3] + GAP, ins[0] + GAP, size.x - ins[1] - ins[3] - GAP * 2, size.y - ins[0] - ins[2] - GAP * 2)
	portrait = area.size.x < area.size.y * 1.15
	var rows_h := BTN_H * 4 + GAP * 4
	var bs: float
	if portrait:
		# Top bar, board (full width), heroes, abilities, actions, info.
		bs = minf(area.size.x, area.size.y - rows_h - 64)
		var cell := floorf(bs / 10.0)
		bs = cell * 10.0
		var y := area.position.y
		_place(top_row, area.position.x, y, area.size.x, BTN_H)
		y += BTN_H + GAP
		_place(board_input, area.position.x + (area.size.x - bs) * 0.5, y, bs, bs)
		y += bs + GAP
		for r in [hero_row, ability_row, action_row]:
			_place(r, area.position.x, y, area.size.x, BTN_H)
			y += BTN_H + GAP
		_place(info_text, area.position.x, y, area.size.x, maxf(40.0, area.end.y - y))
	else:
		# Board on the left at full height, everything else in a column.
		bs = minf(area.size.y, area.size.x - 300.0)
		var cell := floorf(bs / 10.0)
		bs = cell * 10.0
		_place(board_input, area.position.x, area.position.y + (area.size.y - bs) * 0.5, bs, bs)
		var px := area.position.x + bs + GAP * 2
		var pw := area.end.x - px
		var y := area.position.y
		for r in [top_row, hero_row, ability_row, action_row]:
			_place(r, px, y, pw, BTN_H)
			y += BTN_H + GAP
		_place(info_text, px, y, pw, maxf(40.0, area.end.y - y))
	board_input.cell_size = bs / 10.0
	board.set_cell_size(bs / 10.0)
	_place(over_layer, 0, 0, size.x, size.y)
	_laying_out = false
