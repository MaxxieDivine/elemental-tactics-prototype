## The town's walkable grid, built from data/town.json. Plain data, no Nodes.
## Knows which tiles are walkable, which cells hold an NPC/object/prop
## (they block movement), shortest 4-way paths, and where to stand to use
## something.
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]
const NO_CELL := Vector2i(-1, -1)

var size: Vector2i = Vector2i.ZERO
var rows: Array = []
var tiles: Dictionary = {}  # legend char -> tile def
var things: Dictionary = {}  # cell -> id of the NPC/object/prop standing there


## Builds the map from a town definition (data/town.json by default).
static func from_data(def: Dictionary = {}):
	if def.is_empty():
		def = GameData.get_json("town")
	var m = load("res://scripts/core/town_map.gd").new()
	m.rows = def["map"]
	m.tiles = def["tiles"]
	m.size = Vector2i(m.rows[0].length(), m.rows.size())
	for n in def.get("npcs", []):
		m.things[cell_of(n["cell"])] = n["id"]
	for o in def.get("objects", []):
		m.things[cell_of(o["cell"])] = o["id"]
	for i in def.get("props", []).size():
		m.things[cell_of(def["props"][i]["cell"])] = "prop_%d" % i
	return m


static func cell_of(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


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


## Cell of a thing by id (NO_CELL if absent).
func cell_of_thing(id: String) -> Vector2i:
	for c in things:
		if things[c] == id:
			return c
	return NO_CELL


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
## (4-way) with the shortest path from `from`. Returns
## {"cell": Vector2i, "path": Array} or {} when no side can be reached.
## Ties prefer standing below the target (facing it from the front).
func approach(from: Vector2i, target: Vector2i) -> Dictionary:
	var best := {}
	for d in DIRS:
		var c: Vector2i = target + d
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


## "up", "down", "left" or "right" for a step or a look from a to b.
static func facing_toward(a: Vector2i, b: Vector2i) -> String:
	var d := b - a
	if absi(d.x) > absi(d.y):
		return "right" if d.x > 0 else "left"
	if d.y != 0:
		return "down" if d.y > 0 else "up"
	return ""
