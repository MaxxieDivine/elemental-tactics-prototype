## Lighting presets: how a map looks at a time of day, all from data.
## Plain data, no Nodes: the town view draws what this picks.
##
## A map's "lighting" is the name of a preset in data/town.json
## "lighting_presets" (e.g. "outdoor", "inn"), or a preset written inline.
## A preset holds one look per time of day ("day", "night"), each with:
##   "tint"        colour the ground tiles are multiplied by
##   "tile_tints"  {legend char: colour} for tiles that need their own
##                 (darker water, a dock path that stays visible)
##   "prop_tint"   props and objects nobody can use
##   "actor_tint"  characters and anything the player can tap (keep bright)
##   "lit_tint"    anything that gives off light (lamps, lanterns)
##   "glows"       {kind: shape or [shapes]}: light pools and window panes.
##                 Tiles (legend "glow") and things (a "glow" key) name a kind.
##                 Shape: "color", "strength" (0..1), "offset" [x, y],
##                 then "radius" (a soft stepped pool, "steps" rings) or
##                 "rect" [x, y, w, h]; "blend": "add" (light, default)
##                 or "mix" (paint over, e.g. dark window panes).
## A missing preset or time means no change: everything as drawn.
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

const WHITE := "#ffffff"


## The look for a map definition at a time of day ({} for none).
static func preset_for(map_def: Dictionary, time_of_day: String) -> Dictionary:
	var l = map_def.get("lighting", "")
	var looks: Dictionary = {}
	if l is Dictionary:
		looks = l
	elif str(l) != "":
		var presets: Dictionary = GameData.get_json("town").get("lighting_presets", {})
		if not presets.has(str(l)):
			push_warning("Map '%s' uses unknown lighting preset '%s'." % [map_def.get("id", ""), str(l)])
		looks = presets.get(str(l), {})
	return looks.get(time_of_day, {})


## The name of the preset a map uses ("" when inline or none).
static func preset_name(map_def: Dictionary) -> String:
	var l = map_def.get("lighting", "")
	return "" if l is Dictionary else str(l)


## A tint colour from a preset (white when not set).
static func tint(preset: Dictionary, key: String) -> Color:
	return Color(str(preset.get(key, WHITE)))


## The colour for a tile's legend char: its own tile tint, else "tint".
static func tile_tint(preset: Dictionary, legend_char: String) -> Color:
	var own: Dictionary = preset.get("tile_tints", {})
	return Color(str(own[legend_char])) if own.has(legend_char) else tint(preset, "tint")


## The tint key for a thing on a map: "lit_tint" if it gives off light,
## "actor_tint" for characters and anything with an interaction, else
## "prop_tint".
static func tint_key(kind: String, thing: Dictionary) -> String:
	if str(thing.get("glow", "")) != "":
		return "lit_tint"
	if kind == "npc" or kind == "player" or str(thing.get("interaction", "")) != "":
		return "actor_tint"
	return "prop_tint"


## The shapes of one glow kind in a preset (always a list).
static func glow_shapes(preset: Dictionary, kind: String) -> Array:
	var g = preset.get("glows", {}).get(kind, [])
	return g if g is Array else [g]


## Every light pool / pane to draw on a built TownMap for a preset:
## [{"id": thing id or "", "pos": Vector2 (world px anchor), "shape": {...}}].
## Tiles anchor at their top-left corner; things at their feet (bottom centre
## of their tile). `ts` is the tile size in pixels.
static func glows(map, preset: Dictionary, ts: int) -> Array:
	var out: Array = []
	if preset.get("glows", {}).is_empty():
		return out
	for y in map.size.y:
		for x in map.size.x:
			var c := Vector2i(x, y)
			var kind := str(map.tile_def(c).get("glow", ""))
			for s in glow_shapes(preset, kind):
				out.append({"id": "", "pos": Vector2(c * ts), "shape": s})
	var lists := {"npcs": "", "objects": "", "props": "prop_"}
	for list in lists:
		var things: Array = map.def.get(list, [])
		for i in things.size():
			var t: Dictionary = things[i]
			var kind := str(t.get("glow", ""))
			if kind == "":
				continue
			var tid: String = "prop_%d" % i if list == "props" else str(t["id"])
			var c: Vector2i = map.cell_of_thing(tid)
			for s in glow_shapes(preset, kind):
				out.append({"id": tid, "pos": Vector2(c.x * ts + ts * 0.5, c.y * ts + ts - 1), "shape": s})
	return out
