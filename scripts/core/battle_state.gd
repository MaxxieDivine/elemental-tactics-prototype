## The whole fight as plain data: grid terrain, surfaces, units, round, phase
## and the seeded RNG. No Nodes. Also owns grid queries (movement range,
## paths, line of sight). What each tile/surface does comes from terrain.json.
extends RefCounted

const Unit = preload("res://scripts/core/unit.gd")
const GameData = preload("res://scripts/core/game_data.gd")

enum Terrain { FLOOR, WALL, BARREL }
enum Surface { NONE, WATER, OIL, STEAM }
## Names match the keys in data/terrain.json. Tiles beyond these three (a
## lantern, say) get the next numbers, in the order terrain.json lists them
## (see terrain_names()).
const TERRAIN_NAMES: Array[String] = ["floor", "wall", "barrel"]
const SURFACE_NAMES: Array[String] = ["none", "water", "oil", "steam"]

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var width: int = 10
var height: int = 10
var terrain: Array = []
var surface: Array = []
var steam_timer: Array = []  # rounds left for surfaces with a duration
var units: Array = []
var round_num: int = 1
var phase: String = "player"  # player, enemy, won, lost
var next_unit_id: int = 1
## All gameplay randomness must go through rand_int() so that cloned states
## (used for previews) roll exactly the same results as the real one.
var rng_seed: int = 0
var rng_state: int = 0
## What tiles, surfaces and element reactions do in this fight: data/terrain.json
## with the encounter's own "terrain" overrides laid over it (see LevelLoader).
## Shared (read-only) between clones.
var terrain_data: Dictionary = {}

static var _terrain_names: Array = []


func setup(w: int, h: int) -> void:
	width = w
	height = h
	terrain.clear()
	surface.clear()
	steam_timer.clear()
	for i in w * h:
		terrain.append(Terrain.FLOOR)
		surface.append(Surface.NONE)
		steam_timer.append(0)


func clone():
	var s = get_script().new()
	s.width = width
	s.height = height
	s.terrain = terrain.duplicate()
	s.surface = surface.duplicate()
	s.steam_timer = steam_timer.duplicate()
	for u in units:
		s.units.append(u.clone())
	s.round_num = round_num
	s.phase = phase
	s.next_unit_id = next_unit_id
	s.rng_seed = rng_seed
	s.rng_state = rng_state
	s.terrain_data = terrain_data
	return s


# --- randomness ------------------------------------------------------------

func seed_rng(seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	rng_seed = seed_value
	rng_state = r.state


## Inclusive random integer from the fight's own RNG.
func rand_int(lo: int, hi: int) -> int:
	var r := RandomNumberGenerator.new()
	r.state = rng_state
	var v := r.randi_range(lo, hi)
	rng_state = r.state
	return v


# --- cells -----------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func idx(c: Vector2i) -> int:
	return c.y * width + c.x


func get_terrain(c: Vector2i) -> int:
	return terrain[idx(c)] if in_bounds(c) else Terrain.WALL


func set_terrain(c: Vector2i, t: int) -> void:
	terrain[idx(c)] = t


func get_surface(c: Vector2i) -> int:
	return surface[idx(c)] if in_bounds(c) else Surface.NONE


## timer < 0 uses the surface's "duration" from terrain.json (0 = permanent).
func set_surface(c: Vector2i, s: int, timer: int = -1) -> void:
	if timer < 0:
		timer = int(surface_info(s).get("duration", 0))
	surface[idx(c)] = s
	steam_timer[idx(c)] = timer


## Every terrain tile name by number: floor, wall, barrel, then any other
## tile in data/terrain.json (or added by an encounter), in order.
static func terrain_names() -> Array:
	if _terrain_names.is_empty():
		for n in TERRAIN_NAMES:
			_terrain_names.append(n)
		for k in GameData.get_json("terrain")["tiles"]:
			if not _terrain_names.has(k):
				_terrain_names.append(k)
	return _terrain_names


## The number for a terrain tile name (new names get the next number).
static func terrain_index(name: String) -> int:
	var names := terrain_names()
	if not names.has(name):
		names.append(name)
	return names.find(name)


static func terrain_name(t: int) -> String:
	var names := terrain_names()
	return names[t] if t >= 0 and t < names.size() else "floor"


## Global definitions (data/terrain.json only, no encounter overrides).
static func terrain_def(t: int) -> Dictionary:
	return GameData.get_json("terrain")["tiles"].get(terrain_name(t), {})


static func surface_def(s: int) -> Dictionary:
	return GameData.surface(SURFACE_NAMES[s])


func _terrain_rules() -> Dictionary:
	return terrain_data if not terrain_data.is_empty() else GameData.get_json("terrain")


## This fight's definition of a terrain tile (with encounter overrides).
func tile_info(t: int) -> Dictionary:
	return _terrain_rules()["tiles"].get(terrain_name(t), {})


## This fight's definition of a surface (with encounter overrides).
func surface_info(s: int) -> Dictionary:
	return _terrain_rules()["surfaces"].get(SURFACE_NAMES[s], {})


## What an element does to a surface in this fight ({} if nothing).
func reaction(element: String, s: int) -> Dictionary:
	return _terrain_rules()["reactions"].get(element, {}).get(SURFACE_NAMES[s], {})


## Map edge and tiles with blocks_move (walls, barrels) stop movement and pushes.
func is_obstacle(c: Vector2i) -> bool:
	return not in_bounds(c) or tile_info(get_terrain(c)).get("blocks_move", false)


func blocks_sight(c: Vector2i) -> bool:
	return tile_info(get_terrain(c)).get("blocks_sight", false) or surface_info(get_surface(c)).get("blocks_sight", false)


# --- units -----------------------------------------------------------------

func add_unit(u) -> void:
	u.id = next_unit_id
	next_unit_id += 1
	units.append(u)


func unit_at(c: Vector2i):
	for u in units:
		if u.alive and u.cell == c:
			return u
	return null


func unit_by_id(id: int):
	for u in units:
		if u.id == id:
			return u
	return null


func living(team: String) -> Array:
	var out: Array = []
	for u in units:
		if u.alive and u.team == team:
			out.append(u)
	return out


# --- queries ---------------------------------------------------------------

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## BFS over the unit's move range. Units may pass through allies but not
## enemies, and may only stop on empty tiles. A unit never steps onto a
## surface it avoids (its data "avoids", e.g. rats and oil).
## Returns {cell: {"dist": int, "prev": Vector2i, "stop": bool}}.
func reachable(u) -> Dictionary:
	var info := {u.cell: {"dist": 0, "prev": u.cell, "stop": true}}
	var frontier: Array = [u.cell]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		var d: int = info[c]["dist"]
		if d >= u.move:
			continue
		for dir in DIRS:
			var n: Vector2i = c + dir
			if info.has(n) or is_obstacle(n) or avoids_cell(u, n):
				continue
			var other = unit_at(n)
			if other != null and other.team != u.team:
				continue
			info[n] = {"dist": d + 1, "prev": c, "stop": other == null}
			frontier.append(n)
	return info


## True when the unit will not walk onto this cell by itself.
func avoids_cell(u, c: Vector2i) -> bool:
	return not u.avoids.is_empty() and u.avoids.has(SURFACE_NAMES[get_surface(c)])


func move_destinations(u) -> Array:
	var out: Array = []
	var info := reachable(u)
	for c in info:
		if info[c]["stop"] and c != u.cell:
			out.append(c)
	return out


static func path_from(info: Dictionary, dest: Vector2i) -> Array:
	if not info.has(dest):
		return []
	var path: Array = [dest]
	var c: Vector2i = dest
	while info[c]["prev"] != c:
		c = info[c]["prev"]
		path.push_front(c)
	return path


## Line of sight between tile centres. Walls and steam block; the start and
## end tiles themselves never block.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var from := Vector2(a) + Vector2(0.5, 0.5)
	var to := Vector2(b) + Vector2(0.5, 0.5)
	var steps := int(ceil(from.distance_to(to) * 6.0))
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var c := Vector2i(floori(p.x), floori(p.y))
		if c == a or c == b:
			continue
		if blocks_sight(c):
			return false
	return true


## Cells of the same surface connected orthogonally to start.
func surface_component(start: Vector2i, s: int) -> Array:
	if get_surface(start) != s:
		return []
	var seen := {start: true}
	var out: Array = [start]
	var i := 0
	while i < out.size():
		var c: Vector2i = out[i]
		i += 1
		for dir in DIRS:
			var n: Vector2i = c + dir
			if in_bounds(n) and not seen.has(n) and get_surface(n) == s:
				seen[n] = true
				out.append(n)
	return out


## Tiles connected to start through surfaces that conduct this element.
func conductive_component(start: Vector2i, element: String) -> Array:
	var s: int = get_surface(start)
	if surface_info(s).get("conducts", "") != element:
		return []
	return surface_component(start, s)
