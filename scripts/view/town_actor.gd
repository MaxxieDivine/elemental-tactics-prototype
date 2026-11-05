## One thing in the town that is depth-sorted with the others: the player, an
## NPC, an object or a prop. Its position is its feet (bottom centre of its
## tile), so a y-sorted parent draws whoever is lower on screen in front.
## Draws its sprite (by asset key) or a simple placeholder. Presentation only.
##
## Character sprite sheets: one row of 4 equal frames facing down, left,
## right, up. Object/prop sprites: one image, drawn standing on the tile.
extends Node2D

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")

const FRAMES := ["down", "left", "right", "up"]
const SKIN := Color("#f1c9a5")
const INK := Color("#1d1b24")

var id: String = ""
var kind: String = "object"  # "character", "object" or "prop"
var shape: String = ""  # placeholder shape for objects/props
var color: Color = Color.WHITE
var facing: String = "down":
	set(v):
		if v != "" and v != facing:
			facing = v
			queue_redraw()
var tex: Texture2D


func setup(key: String) -> void:
	tex = AssetCatalog.try_texture(key) if key != "" else null
	queue_redraw()


func _draw() -> void:
	draw_ellipse_shadow()
	if tex != null:
		_draw_texture()
	elif kind == "character":
		_draw_character()
	else:
		_draw_object()


func draw_ellipse_shadow() -> void:
	if shape == "hatch":
		return
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a) * 6.0, -1.0 + sin(a) * 2.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28))


func _draw_texture() -> void:
	var size := tex.get_size()
	var src := Rect2(Vector2.ZERO, size)
	if kind == "character":
		var fw := size.x / 4.0
		src = Rect2(fw * maxi(0, FRAMES.find(facing)), 0, fw, size.y)
	draw_texture_rect_region(tex, Rect2(-src.size.x * 0.5, -src.size.y, src.size.x, src.size.y), src)


func _draw_character() -> void:
	# Body, head and a facing cue: eyes, plus a small arrow at the feet.
	var dark := color.darkened(0.35)
	draw_rect(Rect2(-4, -4, 3, 3), dark)  # legs
	draw_rect(Rect2(1, -4, 3, 3), dark)
	draw_rect(Rect2(-5, -13, 10, 10), color)  # body
	draw_rect(Rect2(-5, -13, 10, 2), color.lightened(0.2))
	draw_rect(Rect2(-4, -21, 8, 8), SKIN)  # head
	draw_rect(Rect2(-4, -22, 8, 3), dark)  # hair
	match facing:
		"down":
			draw_rect(Rect2(-3, -18, 1, 2), INK)
			draw_rect(Rect2(2, -18, 1, 2), INK)
		"left":
			draw_rect(Rect2(-4, -18, 1, 2), INK)
			draw_rect(Rect2(1, -22, 3, 6), dark)
		"right":
			draw_rect(Rect2(3, -18, 1, 2), INK)
			draw_rect(Rect2(-4, -22, 3, 6), dark)
		"up":
			draw_rect(Rect2(-4, -22, 8, 6), dark)
	var d: Vector2 = {"down": Vector2(0, 1), "up": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}.get(facing, Vector2(0, 1))
	var tip := Vector2(0, -1) + d * 8.0
	var side := Vector2(-d.y, d.x) * 2.5
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 3.0 + side, tip - d * 3.0 - side]), Color(1, 1, 1, 0.85))


func _draw_object() -> void:
	var dark := color.darkened(0.35)
	match shape:
		"banner":
			draw_rect(Rect2(-7, -26, 2, 26), Color("#5e3c22"))  # posts
			draw_rect(Rect2(5, -26, 2, 26), Color("#5e3c22"))
			draw_rect(Rect2(-6, -24, 12, 9), color)  # cloth
			draw_rect(Rect2(-6, -16, 12, 1), dark)
			for x in [-4, -1, 2]:
				draw_rect(Rect2(x, -21, 2, 2), Color("#f6d55c"))
		"letter":
			draw_rect(Rect2(-6, -9, 12, 9), Color("#a0723f"))  # crate
			draw_rect(Rect2(-6, -9, 12, 1), Color("#c08a50"))
			draw_rect(Rect2(-6, -5, 12, 1), Color("#7a5530"))
			draw_rect(Rect2(-4, -13, 8, 5), color)  # envelope
			draw_line(Vector2(-4, -13), Vector2(0, -10), INK, 1.0)
			draw_line(Vector2(4, -13), Vector2(0, -10), INK, 1.0)
			draw_rect(Rect2(-1, -11, 2, 2), Color("#c0392b"))  # seal
		"hatch":
			draw_rect(Rect2(-7, -14, 14, 13), dark)
			draw_rect(Rect2(-6, -13, 12, 11), color)
			draw_rect(Rect2(-6, -8, 12, 1), dark)
			draw_rect(Rect2(-1, -13, 1, 11), dark)
			draw_rect(Rect2(2, -9, 2, 3), Color("#c9c3b5"))  # ring
		"tree":
			draw_rect(Rect2(-2, -9, 4, 9), Color("#6b4a2b"))
			draw_circle(Vector2(0, -16), 8.0, color)
			draw_circle(Vector2(-3, -19), 4.0, color.lightened(0.15))
		"lamp":
			draw_rect(Rect2(-1, -22, 2, 22), color)
			draw_rect(Rect2(-3, -27, 6, 6), Color("#f6d55c"))
			draw_rect(Rect2(-3, -27, 6, 1), color)
		"crate":
			draw_rect(Rect2(-6, -11, 12, 11), color)
			draw_rect(Rect2(-6, -11, 12, 1), color.lightened(0.2))
			draw_line(Vector2(-6, -11), Vector2(6, 0), dark, 1.0)
			draw_line(Vector2(6, -11), Vector2(-6, 0), dark, 1.0)
		_:
			# Unknown shape: the loud placeholder.
			draw_texture(AssetCatalog.placeholder(), Vector2(-8, -16))
