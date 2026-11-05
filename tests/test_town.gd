## Town grid: walkability, paths, and finding a tile next to a target.
extends "res://tests/test_base.gd"

const TownMap = preload("res://scripts/core/town_map.gd")


func _small() -> Dictionary:
	# 6x4 test town: # blocks, . walks. Thing "sign" at (3,1).
	return {
		"tiles": {".": {"walkable": true}, "#": {"walkable": false}},
		"map": [
			"......",
			"..#...",
			"..#...",
			"......",
		],
		"objects": [{"id": "sign", "cell": [3, 1]}],
		"npcs": [],
		"props": [],
	}


func test_walkability_from_data() -> void:
	var m = TownMap.from_data(_small())
	check(m.is_walkable(Vector2i(0, 0)), "floor walks")
	check(not m.is_walkable(Vector2i(2, 1)), "wall blocks")
	check(not m.is_walkable(Vector2i(3, 1)), "object blocks")
	check(m.is_ground(Vector2i(3, 1)), "object stands on walkable ground")
	check(not m.is_walkable(Vector2i(-1, 0)) and not m.is_walkable(Vector2i(6, 0)), "outside the map blocks")
	eq(m.thing_at(Vector2i(3, 1)), "sign", "thing lookup")
	eq(m.cell_of_thing("sign"), Vector2i(3, 1), "thing cell lookup")


func test_path_goes_around_blockers() -> void:
	var m = TownMap.from_data(_small())
	var p: Array = m.find_path(Vector2i(1, 1), Vector2i(4, 1))
	eq(p.size(), 5, "shortest path around the wall and the sign")
	eq(p[-1], Vector2i(4, 1), "path ends at the goal")
	for c in p:
		check(m.is_walkable(c), "path only uses walkable tiles")
	for i in range(1, p.size()):
		eq((p[i] - p[i - 1]).length_squared(), 1, "path steps one tile at a time")
	check(m.find_path(Vector2i(0, 0), Vector2i(2, 1)).is_empty(), "no path onto a wall")
	check(m.find_path(Vector2i(0, 0), Vector2i(0, 0)).is_empty(), "no path to where you stand")


func test_approach_picks_nearest_free_side() -> void:
	var m = TownMap.from_data(_small())
	var a: Dictionary = m.approach(Vector2i(5, 1), Vector2i(3, 1))
	eq(a["cell"], Vector2i(4, 1), "nearest free side of the sign")
	eq(a["path"], [Vector2i(4, 1)], "one step to get there")
	var b: Dictionary = m.approach(Vector2i(0, 3), Vector2i(3, 1))
	check(b["cell"] == Vector2i(3, 2) or b["cell"] == Vector2i(3, 0), "reaches the sign from below or above, not through the wall")
	check(m.is_walkable(b["cell"]), "approach tile is walkable")
	var c: Dictionary = m.approach(Vector2i(4, 1), Vector2i(3, 1))
	eq(c["cell"], Vector2i(4, 1), "already next to it: stay put")
	check(c["path"].is_empty(), "no walking needed")


func test_approach_unreachable_target() -> void:
	var def := _small()
	def["map"] = ["..#.#.", "..###.", "......", "......"]
	def["objects"] = [{"id": "boxed", "cell": [3, 0]}]
	var m = TownMap.from_data(def)
	check(m.approach(Vector2i(0, 3), Vector2i(3, 0)).is_empty(), "boxed-in target cannot be approached")


func test_every_town_interaction_is_reachable_from_the_start() -> void:
	var def: Dictionary = GameData.get_json("town")
	var m = TownMap.from_data(def)
	var start := TownMap.cell_of(def["player"]["cell"])
	check(m.is_walkable(start), "player starts on a walkable tile")
	for t in def["npcs"] + def["objects"]:
		var a: Dictionary = m.approach(start, TownMap.cell_of(t["cell"]))
		check(not a.is_empty(), "%s can be reached" % t["id"])
		check(t.has("interaction") and GameData.get_json("dialogue").has(t["interaction"]), "%s has dialogue" % t["id"])


func test_town_map_rows_and_tiles_are_consistent() -> void:
	var def: Dictionary = GameData.get_json("town")
	var w: int = def["map"][0].length()
	for r in def["map"]:
		eq(r.length(), w, "town map rows have equal width")
		for ch in r:
			check(def["tiles"].has(ch), "tile '%s' is in the legend" % ch)
	var m = TownMap.from_data(def)
	for t in def["npcs"] + def["objects"] + def["props"]:
		check(m.is_ground(TownMap.cell_of(t["cell"])), "thing at %s stands on ground" % str(t["cell"]))


func test_facing() -> void:
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(2, 1)), "up", "up")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(2, 3)), "down", "down")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(1, 2)), "left", "left")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(3, 2)), "right", "right")
