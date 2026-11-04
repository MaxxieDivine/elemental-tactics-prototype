## Builds a BattleState from data/level.json + unit data.
extends RefCounted

const BattleState = preload("res://scripts/core/battle_state.gd")
const Unit = preload("res://scripts/core/unit.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")


static func build(level: Dictionary = {}) -> Object:
	if level.is_empty():
		level = GameData.level()
	var rows: Array = level["map"]
	var state = BattleState.new()
	state.setup(rows[0].length(), rows.size())
	var legend: Dictionary = level["legend"]
	for y in rows.size():
		for x in rows[y].length():
			var c := Vector2i(x, y)
			match legend.get(rows[y][x], "floor"):
				"wall": state.set_terrain(c, BattleState.Terrain.WALL)
				"barrel": state.set_terrain(c, BattleState.Terrain.BARREL)
				"oil": state.set_surface(c, BattleState.Surface.OIL)
				"water": state.set_surface(c, BattleState.Surface.WATER)
	for h in level.get("heroes", []):
		state.add_unit(make_hero(h["id"], _cell(h["cell"])))
	for e in level.get("enemies", []):
		state.add_unit(make_enemy(e["type"], _cell(e["cell"])))
	EnemyAI.plan_all(state)
	return state


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
	return u


static func _cell(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
