## Builds a BattleState from an encounter in data/encounters.json + unit data.
##
## An encounter describes the whole fight in data:
##   "map" rows + "legend" (char -> terrain tile or surface name): the board
##   "terrain"   overrides for data/terrain.json in this fight only (tiles,
##               surfaces, reactions; merged key by key)
##   "objects"   [{"type": terrain tile name, "cell": [x, y]}] placed on the board
##   "party" (or "heroes") [{"id", "cell"}], "enemies" [{"type", "cell"}]
##   "seed"      the fight's RNG seed
##   "presentation", "return": read by the view and GameSession, not here.
extends RefCounted

const BattleState = preload("res://scripts/core/battle_state.gd")
const Unit = preload("res://scripts/core/unit.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")


## Builds the encounter with this id from data/encounters.json.
static func build_encounter(encounter_id: String = GameData.DEFAULT_ENCOUNTER) -> Object:
	return build(GameData.encounter(encounter_id))


## The terrain rules for an encounter: data/terrain.json with its overrides.
static func terrain_for(level: Dictionary) -> Dictionary:
	var base: Dictionary = GameData.get_json("terrain")
	if not level.has("terrain"):
		return base
	return GameData.deep_merge(base, level["terrain"])


static func build(level: Dictionary = {}) -> Object:
	if level.is_empty():
		level = GameData.encounter()
	var rows: Array = level["map"]
	var state = BattleState.new()
	state.terrain_data = terrain_for(level)
	for k in state.terrain_data["tiles"]:
		BattleState.terrain_index(k)
	state.setup(rows[0].length(), rows.size())
	state.seed_rng(int(level.get("seed", 0)))
	var legend: Dictionary = level["legend"]
	for y in rows.size():
		for x in rows[y].length():
			_place(state, Vector2i(x, y), str(legend.get(rows[y][x], "floor")))
	for o in level.get("objects", []):
		_place(state, _cell(o["cell"]), str(o["type"]))
	for h in level.get("party", level.get("heroes", [])):
		state.add_unit(make_hero(h["id"], _cell(h["cell"])))
	for e in level.get("enemies", []):
		state.add_unit(make_enemy(e["type"], _cell(e["cell"])))
	EnemyAI.plan_all(state)
	return state


## Puts a terrain tile or a surface (by name) on a cell. "floor" and unknown
## names leave plain floor.
static func _place(state, c: Vector2i, name: String) -> void:
	var s := BattleState.SURFACE_NAMES.find(name)
	if s > 0:
		state.set_surface(c, s)
	elif name != "floor" and state.terrain_data["tiles"].has(name):
		state.set_terrain(c, BattleState.terrain_index(name))


static func make_hero(id: String, cell: Vector2i):
	var d := GameData.hero(id)
	var u = Unit.new()
	u.type_id = id
	u.team = "hero"
	u.name = d["name"]
	u.cell = cell
	u.max_hp = int(d["hp"])
	u.hp = u.max_hp
	u.move = int(d["move"])
	u.abilities = d["abilities"].duplicate()
	for a in u.abilities:
		var ab := GameData.ability(a)
		if ab.has("uses"):
			u.uses[a] = int(ab["uses"])
	u.avoids = d.get("avoids", []).duplicate()
	u.carries = str(d.get("carries", ""))
	return u


static func make_enemy(type_id: String, cell: Vector2i):
	var d := GameData.enemy(type_id)
	var u = Unit.new()
	u.type_id = type_id
	u.team = "enemy"
	u.name = d["name"]
	u.cell = cell
	u.max_hp = int(d["hp"])
	u.hp = u.max_hp
	u.move = int(d["move"])
	u.abilities = [d["attack"]]
	u.avoids = d.get("avoids", []).duplicate()
	u.carries = str(d.get("carries", ""))
	return u


static func _cell(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
