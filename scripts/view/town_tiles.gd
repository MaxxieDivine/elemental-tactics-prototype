## Builds the town TileSet. Uses the "town.tiles" asset (a 16x16-tile sheet
## such as Kenney's Tiny Town) when it exists; otherwise generates simple
## placeholder tiles, painting each tile type into the atlas cell its data
## names, so swapping in a real sheet only means editing "atlas" in data.
## The generated inn tiles aim for warm, polished and slightly too perfect.
## Presentation only.
extends RefCounted

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")

const SOURCE_ID := 0
const INTERIOR := ["floorboards", "rug", "walltop", "wallpaper", "window_in", "door_in", "stairs_up", "stairs_down", "doorway", "threshold"]
const WOOD := Color("#8a4a2a")
const WOOD_DARK := Color("#5e3020")
const BRASS := Color("#e0b44a")


static func build(def: Dictionary) -> TileSet:
	var ts: int = int(def.get("tile_size", 16))
	var tex: Texture2D = AssetCatalog.try_texture("town.tiles")
	if tex == null:
		tex = generate_atlas(def["tiles"], ts)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	var grid := Vector2i(tex.get_size()) / ts
	for ch in def["tiles"]:
		var a := atlas_of(def["tiles"][ch])
		if a.x < grid.x and a.y < grid.y and not src.has_tile(a):
			src.create_tile(a)
	tileset.add_source(src, SOURCE_ID)
	return tileset


static func atlas_of(tile: Dictionary) -> Vector2i:
	var a: Array = tile.get("atlas", [0, 0])
	return Vector2i(int(a[0]), int(a[1]))


## A generated sheet with one placeholder tile per tile type.
static func generate_atlas(tiles: Dictionary, ts: int) -> Texture2D:
	var cols := 1
	var rows := 1
	for ch in tiles:
		var a := atlas_of(tiles[ch])
		cols = maxi(cols, a.x + 1)
		rows = maxi(rows, a.y + 1)
	var img := Image.create(cols * ts, rows * ts, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	for ch in tiles:
		var t: Dictionary = tiles[ch]
		paint(img, atlas_of(t) * ts, ts, str(t.get("pattern", "")), Color(str(t.get("color", "#ff00ff"))), ch.unicode_at(0))
	return ImageTexture.create_from_image(img)


static func _noise(x: int, y: int, s: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (s * 83492791)) & 0xff


static func paint(img: Image, o: Vector2i, ts: int, pattern: String, base: Color, s: int) -> void:
	var dark := base.darkened(0.18)
	var light := base.lightened(0.15)
	for y in ts:
		for x in ts:
			var c := base
			var n := _noise(x, y, s)
			match pattern:
				"grass", "flowers":
					if n < 30:
						c = dark
					elif n > 236:
						c = light
				"speckle":
					if n < 24:
						c = dark
					elif n > 240:
						c = light
				"cobble":
					var row := y / 4
					if y % 4 == 3 or (x + (row % 2) * 2) % 4 == 3:
						c = dark
					elif n > 220:
						c = light
				"planks":
					if y % 4 == 3:
						c = dark.darkened(0.15)
					elif (x + (y / 4) * 5) % 16 == 0:
						c = dark
					elif n < 20:
						c = light
				"waves":
					if (y == 4 and (x + 2) % 8 < 3) or (y == 11 and (x + 6) % 8 < 3):
						c = light.lightened(0.2)
					elif n < 16:
						c = dark
				"shingles":
					if y % 4 == 3:
						c = dark.darkened(0.1)
					elif (x + (y / 4 % 2) * 3) % 6 == 5:
						c = dark
				"wall", "window", "door":
					if y < 2:
						c = Color("#6b4b37")  # eave shadow / beam
					elif y >= ts - 2:
						c = Color("#8d8577")  # stone footing
					elif x == 0:
						c = Color("#7a5a40")  # timber post
					elif n < 14:
						c = dark
			if pattern in INTERIOR:
				c = _interior(pattern, x, y, ts, base, n)
			if pattern == "flowers" and ((x == 3 and y == 4) or (x == 11 and y == 3) or (x == 7 and y == 10) or (x == 13 and y == 12)):
				c = [Color("#f6d55c"), Color("#f28fb0"), Color.WHITE, Color("#f6d55c")][(x + y) % 4]
			if pattern == "window" and x >= 4 and x <= 11 and y >= 4 and y <= 11:
				c = Color("#5a4030") if (x == 4 or x == 11 or y == 4 or y == 11) else (Color("#c9e6f2") if x == 7 or y == 7 else Color("#5f9cc2"))
			if pattern == "door" and x >= 2 and x <= 13 and y >= 3:
				c = Color("#5e3c22") if (x == 2 or x == 13 or y == 3) else (Color("#e0b44a") if (x == 11 and y == 9) else Color("#8a5a32"))
			img.set_pixel(o.x + x, o.y + y, c)


## Wallpaper above a polished wood wainscot (shared by the wall-based tiles).
static func _wall(x: int, y: int, base: Color, n: int) -> Color:
	if y >= 15:
		return WOOD_DARK  # skirting
	if y >= 10:
		return WOOD.lightened(0.18) if y == 10 else (WOOD.darkened(0.1) if x % 8 == 0 else WOOD)
	if y == 9:
		return WOOD_DARK  # rail
	if x % 4 == 1:
		return base.darkened(0.08)  # stripes
	if (x % 8 == 3 and y % 6 == 2):
		return Color("#d77a8a")  # tiny flowers
	return base if n > 12 else base.lightened(0.05)


static func _interior(pattern: String, x: int, y: int, ts: int, base: Color, n: int) -> Color:
	match pattern:
		"floorboards":
			var row := y / 4
			if y % 4 == 3:
				return base.darkened(0.28)
			if (x + row * 6) % 16 == 0:
				return base.darkened(0.2)
			if y % 4 == 0 and n > 150:
				return base.lightened(0.22)  # polish glints
			return base if n > 30 else base.darkened(0.06)
		"rug":
			var dx := absi((x % 8) - 4)
			var dy := absi((y % 8) - 4)
			if dx + dy == 3:
				return BRASS.darkened(0.1)
			if dx + dy == 0:
				return Color("#f4efe1")
			return base if n > 20 else base.darkened(0.1)
		"walltop":
			if y == 0:
				return base.lightened(0.25)
			if y == ts - 1:
				return base.darkened(0.35)
			return base if (x + y * 3) % 7 != 0 else base.lightened(0.08)
		"wallpaper":
			return _wall(x, y, base, n)
		"window_in":
			if x >= 3 and x <= 12 and y >= 1 and y <= 8:
				if x == 3 or x == 12 or y == 1 or y == 8:
					return WOOD_DARK
				if x <= 4 or x >= 11:
					return Color("#e98aa0")  # curtains
				if x == 7 or x == 8 or y == 4:
					return Color("#f4efe1")
				return Color("#5f9cc2") if y > 2 else Color("#c9e6f2")
			return _wall(x, y, base, n)
		"door_in":
			if x >= 3 and x <= 12 and y >= 2:
				if x == 3 or x == 12 or y == 2:
					return WOOD_DARK
				if x == 10 and y == 9:
					return BRASS  # knob
				if x >= 6 and x <= 9 and y >= 4 and y <= 5:
					return BRASS.darkened(0.15)  # number plate
				if (x == 5 or x == 10) and y >= 7 and y <= 13 and not (x == 10 and y == 9):
					return Color("#6a2f22")  # panel lines
				return Color("#7a3b2e") if n > 20 else Color("#8a4536")
			return _wall(x, y, base, n)
		"stairs_up", "stairs_down":
			if x <= 1 or x >= ts - 2:
				return WOOD_DARK  # banisters
			var step := y / 3
			var shade := (5 - step) * 0.07 if pattern == "stairs_up" else step * 0.07
			var c := base.darkened(shade)
			if y % 3 == 0:
				c = c.lightened(0.2)  # step nosing
			if x >= 6 and x <= 9:
				c = Color("#9c2f3e").darkened(shade)  # stair runner
			return c
		"doorway":
			if y <= 1:
				return WOOD_DARK  # lintel
			if x >= 4 and x <= 11:
				return Color("#2a1c15") if x < 10 else Color("#5a3a26")
			return base
		"threshold":
			if x <= 1 or x >= ts - 2:
				return WOOD_DARK  # door frame
			if y <= 2:
				return Color("#3a2a1f")
			if y >= 4 and y <= 12 and x >= 3 and x <= 12:
				return Color("#6b5a3a") if (y % 2 == 0) else Color("#7d6a45")  # doormat
			return Color("#a8693f")
	return base
