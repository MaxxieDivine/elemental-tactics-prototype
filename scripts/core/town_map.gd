## One walkable map (the town, the lobby, a bedroom...), built from data.
## Plain data, no Nodes. Knows which tiles are walkable, what stands where
## (NPCs/objects/props block movement), the exits to other maps, shortest
## 4-way paths, and where to stand to use something.
##
## Map files live in data/maps/<id>.json. The shared tile legend, tile size
## and start position live in data/town.json. NPCs and objects can appear,
## disappear, move or change with story flags through their "states" (see
## WorldState); a map is always built for one set of flags. An object or
## prop bigger than a tile lists the extra cells it blocks in "footprint".
## A map may also list "triggers": zones that start an interaction when the
## player walks onto one of their cells (see trigger_at).
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")
const WorldState = preload("res://scripts/core/world_state.gd")
const Pacer = preload("res://scripts/core/pacer.gd")

const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]
const NO_CELL := Vector2i(-1, -1)

var id: String = ""
## The map definition as built: world state already applied for the flags
## (hidden things removed, the winning state's cell/look/pace filled in).
var def: Dictionary = {}
var size: Vector2i = Vector2i.ZERO
var rows: Array = []
var tiles: Dictionary = {}  # legend char -> tile def
var things: Dictionary = {}  # cell -> id of the NPC/object/prop standing there (blocks)
## Things the player can tap and use: id -> {"kind": "npc"/"object"/"exit",
## "cells": [Vector2i], "stand": [Vector2i], "interaction": String, "def": Dictionary}
var targets: Dictionary = {}
var exit_cells: Dictionary = {}  # cell -> exit id
var pacers: Dictionary = {}  # NPC id -> Pacer, for NPCs whose state has "pace"
## Trigger zones as written in data: {"id", "cells"/"cell", "interaction",
## optional "requires", "unless", "time_of_day", "once", "facing"}.
var triggers: Array = []


## The world file: tile legend, tile size, tuning and the start position.
static func world() -> Dictionary:
	return GameData.get_json("town")


## The map definition for an id (data/maps/<id>.json), with the shared tile
## legend filled in. {} if there is no such map.
static func map_def(map_id: String) -> Dictionary:
	if map_id == "" or not FileAccess.file_exists("res://data/maps/%s.json" % map_id):
		return {}
	var d: Dictionary = GameData.get_json("maps/" + map_id).duplicate()
	if not d.has("tiles"):
		d["tiles"] = world()["tiles"]
	d["id"] = map_id
	return d


## Builds a map by id (see map_def) as it is for these story flags (null:
## no flags set). Null if the map does not exist.
static func load_map(map_id: String, flags = null):
	var d := map_def(map_id)
	if d.is_empty():
		push_warning("Map '%s' does not exist (expected data/maps/%s.json)." % [map_id, map_id])
		return null
	return from_data(d, flags)


## Builds a map from a definition: "map" rows, "tiles" legend, and optional
## "npcs", "objects", "props" and "exits" lists. NPC/object "states" are
## resolved for `flags` first (null: no flags set).
static func from_data(raw: Dictionary, flags = null):
	var md := WorldState.apply(raw, flags)
	var m = load("res://scripts/core/town_map.gd").new()
	m.def = md
	m.id = str(md.get("id", ""))
	m.rows = md["map"]
	m.tiles = md["tiles"]
	m.size = Vector2i(m.rows[0].length(), m.rows.size())
	for n in md.get("npcs", []):
		var c := cell_of(n["cell"])
		if n.get("pace", []).size() > 0:
			var p = Pacer.new(n["pace"], c)
			m.pacers[n["id"]] = p
			c = p.cell  # a pacer starts on its route
		m.things[c] = n["id"]
		m._add_target(n, "npc", [c])
	for o in md.get("objects", []):
		var cells := cells_of_thing(o)
		for c in cells:
			m.things[c] = o["id"]
		if str(o.get("interaction", "")) != "":
			m._add_target(o, "object", cells)  # scenery (a ferry offshore) is not a target
	for i in md.get("props", []).size():
		for c in cells_of_thing(md["props"][i]):
			m.things[c] = "prop_%d" % i
	for e in md.get("exits", []):
		var cells := exit_cells_of(e)
		for c in cells:
			m.exit_cells[c] = e["id"]
		m._add_target(e, "exit", cells)
	m.triggers = md.get("triggers", []).duplicate(true)
	return m


static func cell_of(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## Every cell an object or prop blocks: its "cell", then its "footprint"
## (cells relative to it, for things bigger than one tile, like a building).
static func cells_of_thing(t: Dictionary) -> Array:
	var c := cell_of(t["cell"])
	var out: Array = [c]
	for off in t.get("footprint", []):
		var f: Vector2i = c + cell_of(off)
		if not out.has(f):
			out.append(f)
	return out


## An exit's cells: "cells" (a list) or a single "cell".
static func exit_cells_of(e: Dictionary) -> Array:
	if e.has("cells"):
		return e["cells"].map(func(a): return cell_of(a))
	return [cell_of(e["cell"])]


func _add_target(d: Dictionary, kind: String, cells: Array) -> void:
	targets[d["id"]] = {
		"kind": kind,
		"cells": cells,
		"stand": _stand_cells(d, cells),
		"interaction": str(d.get("interaction", "")),
		"def": d,
	}


## A target's "stand" cells from data, else every side of its cells.
static func _stand_cells(d: Dictionary, cells: Array) -> Array:
	if d.has("stand"):
		return d["stand"].map(func(a): return cell_of(a))
	var stand: Array = []
	for c in cells:
		for dir in DIRS:
			if not cells.has(c + dir) and not stand.has(c + dir):
				stand.append(c + dir)
	return stand


## One pacing step for NPC `thing_id`: moves it to the next cell of its
## route unless that cell is not walkable or `blocked.call(cell)` is true
## (then it turns around). Returns true when it moved.
func step_pacer(thing_id: String, blocked: Callable = func(_c): return false) -> bool:
	var p = pacers.get(thing_id)
	if p == null:
		return false
	var from: Vector2i = p.cell
	if not p.step(func(c): return not is_walkable(c) or blocked.call(c)):
		return false
	move_thing(thing_id, p.cell)
	return from != p.cell


## Moves an NPC/object to another cell (a pacing NPC's step). Its old cell
## frees up and the cells to use it from follow it.
func move_thing(thing_id: String, to: Vector2i) -> void:
	var from := cell_of_thing(thing_id)
	if from == to or from == NO_CELL:
		return
	if things.get(from, "") == thing_id:
		things.erase(from)
	things[to] = thing_id
	if targets.has(thing_id) and targets[thing_id]["kind"] != "exit":
		var t: Dictionary = targets[thing_id]
		t["cells"] = [to]
		t["stand"] = _stand_cells(t["def"], [to])


## The trigger zone that starts when the player steps onto `c` now ({} if
## none): its cells include `c`, its rule matches these flags (requires,
## unless, time_of_day), and a "once" trigger has not run yet. The caller
## marks a once trigger as run (flags.mark_ran) when it starts it.
func trigger_at(c: Vector2i, flags) -> Dictionary:
	for t in triggers:
		if not exit_cells_of(t).has(c) or not flags.meets_rule(t):
			continue
		if bool(t.get("once", false)) and flags.has_run(str(t["id"])):
			continue
		return t
	return {}


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func tile_char(c: Vector2i) -> String:
	return rows[c.y][c.x] if in_bounds(c) else ""


func tile_def(c: Vector2i) -> Dictionary:
	return tiles.get(tile_char(c), {})


## Ground you could stand on, ignoring NPCs/objects.
func is_ground(c: Vector2i) -> bool:
	return in_bounds(c) and bool(tile_def(c).get("walkable", false))


## Ground with nothing standing on it.
func is_walkable(c: Vector2i) -> bool:
	return is_ground(c) and not things.has(c)


func thing_at(c: Vector2i) -> String:
	return things.get(c, "")


## Cell of a thing or target by id (NO_CELL if absent). For a wide exit,
## its first cell.
func cell_of_thing(thing_id: String) -> Vector2i:
	if targets.has(thing_id):
		return targets[thing_id]["cells"][0]
	for c in things:
		if things[c] == thing_id:
			return c
	return NO_CELL


## The exit definition for an id ({} if none).
func exit_def(exit_id: String) -> Dictionary:
	var t: Dictionary = targets.get(exit_id, {})
	return t["def"] if t.get("kind", "") == "exit" else {}


## Where an exit leads: {"map", "cell", "facing"} straight from its data.
static func arrival(exit: Dictionary) -> Dictionary:
	return {"map": str(exit["to"]), "cell": cell_of(exit["arrive"]), "facing": str(exit.get("facing", "down"))}


## What a tap on cell `c` means: the id of an exit, or of an NPC/object
## with an interaction ("" for plain ground). Sprites stand up to about one
## tile above their own, so a tap on the blocked tile just above an NPC or
## object (a wall behind the innkeeper, say) also counts.
func target_at(c: Vector2i) -> String:
	if exit_cells.has(c):
		return exit_cells[c]
	var here: String = thing_at(c)
	if here != "" and _usable(here):
		return here
	var below: String = thing_at(c + Vector2i(0, 1))
	if below != "" and _usable(below) and not is_walkable(c):
		return below
	return ""


func _usable(thing_id: String) -> bool:
	var t: Dictionary = targets.get(thing_id, {})
	return t.get("kind", "") == "exit" or t.get("interaction", "") != ""


## True when standing on `c` lets the player use the target.
func can_use_from(thing_id: String, c: Vector2i) -> bool:
	return targets.has(thing_id) and targets[thing_id]["stand"].has(c)


## Shortest 4-way path from `from` to `to`, excluding `from` and including
## `to`. Empty when already there or unreachable.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if from == to or not is_walkable(to):
		return []
	var prev := {from: from}
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if not prev.has(n) and is_walkable(n):
				prev[n] = c
				queue.append(n)
	if not prev.has(to):
		return []
	var path: Array = []
	var c: Vector2i = to
	while c != from:
		path.push_front(c)
		c = prev[c]
	return path


## Where to stand to use the thing on `target`: the free tile next to it
## (4-way, or the `stand` cells given) with the shortest path from `from`.
## Returns {"cell": Vector2i, "path": Array} or {} when none can be reached.
## Ties prefer the first candidate (standing below the target by default).
func approach(from: Vector2i, target: Vector2i, stand: Array = []) -> Dictionary:
	var cands: Array = stand if not stand.is_empty() else DIRS.map(func(d): return target + d)
	var best := {}
	for c in cands:
		var path: Array
		if c == from:
			path = []
		elif is_walkable(c):
			path = find_path(from, c)
			if path.is_empty():
				continue
		else:
			continue
		if best.is_empty() or path.size() < best["path"].size():
			best = {"cell": c, "path": path}
	return best


## approach() for a target by id, using its stand cells.
func approach_target(from: Vector2i, thing_id: String) -> Dictionary:
	if not targets.has(thing_id):
		return {}
	var t: Dictionary = targets[thing_id]
	return approach(from, t["cells"][0], t["stand"])


## Which way to face to use a target from `c`: toward its nearest cell.
func facing_to_target(c: Vector2i, thing_id: String) -> String:
	var best: Vector2i = cell_of_thing(thing_id)
	for tc in targets.get(thing_id, {}).get("cells", []):
		if (tc - c).length_squared() < (best - c).length_squared():
			best = tc
	return facing_toward(c, best)


## "up", "down", "left" or "right" for a step or a look from a to b.
static func facing_toward(a: Vector2i, b: Vector2i) -> String:
	var d := b - a
	if absi(d.x) > absi(d.y):
		return "right" if d.x > 0 else "left"
	if d.y != 0:
		return "down" if d.y > 0 else "up"
	return ""
