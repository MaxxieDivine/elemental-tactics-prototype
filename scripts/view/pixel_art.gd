## Placeholder pixel art shared by the town and the pixel-style fight: the
## character figure, rats, the candle rat and the cellar lantern. Each is
## drawn in art pixels around the feet (bottom centre of a 16x16 tile, y up
## is negative), on any CanvasItem. The caller sets the transform: scale 1
## in the town, 3 art pixels per CSS pixel in the cellar fight, so the two
## look the same. Presentation only. Real art (by asset key) replaces these.
extends RefCounted

const SKIN := Color("#f1c9a5")
const INK := Color("#1d1b24")
## Shapes drawn here (others belong to TownActor).
const SHAPES := ["character", "rat", "candle_rat", "cellar_lantern"]


static func has_shape(shape: String) -> bool:
	return SHAPES.has(shape)


## Draws `shape` with its feet at (0, 0). `t` is an animation clock in
## seconds (the candle flickers, the lantern glows).
static func draw(ci: CanvasItem, shape: String, color: Color, t: float = 0.0, facing: String = "down") -> void:
	match shape:
		"character":
			character(ci, color, facing)
		"rat":
			rat(ci, color, t, facing)
		"candle_rat":
			rat(ci, color, t, facing)
			_candle(ci, Vector2(-1, -7), t)
		"cellar_lantern":
			lantern(ci, color, t)


static func _r(ci: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h), c)


static func _pulse(t: float, period: float) -> float:
	return 0.5 - 0.5 * cos(TAU * fmod(t / period, 1.0))


## A person: body, head, hair, and a facing cue (eyes, plus a small arrow at
## the feet). The town's placeholder for every character.
static func character(ci: CanvasItem, color: Color, facing: String) -> void:
	var dark := color.darkened(0.35)
	_r(ci, -4, -4, 3, 3, dark)  # legs
	_r(ci, 1, -4, 3, 3, dark)
	_r(ci, -5, -13, 10, 10, color)  # body
	_r(ci, -5, -13, 10, 2, color.lightened(0.2))
	_r(ci, -4, -21, 8, 8, SKIN)  # head
	_r(ci, -4, -22, 8, 3, dark)  # hair
	match facing:
		"down":
			_r(ci, -3, -18, 1, 2, INK)
			_r(ci, 2, -18, 1, 2, INK)
		"left":
			_r(ci, -4, -18, 1, 2, INK)
			_r(ci, 1, -22, 3, 6, dark)
		"right":
			_r(ci, 3, -18, 1, 2, INK)
			_r(ci, -4, -22, 3, 6, dark)
		"up":
			_r(ci, -4, -22, 8, 6, dark)
	var d: Vector2 = {"down": Vector2(0, 1), "up": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}.get(facing, Vector2(0, 1))
	var tip := Vector2(0, -1) + d * 8.0
	var side := Vector2(-d.y, d.x) * 2.5
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - d * 3.0 + side, tip - d * 3.0 - side]), Color(1, 1, 1, 0.85))


## A cellar rat, side on: hunched body, ears, beady eye, pink nose, and a
## tail that twitches. Faces left unless `facing` is "right".
static func rat(ci: CanvasItem, color: Color, t: float, facing: String = "left") -> void:
	var s := 1.0 if facing == "right" else -1.0
	var dark := color.darkened(0.4)
	var light := color.lightened(0.18)
	var sniff := 1.0 if fmod(t, 1.3) < 0.15 else 0.0
	# Tail curls out behind.
	var flick := -1.0 if fmod(t, 0.9) < 0.45 else 0.0
	ci.draw_line(Vector2(-5 * s, -2), Vector2(-7 * s, -3 + flick), Color("#d79a9a"), 1.0)
	ci.draw_line(Vector2(-7 * s, -3 + flick), Vector2(-8 * s, -5 + flick), Color("#d79a9a"), 1.0)
	# Body, belly shadow, back highlight.
	for y in range(-7, -1):
		var hw := 5.0 - absf(y + 4.0) * 0.6
		ci.draw_line(Vector2(-hw * s - 1 * s, y + 0.5), Vector2(hw * s + 1 * s, y + 0.5), color, 1.0)
	_r(ci, -4, -2, 8, 1, dark)
	_r(ci, -3 if s > 0 else -1, -7, 4, 1, light)
	# Head with snout.
	var hx := 4.0 * s
	ci.draw_colored_polygon(PackedVector2Array([Vector2(hx - 1 * s, -6), Vector2(hx + 3 * s + sniff * s, -4), Vector2(hx - 1 * s, -2)]), color)
	_r(ci, (hx + 3 * s + sniff * s) - (0.0 if s > 0 else 1.0), -5, 1, 1, Color("#f2a0a8"))  # nose
	_r(ci, hx + (0.0 if s > 0 else -1.0), -5, 1, 1, INK)  # eye
	_r(ci, hx - 1 * s - (0.0 if s > 0 else 1.0), -8, 2, 2, Color("#d79a9a"))  # ear
	# Feet.
	_r(ci, -3, -1, 1, 1, dark)
	_r(ci, 2, -1, 1, 1, dark)


## A stub of candle on a rat's back with a flame that flickers.
static func _candle(ci: CanvasItem, at: Vector2, t: float) -> void:
	_r(ci, at.x, at.y - 4, 2, 4, Color("#f4efe1"))  # wax
	_r(ci, at.x, at.y - 4, 2, 1, Color("#fffaf0"))
	_r(ci, at.x - 1, at.y - 1, 4, 1, Color("#e8dcc0"))  # drips
	var h := 3.0 + roundf(_pulse(t, 0.35))
	var sway := 1.0 if fmod(t, 0.5) < 0.25 else 0.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(at.x - 0.5, at.y - 4), Vector2(at.x + 1 + sway, at.y - 4 - h), Vector2(at.x + 2.5, at.y - 4)]), Color("#ff9f43"))
	_r(ci, at.x + 0.5, at.y - 6, 1, 2, Color("#fff1c2"))
	ci.draw_circle(Vector2(at.x + 1, at.y - 6), 3.5, Color(1.0, 0.8, 0.4, 0.18))


## A heavy floor lantern: iron base and cap, a ring handle, glass with a
## warm flame. Brightness breathes slowly.
static func lantern(ci: CanvasItem, color: Color, t: float) -> void:
	var iron := Color("#3b3330")
	var glow := 0.18 + 0.08 * _pulse(t, 1.8)
	ci.draw_circle(Vector2(0, -6), 7.0, Color(1.0, 0.78, 0.4, glow))
	_r(ci, -4, -2, 8, 2, iron)  # base
	_r(ci, -4, -2, 8, 1, iron.lightened(0.2))
	_r(ci, -3, -10, 6, 8, Color("#fff1c2").lerp(color, 0.35))  # glass
	_r(ci, -3, -10, 1, 8, iron)  # frame
	_r(ci, 2, -10, 1, 8, iron)
	_r(ci, -1, -7, 2, 3, Color("#ff9f43"))  # flame
	_r(ci, -1, -6, 1, 1, Color("#fff8e0"))
	_r(ci, -4, -12, 8, 2, iron)  # cap
	_r(ci, -2, -13, 4, 1, iron.lightened(0.15))
	ci.draw_arc(Vector2(0, -14), 2.0, PI, TAU, 6, iron, 1.0)  # handle
