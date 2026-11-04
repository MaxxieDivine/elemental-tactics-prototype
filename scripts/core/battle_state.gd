## The whole fight as plain data: grid terrain, surfaces, units, round and phase.
## Also owns grid queries (movement range, paths, line of sight).
extends RefCounted

const Unit = preload("res://scripts/core/unit.gd")

enum Terrain { FLOOR, WALL, BARREL }
enum Surface { NONE, WATER, OIL, STEAM }

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var width: int = 10
var height: int = 10
var terrain: Array = []
var surface: Array = []
var steam_timer: Array = []
var units: Array = []
var round_num: int = 1
var phase: String = "player"  # player, enemy, won, lost
var next_unit_id: int = 1


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
	return s


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


func set_surface(c: Vector2i, s: int, timer: int = 0) -> void:
	surface[idx(c)] = s
	steam_timer[idx(c)] = timer


## Walls, barrels and the map edge stop movement and pushes.
func is_obstacle(c: Vector2i) -> bool:
	return not in_bounds(c) or get_terrain(c) != Terrain.FLOOR


func blocks_sight(c: Vector2i) -> bool:
	return get_terrain(c) == Terrain.WALL or get_surface(c) == Surface.STEAM


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
## enemies, and may only stop on empty tiles.
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
			if info.has(n) or is_obstacle(n):
				continue
			var other = unit_at(n)
			if other != null and other.team != u.team:
				continue
			info[n] = {"dist": d + 1, "prev": c, "stop": other == null}
			frontier.append(n)
	return info


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
