## Reusable dialogue box: portrait, speaker name, text that types out over
## time, and an advance button. It shows whatever a Dialogue runner (data)
## says. One tap (anywhere on screen, or the button) finishes typing the line;
## the next tap advances. Emits `closed` after the last line.
## When the line just left has a "then" step (a fade, a card, a world object
## fading), the box holds still and emits `step_requested`; whoever shows the
## step calls resume() to carry on with the next line (or close).
## Phone first: sits at the bottom inside the safe area; the button is at
## least 48 UI units (~48 CSS px); long text wraps and scrolls, never spills.
extends Control

signal closed
signal step_requested(step: Dictionary)

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")

const PAD := 10.0
const BTN := Vector2(96, 52)
const PORTRAIT := 76.0
const MAX_W := 720.0
const BOX_H := 200.0

var runner  # Dialogue (scripts/core/dialogue.gd)
var chars_per_sec: float = 45.0
var panel: Panel
var portrait_tex: TextureRect
var portrait_box: ColorRect
var portrait_label: Label
var portrait_initial: Label
var name_label: Label
var text: RichTextLabel
var next_btn: Button
var _shown: float = 0.0  # characters revealed so far
var busy := false  # a step is playing: taps wait
var _more := false  # a line follows the step


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # eats taps so the town ignores them
	panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.94)
	sb.border_color = Color("#e8d9a8")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	portrait_box = ColorRect.new()
	portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait_box)
	# Placeholder portrait: the speaker's initial (or a short name like
	# "???" in full), large, with the name below.
	portrait_initial = Label.new()
	portrait_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_initial.offset_bottom = -16
	portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_initial.add_theme_font_size_override("font_size", 40)
	portrait_initial.add_theme_color_override("font_color", Color.WHITE)
	portrait_initial.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	portrait_initial.add_theme_constant_override("outline_size", 4)
	portrait_box.add_child(portrait_initial)
	portrait_label = Label.new()
	portrait_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_label.offset_bottom = -3
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	portrait_label.clip_text = true
	portrait_label.add_theme_font_size_override("font_size", 12)
	portrait_label.add_theme_color_override("font_color", Color.WHITE)
	portrait_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	portrait_label.add_theme_constant_override("outline_size", 3)
	portrait_box.add_child(portrait_label)
	portrait_tex = TextureRect.new()
	portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait_tex)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.clip_text = true
	panel.add_child(name_label)

	text = RichTextLabel.new()
	text.bbcode_enabled = false
	text.scroll_active = true
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("normal_font_size", 17)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)

	next_btn = Button.new()
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.add_theme_font_size_override("font_size", 16)
	next_btn.pressed.connect(tap)
	panel.add_child(next_btn)


## Lays the box out for a screen of `size` UI units with safe-area `insets`
## [top, right, bottom, left].
func layout(size: Vector2, insets: Array) -> void:
	position = Vector2.ZERO
	self.size = size
	var avail_w: float = size.x - insets[1] - insets[3] - PAD * 2
	var w := minf(avail_w, MAX_W)
	var x: float = insets[3] + PAD + (avail_w - w) * 0.5
	var y: float = size.y - insets[2] - PAD - BOX_H
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, BOX_H)
	portrait_box.position = Vector2(PAD, PAD)
	portrait_box.size = Vector2(PORTRAIT, PORTRAIT)
	portrait_tex.position = portrait_box.position
	portrait_tex.size = portrait_box.size
	var tx := PAD * 2 + PORTRAIT
	name_label.position = Vector2(tx, PAD - 2)
	name_label.size = Vector2(w - tx - PAD, 26)
	text.position = Vector2(tx, PAD + 26)
	text.size = Vector2(w - tx - PAD, BOX_H - PAD * 3 - 26 - BTN.y + 6)
	next_btn.position = Vector2(w - PAD - BTN.x, BOX_H - PAD - BTN.y)
	next_btn.size = BTN


## Top edge of the box in UI units (the camera keeps the player above it).
func top() -> float:
	return panel.position.y


## Shows the runner's current line. The runner must already be started.
func open(dialogue_runner, speed: float = 45.0) -> void:
	runner = dialogue_runner
	busy = false
	next_btn.disabled = false
	chars_per_sec = speed
	visible = true
	_show_line()


func is_open() -> bool:
	return visible


func is_typing() -> bool:
	return visible and text.visible_characters >= 0 and text.visible_characters < text.get_total_character_count()


## The single input: finish typing, else advance (and close after the last line).
func tap() -> void:
	if not visible or busy:
		return
	if is_typing():
		text.visible_characters = -1
		_update_button()
		return
	var more: bool = runner.advance()
	var step: Dictionary = runner.take_step()
	if not step.is_empty():
		busy = true
		_more = more
		next_btn.disabled = true
		step_requested.emit(step)
		return
	_carry_on(more)


## After a step: shows the next line, or closes if the entry is over.
func resume() -> void:
	if not busy:
		return
	busy = false
	next_btn.disabled = false
	_carry_on(_more)


func _carry_on(more: bool) -> void:
	if more:
		_show_line()
	else:
		visible = false
		closed.emit()


func _show_line() -> void:
	var l: Dictionary = runner.line()
	name_label.text = l["name"]
	name_label.add_theme_color_override("font_color", Color(l["color"]).lightened(0.35))
	text.text = l["text"]
	text.scroll_to_line(0)
	_shown = 0.0
	text.visible_characters = 0 if chars_per_sec > 0.0 else -1
	var tex: Texture2D = AssetCatalog.try_texture(l["portrait"])
	portrait_tex.texture = tex
	portrait_tex.visible = tex != null
	# Placeholder portrait: the speaker's colour with their name on it.
	portrait_box.color = Color(l["color"])
	portrait_label.text = l["name"]
	portrait_initial.text = l["initials"]
	portrait_box.visible = tex == null
	_update_button()


## Labels come from data: the line's own "button" (e.g. "Insert coin"), else
## the Next / Close defaults; "Skip" while the line is still typing.
func _update_button() -> void:
	next_btn.text = Dialogue.default_button("skip") if is_typing() else str(runner.line().get("button", ""))


func _process(delta: float) -> void:
	if is_typing():
		_shown += delta * chars_per_sec
		text.visible_characters = mini(int(_shown), text.get_total_character_count())
		if not is_typing():
			text.visible_characters = -1
			_update_button()


func _gui_input(event: InputEvent) -> void:
	# A tap anywhere (inside or outside the box) counts, on release.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		accept_event()
		tap()
