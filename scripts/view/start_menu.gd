## Start screen: "Town" (the walkable slice) and "Fight" (the fight on its own,
## for testing). Presentation only; the app decides what each button does.
extends CanvasLayer

signal town_pressed
signal fight_pressed

const ScreenMetrics = preload("res://scripts/view/screen_metrics.gd")

var town_btn: Button
var fight_btn: Button


func _ready() -> void:
	ScreenMetrics.apply(get_tree().root)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Label.new()
	title.text = str(ProjectSettings.get_setting("application/config/name", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	town_btn = _button(box, "Town")
	town_btn.pressed.connect(func(): town_pressed.emit())
	fight_btn = _button(box, "Fight")
	fight_btn.pressed.connect(func(): fight_pressed.emit())
	get_tree().root.size_changed.connect(_on_resize)


func _on_resize() -> void:
	ScreenMetrics.apply(get_tree().root)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220, 56)
	b.add_theme_font_size_override("font_size", 20)
	parent.add_child(b)
	return b
