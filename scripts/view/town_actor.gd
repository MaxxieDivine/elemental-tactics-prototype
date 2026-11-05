## One thing in the town that is depth-sorted with the others: the player, an
## NPC, an object or a prop. Its position is its feet (bottom centre of its
## tile), so a y-sorted parent draws whoever is lower on screen in front.
## Draws its sprite (by asset key) or a simple placeholder. Presentation only.
##
## Character sprite sheets: one row of 4 equal frames facing down, left,
## right, up. Object/prop sprites: one image, drawn standing on the tile.
## Things on a wall tile (lanterns, the key board, the fireplace) stand on
## the wall's bottom edge. Some placeholder shapes loop a small animation
## (the arcade screen, the fire, the humming hatch).
##
## A character can show a mood mark above the head (a map NPC's "mood", e.g.
## "upset"): the art key "mood.<name>" if that file exists, else a drawn
## placeholder that bobs so it catches the eye.
extends Node2D

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")

const FRAMES := ["down", "left", "right", "up"]
const SKIN := Color("#f1c9a5")
const INK := Color("#1d1b24")
## Placeholder shapes that loop a small animation.
const ANIMATED := ["hatch", "arcade", "fireplace", "door_light", "lantern"]
## Shapes drawn without a ground shadow (on walls, flat, or invisible).
const NO_SHADOW := ["hatch", "none", "lantern", "key_board", "fireplace", "door_reserved", "door_light", "door_name"]
## Moods with a drawn placeholder mark (others show the generic one).
const MOODS := ["upset"]
const ANIM_FPS := 12.0

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
var mood: String = ""  # "" for none; set before setup()
var mood_tex: Texture2D
var t: float = 0.0  # animation clock
var _since_draw: float = 0.0


func setup(key: String) -> void:
	tex = AssetCatalog.try_texture(key) if key != "" else null
	mood_tex = AssetCatalog.try_texture("mood." + mood) if mood != "" else null
	set_process((tex == null and ANIMATED.has(shape)) or mood != "")
	queue_redraw()


## True while a mood mark is showing above this actor.
func shows_mood() -> bool:
	return mood != ""


func _process(delta: float) -> void:
	t += delta
	_since_draw += delta
	if _since_draw >= 1.0 / ANIM_FPS:
		_since_draw = 0.0
		queue_redraw()


func _draw() -> void:
	draw_ellipse_shadow()
	if tex != null:
		_draw_texture()
	elif kind == "character":
		_draw_character()
	else:
		_draw_object()
	if mood != "":
		_draw_mood()


## The mood mark above the head: art if it exists, else a red "!" with
## little anger ticks, hopping every second so it reads at a glance.
func _draw_mood() -> void:
	var hop := -2.0 * _pulse(0.9)
	var top := (-tex.get_size().y if tex != null else -22.0) - 4.0 + hop
	if mood_tex != null:
		var sz := mood_tex.get_size()
		draw_texture(mood_tex, Vector2(-sz.x * 0.5, top - sz.y))
		return
	var red := Color("#e8403a") if mood == "upset" else Color("#f6d55c")
	draw_rect(Rect2(-3, top - 10, 6, 10), INK)  # outlined bubble
	draw_rect(Rect2(-2, top - 9, 4, 8), Color.WHITE)
	draw_rect(Rect2(-1, top - 8, 2, 4), red)  # "!"
	draw_rect(Rect2(-1, top - 3, 2, 1), red)
	if MOODS.has(mood):
		var flick := 1.0 if fmod(t, 0.6) < 0.3 else 0.0
		for side in [-1.0, 1.0]:  # anger ticks either side, flickering
			draw_line(Vector2(side * 5, top - 8 - flick), Vector2(side * 7, top - 10 - flick), red, 1.0)
			draw_line(Vector2(side * 5, top - 5), Vector2(side * 8, top - 5), red, 1.0)


func draw_ellipse_shadow() -> void:
	if NO_SHADOW.has(shape):
		return
	_ellipse(Vector2(0, -1), Vector2(6, 2), Color(0, 0, 0, 0.28))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


## 0..1..0 over `period` seconds.
func _pulse(period: float, offset: float = 0.0) -> float:
	return 0.5 - 0.5 * cos(TAU * fmod(t / period + offset, 1.0))


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
			_draw_hatch()
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
		"none":
			pass  # an invisible blocker (e.g. the head end of the bed)
		"arcade":
			_draw_arcade()
		"fireplace":
			_draw_fireplace()
		"lantern":
			var glow := 0.16 + 0.05 * _pulse(1.7)
			draw_circle(Vector2(0, -9), 7.0, Color(1.0, 0.8, 0.4, glow))
			draw_line(Vector2(0, -15), Vector2(0, -12), Color("#3b2a20"), 1.0)
			draw_rect(Rect2(-3, -12, 6, 1), Color("#3b2a20"))
			draw_rect(Rect2(-2, -11, 4, 5), color)
			draw_rect(Rect2(-1, -10, 2, 3), Color("#fff1c2"))
			draw_rect(Rect2(-3, -6, 6, 1), Color("#3b2a20"))
		"flowers":
			draw_rect(Rect2(-3, -6, 6, 6), Color("#7a4a2a"))  # little stand
			draw_rect(Rect2(-3, -6, 6, 1), Color("#a8693f"))
			draw_rect(Rect2(-2, -10, 4, 4), Color("#dfe8f0"))  # vase
			draw_rect(Rect2(-2, -10, 1, 4), Color.WHITE)
			draw_line(Vector2(0, -10), Vector2(-2, -14), Color("#3f8a3a"), 1.0)
			draw_line(Vector2(0, -10), Vector2(2, -15), Color("#3f8a3a"), 1.0)
			for p in [Vector2(-3, -15), Vector2(1, -16), Vector2(-1, -13), Vector2(3, -14)]:
				draw_rect(Rect2(p, Vector2(2, 2)), color)
			draw_rect(Rect2(0, -16, 1, 1), Color("#fff6d0"))
		"desk", "desk_book":
			draw_rect(Rect2(-8, -12, 16, 12), color)  # mahogany front desk
			draw_rect(Rect2(-8, -12, 16, 2), color.lightened(0.35))  # polished top
			draw_rect(Rect2(-8, -10, 16, 1), color.darkened(0.3))
			draw_rect(Rect2(-6, -8, 5, 6), color.lightened(0.08))  # panels
			draw_rect(Rect2(1, -8, 5, 6), color.lightened(0.08))
			draw_rect(Rect2(-8, -1, 16, 1), color.darkened(0.4))
			if shape == "desk_book":
				draw_rect(Rect2(-6, -16, 12, 5), Color("#5e2a1e"))  # open guest book
				draw_rect(Rect2(-5, -16, 5, 4), Color("#f4efe1"))
				draw_rect(Rect2(0, -16, 5, 4), Color("#ece4cf"))
				for y in [-15, -13]:
					draw_rect(Rect2(-4, y, 3, 1), Color("#5b5f8a"))
					draw_rect(Rect2(1, y, 3, 1), Color("#5b5f8a"))
				draw_line(Vector2(5, -18), Vector2(3, -14), INK, 1.0)  # pen
		"key_board":
			draw_rect(Rect2(-6, -14, 12, 10), color.darkened(0.3))
			draw_rect(Rect2(-5, -13, 10, 8), color)
			for i in 3:
				var x := -4 + i * 3
				draw_rect(Rect2(x, -12, 1, 1), Color("#c9c3b5"))  # hooks
				if i < 2:  # keys for Rooms 2 and 3; Room 4's hook is empty
					draw_rect(Rect2(x, -11, 1, 3), Color("#e0b44a"))
					draw_rect(Rect2(x - 1, -8, 3, 2), Color("#e0b44a"))
		"armchair":
			var dk := color.darkened(0.3)
			draw_rect(Rect2(-6, -14, 12, 7), dk)  # back
			draw_rect(Rect2(-5, -13, 10, 5), color)
			draw_rect(Rect2(-7, -9, 3, 7), dk)  # arms
			draw_rect(Rect2(4, -9, 3, 7), dk)
			draw_rect(Rect2(-4, -8, 8, 5), color.lightened(0.12))  # seat
			draw_rect(Rect2(-6, -2, 1, 2), Color("#3b2a20"))
			draw_rect(Rect2(5, -2, 1, 2), Color("#3b2a20"))
		"side_table":
			draw_rect(Rect2(-4, -9, 8, 2), Color("#8a4a2a"))
			draw_rect(Rect2(-1, -7, 2, 7), Color("#6b3a20"))
			draw_rect(Rect2(-2, -13, 4, 4), Color("#dfe8f0"))
			for p in [Vector2(-3, -16), Vector2(0, -17), Vector2(2, -15)]:
				draw_rect(Rect2(p, Vector2(2, 2)), color)
		"door_reserved":
			draw_line(Vector2(3, -9), Vector2(1, -6), Color("#c9c3b5"), 1.0)  # string
			draw_line(Vector2(3, -9), Vector2(6, -6), Color("#c9c3b5"), 1.0)
			draw_rect(Rect2(0, -6, 7, 4), color)  # "Reserved" card
			draw_rect(Rect2(1, -5, 5, 1), Color("#c0392b"))
			draw_rect(Rect2(1, -3, 4, 1), Color("#8d8577"))
		"door_name":
			# The Reserved card is gone; a name card with smudged wet ink.
			draw_rect(Rect2(0, -7, 7, 4), color)
			draw_rect(Rect2(0, -7, 7, 1), color.darkened(0.15))
			draw_rect(Rect2(1, -5, 5, 1), Color("#3a4f9a"))
			draw_rect(Rect2(2, -4, 3, 1), Color(0.23, 0.31, 0.6, 0.55))  # running ink
			draw_rect(Rect2(4, -3, 1, 2), Color(0.23, 0.31, 0.6, 0.4))
		"door_light":
			var a := 0.55 + 0.3 * _pulse(2.6)
			draw_rect(Rect2(-5, -1, 10, 1), Color(color, a))  # light under the door
			draw_colored_polygon(PackedVector2Array([Vector2(-5, 0), Vector2(5, 0), Vector2(7, 5), Vector2(-7, 5)]), Color(color, a * 0.3))
		"bed":
			var wood := Color("#6b3f24")
			draw_rect(Rect2(-7, -31, 14, 31), wood)  # frame, two tiles long
			draw_rect(Rect2(-7, -31, 14, 3), wood.lightened(0.25))  # headboard
			draw_rect(Rect2(-6, -28, 12, 26), Color("#f4efe1"))  # sheet
			draw_rect(Rect2(-5, -27, 10, 5), Color("#fffaf0"))  # pillow
			draw_rect(Rect2(-5, -22, 10, 1), Color("#d9cfba"))
			draw_rect(Rect2(-1, -25, 3, 2), Color("#3fbf7f"))  # the mint
			draw_rect(Rect2(-6, -16, 12, 14), color)  # blanket, turned down
			draw_rect(Rect2(-6, -17, 12, 2), Color("#fffaf0"))
			draw_rect(Rect2(-6, -16, 1, 14), color.lightened(0.15))
		"table_key":
			draw_rect(Rect2(-6, -9, 12, 2), Color("#8a4a2a"))  # small table
			draw_rect(Rect2(-6, -9, 12, 1), Color("#b06a3a"))
			draw_rect(Rect2(-5, -7, 1, 7), Color("#6b3a20"))
			draw_rect(Rect2(4, -7, 1, 7), Color("#6b3a20"))
			draw_rect(Rect2(-3, -12, 3, 3), color)  # key bow
			draw_rect(Rect2(-2, -11, 1, 1), Color("#8a5a32"))
			draw_rect(Rect2(0, -11, 4, 1), color)  # shaft
			draw_rect(Rect2(3, -10, 1, 1), color)  # bit
			if _pulse(3.0) > 0.9:
				draw_rect(Rect2(-3, -13, 1, 1), Color.WHITE)
		_:
			# Unknown shape: the loud placeholder.
			draw_texture(AssetCatalog.placeholder(), Vector2(-8, -16))


## A slanted cellar hatch leaning against the wall behind it: two wooden
## leaves narrowing toward the wall, iron bands, a padlock, and faint
## humming ripples (with the padlock buzzing now and then).
func _draw_hatch() -> void:
	var dark := color.darkened(0.45)
	var stone := Color("#7d766c")
	# Low stone cheeks: the slope rises from the ground (y 0) to the wall (y -12).
	draw_colored_polygon(PackedVector2Array([Vector2(-8, 0), Vector2(-8, -3), Vector2(-6, -13), Vector2(6, -13), Vector2(8, -3), Vector2(8, 0)]), stone)
	draw_rect(Rect2(-6, -14, 12, 1), Color(0, 0, 0, 0.35))  # shadow where it meets the wall
	# The sloping leaves, lit brighter toward the top, so the face reads as tilted.
	for i in 12:
		var y := -12.0 + i
		var hw := 5.0 + (y + 12.0) / 11.0 * 1.5
		draw_line(Vector2(-hw, y + 0.5), Vector2(hw, y + 0.5), color.lightened(0.28 - i * 0.03), 1.0)
	# Plank seams converge toward the wall: perspective on the slope.
	for xb in [-4.0, -2.0, 2.0, 4.0]:
		draw_line(Vector2(xb, -1), Vector2(xb * 0.77, -12), color.darkened(0.2), 1.0)
	draw_line(Vector2(0, -1), Vector2(0, -12), dark, 1.0)  # the two leaves meet
	for y in [-9, -4]:
		var hw: float = 5.0 + (y + 12.0) / 11.0 * 1.5
		draw_line(Vector2(-hw, y + 0.5), Vector2(hw, y + 0.5), Color("#3b3b46"), 1.0)  # iron straps
	draw_rect(Rect2(-8, -1, 16, 1), stone.darkened(0.35))  # front lip
	# Padlock on the hasp; it buzzes for a moment every couple of seconds.
	var buzz := fmod(t, 2.2) < 0.35
	var jx := (1.0 if int(t * 24.0) % 2 == 0 else 0.0) if buzz else 0.0
	draw_rect(Rect2(-1 + jx, -8, 3, 1), Color("#9aa0a8"))  # shackle
	draw_rect(Rect2(-2 + jx, -7, 5, 3), Color("#c9c3b5"))
	draw_rect(Rect2(0 + jx, -6, 1, 1), INK)
	# Humming ripples drifting out from the hatch.
	for k in 2:
		var ph := fmod(t * 0.7 + k * 0.5, 1.0)
		var col := Color(0.82, 0.74, 1.0, 0.5 * (1.0 - ph))
		var r := 5.0 + ph * 7.0
		draw_arc(Vector2(0, -6), r, -0.5, 0.5, 6, col, 1.0)
		draw_arc(Vector2(0, -6), r, PI - 0.5, PI + 0.5, 6, col, 1.0)


## An arcade cabinet that does not belong in a cozy inn: neon marquee,
## a glowing screen with a looping attract mode, and a blinking coin slot.
func _draw_arcade() -> void:
	var glow := 0.18 + 0.12 * _pulse(1.6)
	_ellipse(Vector2(0, 1), Vector2(11, 3.5), Color(0.25, 0.95, 1.0, glow))  # light on the floor
	draw_circle(Vector2(0, -20), 11.0, Color(0.25, 0.95, 1.0, glow * 0.45))  # screen halo
	draw_rect(Rect2(-7, -31, 14, 31), color)  # cabinet
	draw_rect(Rect2(-7, -31, 2, 31), color.lightened(0.25))
	draw_rect(Rect2(5, -31, 2, 31), color.darkened(0.35))
	draw_rect(Rect2(-6, -30, 12, 4), Color("#ff4fd8").lerp(Color.WHITE, 0.3 * _pulse(0.9)))  # marquee
	draw_rect(Rect2(-4, -29, 8, 1), Color("#fff0ff"))
	draw_rect(Rect2(-6, -25, 12, 10), Color("#06060c"))  # bezel
	draw_rect(Rect2(-5, -24, 10, 8), Color("#123a4a"))  # screen
	# Attract mode: a scanline sweeping down, a ship sliding across, a star.
	var sy := -24 + int(t * 10.0) % 8
	draw_rect(Rect2(-5, sy, 10, 1), Color("#3ff0ff"))
	var sx := -5 + int(t * 6.0) % 9
	draw_rect(Rect2(sx, -19, 2, 2), Color("#f6d55c"))
	if int(t * 3.0) % 2 == 0:
		draw_rect(Rect2(2, -23, 1, 1), Color.WHITE)
	draw_rect(Rect2(-7, -15, 14, 3), Color("#16112c"))  # control panel
	draw_rect(Rect2(-4, -14, 1, 1), Color("#c0392b"))  # stick
	draw_rect(Rect2(1, -14, 1, 1), Color("#ff4fd8"))
	draw_rect(Rect2(3, -14, 1, 1), Color("#3ff0ff"))
	var slot := Color("#ff9f43") if int(t * 2.0) % 2 == 0 else Color("#7a3f10")
	draw_rect(Rect2(-1, -9, 2, 3), slot)  # coin slot


## A stone fireplace on the wall with a flickering fire and warm floor glow.
func _draw_fireplace() -> void:
	var flick := 0.5 + 0.5 * sin(t * 9.0) * sin(t * 3.7)
	_ellipse(Vector2(0, 3), Vector2(10, 4), Color(1.0, 0.6, 0.2, 0.14 + 0.08 * flick))
	draw_rect(Rect2(-9, -14, 18, 14), color)  # stone surround
	draw_rect(Rect2(-9, -14, 18, 1), color.lightened(0.2))
	draw_rect(Rect2(-10, -16, 20, 3), Color("#6b3f24"))  # polished mantel
	draw_rect(Rect2(-10, -16, 20, 1), Color("#a8693f"))
	draw_rect(Rect2(-6, -18, 2, 2), Color("#f28fb0"))  # flowers on the mantel
	draw_rect(Rect2(4, -18, 2, 2), Color("#f6d55c"))
	draw_rect(Rect2(-5, -10, 10, 10), Color("#1a0f0a"))  # opening
	var h1 := 5.0 + 2.0 * sin(t * 11.0)
	var h2 := 6.0 + 2.0 * sin(t * 8.0 + 1.3)
	var h3 := 4.0 + 1.5 * sin(t * 13.0 + 2.1)
	draw_colored_polygon(PackedVector2Array([Vector2(-4, -1), Vector2(-2.5, -1 - h1), Vector2(-1, -1)]), Color("#ff6b3d"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2, -1), Vector2(0, -1 - h2), Vector2(2, -1)]), Color("#ff9f43"))
	draw_colored_polygon(PackedVector2Array([Vector2(1, -1), Vector2(2.5, -1 - h3), Vector2(4, -1)]), Color("#ff6b3d"))
	draw_colored_polygon(PackedVector2Array([Vector2(-1, -1), Vector2(0, -1 - h2 * 0.5), Vector2(1, -1)]), Color("#f6d55c"))
	draw_rect(Rect2(-4, -1, 8, 1), Color("#5e3c22"))  # logs
