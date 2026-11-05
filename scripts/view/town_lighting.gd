## Draws a map's light pools and window panes for its current lighting
## preset (see scripts/core/lighting.gd, which picks them from data). No
## engine lights: plain shapes with additive ("add") or normal ("mix")
## blending, which looks the same in the web build on any phone.
## Pools are stepped rings (pixel-art style), or the "light.pool" art if it
## exists (a white radial blob, tinted). Presentation only.
extends Node2D

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")

## [{"id", "pos", "shape"}] from Lighting.glows().
var spots: Array = []
## Thing id -> 0..1, so a glow fades with its thing (the ferry's lantern).
var alpha: Dictionary = {}
var pool_tex: Texture2D
var _mix: Node2D
var _add: Node2D


func setup(glow_spots: Array) -> void:
	spots = glow_spots
	pool_tex = AssetCatalog.try_texture("light.pool") if not spots.is_empty() else null
	_mix = Node2D.new()
	_mix.draw.connect(_draw_layer.bind(_mix, "mix"))
	add_child(_mix)
	_add = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = m
	_add.draw.connect(_draw_layer.bind(_add, "add"))
	add_child(_add)


## How many pools/panes are drawn (tests).
func count(blend: String = "") -> int:
	return spots.filter(func(s): return blend == "" or _blend(s) == blend).size()


## Fades the glows that belong to one thing.
func set_alpha(thing_id: String, a: float) -> void:
	alpha[thing_id] = a
	_mix.queue_redraw()
	_add.queue_redraw()


func _blend(s: Dictionary) -> String:
	return str(s["shape"].get("blend", "add"))


func _draw_layer(node: Node2D, blend: String) -> void:
	for s in spots:
		if _blend(s) != blend:
			continue
		var sh: Dictionary = s["shape"]
		var a: float = float(sh.get("strength", 0.5)) * float(alpha.get(s["id"], 1.0))
		if a <= 0.0:
			continue
		var col := Color(str(sh.get("color", "#ffd27a")))
		var off: Array = sh.get("offset", [0, 0])
		var at: Vector2 = s["pos"] + Vector2(float(off[0]), float(off[1]))
		if sh.has("rect"):
			var r: Array = sh["rect"]
			node.draw_rect(Rect2(s["pos"] + Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3]))), Color(col, a))
			continue
		var radius := float(sh.get("radius", 16))
		if pool_tex != null:
			node.draw_texture_rect(pool_tex, Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(col, a))
			continue
		# Stepped rings: each adds a share, so the centre is brightest.
		var steps := maxi(1, int(sh.get("steps", 3)))
		for k in steps:
			node.draw_circle(at, roundf(radius * float(steps - k) / steps), Color(col, a / steps))
