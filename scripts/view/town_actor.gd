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
const PixelArt = preload("res://scripts/view/pixel_art.gd")

const FRAMES := ["down", "left", "right", "up"]
const SKIN := Color("#f1c9a5")
const INK := Color("#1d1b24")
## Placeholder shapes that loop a small animation.
const ANIMATED := ["hatch", "hatch_unlocked", "arcade", "fireplace", "door_light", "lantern", "ferry", "rat", "candle_rat", "humming_case", "office_window"]
## Shapes drawn without a ground shadow (on walls, flat, or invisible).
const NO_SHADOW := ["hatch", "hatch_unlocked", "none", "lantern", "key_board", "fireplace", "door_reserved", "door_light", "door_name", "ferry", "tall_shelf", "dock_office", "office_door", "office_window"]
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
	# Body, head and a facing cue (shared with the pixel-style fight).
	PixelArt.character(self, color, facing)


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
		"hatch_unlocked":
			_draw_hatch(false)
		"rat", "candle_rat":
			PixelArt.draw(self, shape, color, t, "left" if id.hash() % 2 == 0 else "right")
		"cellar_lantern":
			PixelArt.lantern(self, color, t)
		"fallen_shelf":
			_draw_fallen_shelf()
		"tall_shelf":
			_draw_tall_shelf()
		"luggage_pile":
			_suitcase(Vector2(-6, 0), Vector2(12, 6), color, true)
			_suitcase(Vector2(-5, -6), Vector2(10, 5), color.lightened(0.2).lerp(Color("#8a6a44"), 0.4), false)
			_tag(Vector2(4, -4), false)
		"suitcase":
			_suitcase(Vector2(-6, 0), Vector2(12, 9), color, true)
			_tag(Vector2(5, -5), true)
		"blank_tags":
			draw_rect(Rect2(-6, -8, 12, 8), color)  # crate
			draw_rect(Rect2(-6, -8, 12, 1), color.lightened(0.25))
			draw_line(Vector2(-6, -4), Vector2(6, -4), color.darkened(0.3), 1.0)
			_tag(Vector2(-3, -9), false)
			_tag(Vector2(2, -9), false)
		"ribbon_case":
			_suitcase(Vector2(-6, 0), Vector2(12, 9), color, true)
			_tag(Vector2(5, -5), true)
			var ribbon := Color("#e0457b")
			draw_rect(Rect2(-1, -12, 2, 3), ribbon)  # bow on the handle
			draw_colored_polygon(PackedVector2Array([Vector2(0, -11), Vector2(-4, -13), Vector2(-4, -9)]), ribbon)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -11), Vector2(4, -13), Vector2(4, -9)]), ribbon)
			draw_line(Vector2(-1, -9), Vector2(-3, -5), ribbon, 1.0)
			draw_line(Vector2(1, -9), Vector2(2, -5), ribbon, 1.0)
		"humming_case":
			_draw_humming_case()
		"dock_office":
			_draw_dock_office()
		"office_door":
			draw_rect(Rect2(-5, -13, 10, 13), Color("#3b2a1f"))  # frame
			draw_rect(Rect2(-4, -12, 8, 12), color)
			draw_line(Vector2(0, -12), Vector2(0, 0), color.darkened(0.3), 1.0)
			draw_rect(Rect2(2, -6, 1, 1), Color("#e0b44a"))  # knob
			draw_rect(Rect2(-3, -10, 6, 3), Color("#c9b48a"))  # "Closed" plank
			draw_rect(Rect2(-2, -9, 4, 1), Color("#7a3b2e"))
		"office_window":
			var warm := 0.9 + 0.1 * _pulse(2.8)
			draw_rect(Rect2(-5, -12, 10, 9), Color("#3b2a1f"))  # frame
			draw_rect(Rect2(-4, -11, 8, 7), Color(color, warm))
			draw_rect(Rect2(-4, -11, 8, 1), Color("#fff1c2"))
			draw_line(Vector2(0, -11), Vector2(0, -4), Color("#3b2a1f"), 1.0)
			draw_line(Vector2(-4, -8), Vector2(4, -8), Color("#3b2a1f"), 1.0)
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
		"ferry":
			_draw_ferry()
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
## leaves narrowing toward the wall, iron bands, a padlock (or, unlocked,
## an open hasp), and faint humming ripples (the padlock buzzing now and then).
func _draw_hatch(locked: bool = true) -> void:
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
	if locked:
		# Padlock on the hasp; it buzzes for a moment every couple of seconds.
		var buzz := fmod(t, 2.2) < 0.35
		var jx := (1.0 if int(t * 24.0) % 2 == 0 else 0.0) if buzz else 0.0
		draw_rect(Rect2(-1 + jx, -8, 3, 1), Color("#9aa0a8"))  # shackle
		draw_rect(Rect2(-2 + jx, -7, 5, 3), Color("#c9c3b5"))
		draw_rect(Rect2(0 + jx, -6, 1, 1), INK)
	else:
		# The padlock is gone; the hasp hangs open and the leaves sit ajar.
		draw_line(Vector2(1, -8), Vector2(3, -5), Color("#9aa0a8"), 1.0)
		draw_rect(Rect2(-1, -8, 2, 1), Color("#6a6e76"))
		draw_line(Vector2(-1, -12), Vector2(1, -12), Color(0, 0, 0, 0.55), 1.0)  # dark gap at the seam
	# Humming ripples drifting out from the hatch.
	for k in 2:
		var ph := fmod(t * 0.7 + k * 0.5, 1.0)
		var col := Color(0.82, 0.74, 1.0, 0.5 * (1.0 - ph))
		var r := 5.0 + ph * 7.0
		draw_arc(Vector2(0, -6), r, -0.5, 0.5, 6, col, 1.0)
		draw_arc(Vector2(0, -6), r, PI - 0.5, PI + 0.5, 6, col, 1.0)


## A ferry offshore at night: a dark silhouette with a faint moonlit rim so
## it reads against dark water, one dim lantern on the mast, bobbing gently.
func _draw_ferry() -> void:
	var bob := roundf(_pulse(3.2))
	var o := Vector2(0, bob)
	var rim := color.lightened(0.3)
	var hull := PackedVector2Array([Vector2(-15, -7), Vector2(15, -7), Vector2(12, 0), Vector2(-12, 0)])
	for i in hull.size():
		hull[i] += o
	draw_colored_polygon(hull, color)
	draw_line(Vector2(-15, -7) + o, Vector2(15, -7) + o, rim, 1.0)  # deck edge
	draw_rect(Rect2(Vector2(-10, -14) + o, Vector2(14, 7)), color)  # cabin
	draw_line(Vector2(-10, -14) + o, Vector2(4, -14) + o, rim, 1.0)
	for x in [-8, -4, 0]:
		draw_rect(Rect2(Vector2(x, -12) + o, Vector2(2, 2)), color.lightened(0.12))  # dark portholes
	draw_rect(Rect2(Vector2(-6, -20) + o, Vector2(3, 6)), color)  # funnel
	draw_line(Vector2(5, -24) + o, Vector2(5, -7) + o, color.lightened(0.08), 1.0)  # mast
	var lamp := 0.55 + 0.25 * _pulse(2.4)
	draw_rect(Rect2(Vector2(4, -18) + o, Vector2(3, 3)), Color(1.0, 0.82, 0.45, lamp))  # the one dim lantern
	# Water lapping at the hull.
	var ph := fmod(t * 0.8, 1.0)
	draw_line(Vector2(-14 - ph * 2, 1), Vector2(-9, 1), Color(0.6, 0.7, 1.0, 0.35), 1.0)
	draw_line(Vector2(9, 1), Vector2(14 + ph * 2, 1), Color(0.6, 0.7, 1.0, 0.35), 1.0)


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


## A wooden suitcase lying on the floor (bottom-left corner at `at`): lid
## seam, corner caps, brass clasps and a handle.
func _suitcase(at: Vector2, size: Vector2, col: Color, handle: bool) -> void:
	var r := Rect2(at.x, at.y - size.y, size.x, size.y)
	draw_rect(r, col.darkened(0.45))
	draw_rect(r.grow(-1), col)
	draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 1), col.lightened(0.25))
	draw_line(Vector2(r.position.x + 1, r.position.y + 3.5), Vector2(r.end.x - 1, r.position.y + 3.5), col.darkened(0.3), 1.0)
	for x in [r.position.x + 2, r.end.x - 3]:
		draw_rect(Rect2(x, r.position.y + 2, 1, 2), Color("#e0b44a"))  # clasps
	if handle:
		draw_rect(Rect2(r.get_center().x - 2, r.position.y - 2, 4, 1), Color("#3b2a20"))
		draw_rect(Rect2(r.get_center().x - 2, r.position.y - 2, 1, 2), Color("#3b2a20"))
		draw_rect(Rect2(r.get_center().x + 1, r.position.y - 2, 1, 2), Color("#3b2a20"))


## A paper luggage tag on a string (top of the string at `at`); `written`
## adds a line of ink.
func _tag(at: Vector2, written: bool) -> void:
	draw_line(at, at + Vector2(0, 2), Color("#c9c3b5"), 1.0)
	draw_rect(Rect2(at.x - 1, at.y + 2, 3, 4), Color("#f4efe1"))
	draw_rect(Rect2(at.x, at.y + 2, 1, 1), Color("#8d8577"))  # eyelet
	if written:
		draw_rect(Rect2(at.x - 1, at.y + 4, 3, 1), Color("#3a4f9a"))


## A tall storage shelf against the wall (two tiles high) crammed with old
## suitcases, a few with paper tags hanging off them.
func _draw_tall_shelf() -> void:
	var wood := color
	var dark := wood.darkened(0.4)
	draw_rect(Rect2(-8, -31, 16, 31), dark)  # back
	draw_rect(Rect2(-8, -31, 2, 31), wood)  # uprights
	draw_rect(Rect2(6, -31, 2, 31), wood.darkened(0.15))
	var cases := [Color("#7a5a3a"), Color("#5a6a7a"), Color("#8a3b2e"), Color("#4f6b4a"), Color("#9a8a6a")]
	for i in 3:
		var y := -1 - i * 10
		draw_rect(Rect2(-8, y, 16, 1), wood.lightened(0.15))  # plank
		var c1: Color = cases[(i * 2 + id.length()) % cases.size()]
		var c2: Color = cases[(i * 2 + 1 + id.length()) % cases.size()]
		draw_rect(Rect2(-6, y - 6, 6, 6), c1)
		draw_rect(Rect2(-6, y - 6, 6, 1), c1.lightened(0.2))
		draw_rect(Rect2(1, y - 5, 5, 5), c2)
		draw_rect(Rect2(1, y - 5, 5, 1), c2.lightened(0.2))
		if i != 1:
			_tag(Vector2(-2, y - 5), true)
	draw_rect(Rect2(-8, -31, 16, 1), wood.lightened(0.25))  # top


## A shelf that has toppled across the doorway, spilling a suitcase.
func _draw_fallen_shelf() -> void:
	var wood := color
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -3), Vector2(-6, -12), Vector2(8, -8), Vector2(7, 0), Vector2(-7, 0)]), wood.darkened(0.45))
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -4), Vector2(-6, -12), Vector2(8, -8), Vector2(8, -5)]), wood)
	for k in 3:
		var x := -4.0 + k * 4.5
		draw_line(Vector2(x, -11 + k * 1.3), Vector2(x + 1, -4), wood.darkened(0.3), 1.0)  # shelf boards
	draw_line(Vector2(-6, -12), Vector2(8, -8), wood.lightened(0.25), 1.0)
	_suitcase(Vector2(-7, 0), Vector2(7, 4), Color("#5a6a7a"), false)
	draw_rect(Rect2(3, -2, 3, 2), Color("#8a6a44"))  # a broken board


## A locked hard case that hums: dark with metal corners, a violet glow
## at the lock, rings drifting off it and a tiny shiver now and then.
func _draw_humming_case() -> void:
	var shiver := (1.0 if int(t * 30.0) % 2 == 0 else 0.0) if fmod(t, 1.7) < 0.2 else 0.0
	var o := Vector2(shiver, 0)
	var r := Rect2(Vector2(-6, -10) + o, Vector2(12, 10))
	draw_rect(r, color.darkened(0.5))
	draw_rect(r.grow(-1), color)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(10, 1)), color.lightened(0.3))
	for corner in [r.position, Vector2(r.end.x - 2, r.position.y), Vector2(r.position.x, r.end.y - 2), r.end - Vector2(2, 2)]:
		draw_rect(Rect2(corner, Vector2(2, 2)), Color("#9aa0a8"))
	var glow := 0.55 + 0.45 * _pulse(1.4)
	draw_rect(Rect2(Vector2(-1, -6) + o, Vector2(2, 2)), Color(0.75, 0.6, 1.0, glow))  # the lock
	draw_rect(Rect2(Vector2(-2, -12) + o, Vector2(4, 1)), Color("#3b3330"))  # handle
	for k in 2:
		var ph := fmod(t * 0.6 + k * 0.5, 1.0)
		var col := Color(0.75, 0.6, 1.0, 0.55 * (1.0 - ph))
		var rad := 6.0 + ph * 6.0
		draw_arc(Vector2(0, -5), rad, -0.6, 0.6, 6, col, 1.0)
		draw_arc(Vector2(0, -5), rad, PI - 0.6, PI + 0.6, 6, col, 1.0)


## The dock office: a small timber building three tiles wide, drawn from its
## front-middle tile. A "DOCK" sign over the front, and a dark window on the
## left tile (its warm light is a separate thing that can go out); the door
## is a separate thing on the right tile.
func _draw_dock_office() -> void:
	var wall := color
	var roof := Color("#3f4a5a")
	_ellipse(Vector2(0, -1), Vector2(23, 2), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-24, -16, 48, 16), wall)  # front wall
	for x in range(-24, 24, 4):
		draw_line(Vector2(x, -16), Vector2(x, 0), wall.darkened(0.18), 1.0)  # planks
	draw_rect(Rect2(-24, -2, 48, 2), Color("#8d8577"))  # stone footing
	draw_colored_polygon(PackedVector2Array([Vector2(-26, -15), Vector2(-20, -30), Vector2(20, -30), Vector2(26, -15)]), roof)
	draw_line(Vector2(-26, -15), Vector2(26, -15), roof.darkened(0.35), 1.0)
	for y in [-26, -22, -18]:
		draw_line(Vector2(-23 + (y + 30) * 0.2, y), Vector2(23 - (y + 30) * 0.2, y), roof.lightened(0.12), 1.0)  # shingle rows
	draw_rect(Rect2(-9, -14, 18, 5), Color("#c9b48a"))  # sign
	draw_rect(Rect2(-9, -14, 18, 1), Color("#e6d9bc"))
	for i in 4:  # "DOCK" as four blocky letters
		draw_rect(Rect2(-7 + i * 4, -12, 3, 2), Color("#3b2a1f"))
	draw_rect(Rect2(-21, -12, 10, 9), Color("#3b2a1f"))  # left window frame
	draw_rect(Rect2(-20, -11, 8, 7), Color("#1d2433"))  # dark pane
	draw_line(Vector2(-16, -11), Vector2(-16, -4), Color("#3b2a1f"), 1.0)
	draw_rect(Rect2(11, -13, 10, 13), Color("#3b2a1f"))  # door frame (the door is its own thing)
	draw_rect(Rect2(-3, -6, 6, 4), wall.darkened(0.25))  # notice board
	draw_rect(Rect2(-2, -5, 2, 2), Color("#f4efe1"))
	draw_rect(Rect2(1, -5, 1, 2), Color("#f4efe1"))
