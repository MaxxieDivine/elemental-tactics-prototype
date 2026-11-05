## Town grid: walkability, paths, and finding a tile next to a target.
extends "res://tests/test_base.gd"

const TownMap = preload("res://scripts/core/town_map.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")


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


func _map_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/maps/"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## Every cell the player can arrive at on a map (the start, exit arrivals).
func _arrivals(map_id: String) -> Array:
	var out: Array = []
	var start: Dictionary = GameSession.start_spot()
	if start["map"] == map_id:
		out.append(start["cell"])
	for other in _map_ids():
		for e in TownMap.map_def(other).get("exits", []):
			if e["to"] == map_id:
				out.append(TownMap.cell_of(e["arrive"]))
	return out


func test_inn_maps_exist() -> void:
	var ids := _map_ids()
	for id in ["town", "lobby", "lounge", "hallway", "room_1"]:
		check(ids.has(id), "map %s exists in data/maps" % id)
	eq(GameSession.start_spot()["map"], "town", "play starts in town")


func test_map_rows_and_tiles_are_consistent() -> void:
	for id in _map_ids():
		var def: Dictionary = TownMap.map_def(id)
		var w: int = def["map"][0].length()
		for r in def["map"]:
			eq(r.length(), w, "%s: rows have equal width" % id)
			for ch in r:
				check(def["tiles"].has(ch), "%s: tile '%s' is in the legend" % [id, ch])
		var m = TownMap.from_data(def)
		for n in def.get("npcs", []):
			check(m.is_ground(TownMap.cell_of(n["cell"])), "%s: %s stands on ground" % [id, n["id"]])
		for e in def.get("exits", []):
			for c in TownMap.exit_cells_of(e):
				check(m.in_bounds(c) and not m.is_ground(c), "%s: exit %s is on a door/stairs tile, not floor" % [id, e["id"]])


func test_every_exit_leads_to_a_walkable_arrival_with_a_facing() -> void:
	for id in _map_ids():
		for e in TownMap.map_def(id).get("exits", []):
			var a := TownMap.arrival(e)
			var to = TownMap.load_map(a["map"])
			check(to != null, "%s: exit %s leads to existing map '%s'" % [id, e["id"], a["map"]])
			if to == null:
				continue
			check(to.is_walkable(a["cell"]), "%s: exit %s arrives on a free walkable tile" % [id, e["id"]])
			check(a["facing"] in ["up", "down", "left", "right"], "%s: exit %s has a facing" % [id, e["id"]])
			# Every exit has a way back from where it arrives.
			var back := false
			for e2 in TownMap.map_def(a["map"]).get("exits", []):
				back = back or e2["to"] == id
			check(back, "%s: %s's map %s leads back here" % [id, e["id"], a["map"]])


func test_every_map_is_reachable_through_exits() -> void:
	var seen := {GameSession.start_spot()["map"]: true}
	var queue: Array = seen.keys()
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for e in TownMap.map_def(id).get("exits", []):
			if not seen.has(e["to"]):
				seen[e["to"]] = true
				queue.append(e["to"])
	for id in _map_ids():
		check(seen.has(id), "map %s is reachable from the start" % id)


func test_every_target_is_usable_from_every_arrival() -> void:
	for id in _map_ids():
		var m = TownMap.load_map(id)
		for from in _arrivals(id):
			for tid in m.targets:
				var a: Dictionary = m.approach_target(from, tid)
				check(not a.is_empty(), "%s: %s can be reached from %s" % [id, tid, str(from)])
				if not a.is_empty():
					check(m.can_use_from(tid, a["cell"]), "%s: %s usable from its approach cell" % [id, tid])
		for tid in m.targets:
			var t: Dictionary = m.targets[tid]
			if t["kind"] != "exit":
				check(Dialogue.has_interaction(t["interaction"]), "%s: %s has dialogue" % [id, tid])


func test_interactive_ids_are_where_the_brief_puts_them() -> void:
	var where := {
		"town": ["welcome_banner", "letter", "cellar_hatch"],
		"lobby": ["innkeeper", "guest_book", "key_board"],
		"lounge": ["fireplace", "arcade"],
		"hallway": ["room_1_door", "room_2_door", "room_3_door", "room_4_door"],
		"room_1": ["room_1_key", "room_1_bed"],
	}
	for id in where:
		var m = TownMap.load_map(id)
		for tid in where[id]:
			check(m.targets.has(tid), "%s is in %s" % [tid, id])
	check(not TownMap.load_map("town").targets.has("innkeeper"), "the innkeeper moved out of the town")
	eq(TownMap.load_map("hallway").targets["room_1_door"]["kind"], "exit", "Room 1's door opens")
	for d in ["room_2_door", "room_3_door", "room_4_door"]:
		eq(TownMap.load_map("hallway").targets[d]["kind"], "object", "%s is locked (dialogue only)" % d)


func test_exit_target_arrival_and_facing() -> void:
	var def := _small()
	def["map"] = ["......", "..#...", "..#D..", "......"]
	def["tiles"]["D"] = {"walkable": false}
	def["exits"] = [{"id": "door", "cell": [3, 2], "to": "elsewhere", "arrive": [1, 2], "facing": "left"}]
	var m = TownMap.from_data(def)
	eq(m.target_at(Vector2i(3, 2)), "door", "tapping the door cell targets the exit")
	var a: Dictionary = m.approach_target(Vector2i(5, 3), "door")
	check(not a.is_empty() and m.can_use_from("door", a["cell"]), "walks next to the door")
	eq(a["cell"], Vector2i(3, 3), "nearest side of the door")
	eq(m.facing_to_target(a["cell"], "door"), "up", "faces the door")
	eq(TownMap.arrival(m.exit_def("door")), {"map": "elsewhere", "cell": Vector2i(1, 2), "facing": "left"}, "arrival map, cell and facing from data")
	# Real data: the inn's front door.
	var town = TownMap.load_map("town")
	var e: Dictionary = town.exit_def("inn_front_door")
	eq(TownMap.arrival(e), {"map": "lobby", "cell": TownMap.cell_of(e["arrive"]), "facing": e["facing"]}, "inn door arrival read from data")
	eq(e["to"], "lobby", "town front door leads into the lobby")
	eq(town.target_at(Vector2i(7, 3)), "inn_front_door", "both door tiles are the exit")


func test_wide_exit_and_stand_cells() -> void:
	var def := _small()
	def["exits"] = [{"id": "gate", "cells": [[0, 0], [1, 0]], "to": "x", "arrive": [0, 0]}]
	def["objects"] = [{"id": "sign", "cell": [3, 1], "interaction": "letter", "stand": [[4, 1]]}]
	var m = TownMap.from_data(def)
	check(m.can_use_from("gate", Vector2i(0, 1)) and m.can_use_from("gate", Vector2i(1, 1)), "either tile below a wide exit works")
	check(not m.can_use_from("gate", Vector2i(1, 0)), "an exit's own cell is not a standing cell")
	eq(m.approach_target(Vector2i(3, 3), "sign")["cell"], Vector2i(4, 1), "stand cells restrict where to use a thing from")
	check(not m.can_use_from("sign", Vector2i(3, 2)), "other sides do not count when stand is given")
	eq(TownMap.arrival({"to": "x", "arrive": [0, 0]})["facing"], "down", "facing defaults to down")


func test_flags_persist_across_map_changes() -> void:
	var s = GameSession.new()
	s.flags.set_flag("read_letter")
	var town = TownMap.load_map("town")
	var spot: Dictionary = s.go_through(town.exit_def("inn_front_door"))
	eq(spot["map"], "lobby", "went into the lobby")
	check(s.flags.has("read_letter"), "flags kept after entering the inn")
	var lobby = TownMap.load_map("lobby")
	s.go_through(lobby.exit_def("stairs_up"))
	eq(s.spot()["map"], "hallway", "went upstairs")
	s.flags.set_flag("won_first_fight")
	s.go_through(TownMap.load_map("hallway").exit_def("stairs_down"))
	s.go_through(lobby.exit_def("lobby_front_door"))
	eq(s.spot()["map"], "town", "back outside")
	eq(s.flags.names(), ["read_letter", "won_first_fight"], "all flags kept across several map changes")


func test_hatch_sits_against_the_inn_wall_and_is_used_from_the_side() -> void:
	var m = TownMap.load_map("town")
	var c: Vector2i = m.cell_of_thing("cellar_hatch")
	var above: Dictionary = m.tile_def(c + Vector2i(0, -1))
	eq(above.get("name", ""), "wall", "the hatch leans on the inn wall")
	var stand: Array = m.targets["cellar_hatch"]["stand"]
	check(not stand.is_empty(), "hatch has stand cells")
	for st in stand:
		eq(st.y, c.y, "Agador uses the hatch from beside it, not in front, so it stays visible")
	var a: Dictionary = m.approach_target(GameSession.start_spot()["cell"], "cellar_hatch")
	check(not a.is_empty() and a["cell"].y == c.y, "walking to the hatch ends beside it")


func test_missing_map_does_not_crash() -> void:
	check(TownMap.load_map("no_such_map") == null, "missing map gives null")
	check(TownMap.map_def("").is_empty(), "empty id gives no map")


func test_facing() -> void:
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(2, 1)), "up", "up")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(2, 3)), "down", "down")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(1, 2)), "left", "left")
	eq(TownMap.facing_toward(Vector2i(2, 2), Vector2i(3, 2)), "right", "right")
