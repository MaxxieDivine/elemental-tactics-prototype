## Tiny assertion helpers + map builder shared by test suites.
extends RefCounted

const BattleState = preload("res://scripts/core/battle_state.gd")
const Rules = preload("res://scripts/core/rules.gd")
const LevelLoader = preload("res://scripts/core/level_loader.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")
const Commands = preload("res://scripts/core/commands.gd")

const WATER := BattleState.Surface.WATER
const OIL := BattleState.Surface.OIL
const STEAM := BattleState.Surface.STEAM
const NONE := BattleState.Surface.NONE
const BARREL := BattleState.Terrain.BARREL
const FLOOR := BattleState.Terrain.FLOOR

var failures: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(a, b, msg: String) -> void:
	if a != b:
		failures.append("%s (expected %s, got %s)" % [msg, str(b), str(a)])


## Builds a small test fight. heroes/enemies: [[id_or_type, x, y], ...]
func make(map: Array, heroes: Array = [], enemies: Array = []):
	var lv := {
		"legend": {".": "floor", "#": "wall", "o": "oil", "w": "water", "B": "barrel"},
		"map": map,
		"heroes": heroes.map(func(h): return {"id": h[0], "cell": [h[1], h[2]]}),
		"enemies": enemies.map(func(e): return {"type": e[0], "cell": [e[1], e[2]]}),
	}
	return LevelLoader.build(lv)


func at(state, x: int, y: int):
	return state.unit_at(Vector2i(x, y))


func hero(state, id: String):
	for u in state.units:
		if u.type_id == id:
			return u
	return null


func types(events: Array) -> Array:
	return events.map(func(e): return e["type"])


func ab_dmg(id: String) -> int:
	return int(GameData.ability(id)["damage"])


func steam_turns() -> int:
	return int(GameData.surface("steam")["duration"])


func oil_damage() -> int:
	return int(GameData.reaction("fire", "oil")["damage"])


func barrel_damage() -> int:
	return int(GameData.tile("barrel")["blast_damage"])
