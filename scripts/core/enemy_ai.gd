## Enemy planning. Intents are chosen at the start of each player phase and
## shown to the player; they execute during the enemy phase.
## An intent is a destination tile plus a fixed target tile: if the hero
## leaves that tile the attack hits whatever is there instead (or nothing).
extends RefCounted

const BattleState = preload("res://scripts/core/battle_state.gd")
const GameData = preload("res://scripts/core/game_data.gd")


static func plan_all(state) -> void:
	var claimed := {}
	var order := 1
	for e in state.living("enemy"):
		plan(state, e, claimed)
		e.order = order
		order += 1


static func can_attack_from(state, from: Vector2i, target: Vector2i, ab: Dictionary) -> bool:
	var d := BattleState.manhattan(from, target)
	if d < 1 or d > int(ab["range"]):
		return false
	return not ab["los"] or state.has_los(from, target)


static func plan(state, e, claimed: Dictionary) -> void:
	var ab := GameData.ability(e.abilities[0])
	var info: Dictionary = state.reachable(e)
	var candidates: Array = []
	for c in info:
		if info[c]["stop"] and not claimed.has(c):
			candidates.append(c)
	var heroes: Array = state.living("hero")

	# 1) Attack the weakest hero we can reach, moving as little as possible.
	var best_score := INF
	var best_cell: Vector2i = e.cell
	var best_hero = null
	for c in candidates:
		for h in heroes:
			if can_attack_from(state, c, h.cell, ab):
				var score: float = h.hp * 10 + info[c]["dist"]
				if score < best_score:
					best_score = score
					best_cell = c
					best_hero = h
	if best_hero != null:
		e.intent = {"move_to": best_cell, "has_target": true, "target": best_hero.cell, "target_name": best_hero.name}
		claimed[best_cell] = true
		return

	# 2) Otherwise close the distance to the nearest hero.
	var dist_map := _distance_to_heroes(state, heroes, e)
	var best_d := INF
	for c in candidates:
		var d: float = dist_map.get(c, 999) * 10 + info[c]["dist"]
		if d < best_d:
			best_d = d
			best_cell = c
	e.intent = {"move_to": best_cell, "has_target": false, "target": best_cell, "target_name": ""}
	claimed[best_cell] = true


## Multi-source BFS distance from every hero, ignoring units (and, for an
## enemy that avoids some surfaces, around those).
static func _distance_to_heroes(state, heroes: Array, e = null) -> Dictionary:
	var dist := {}
	var frontier: Array = []
	for h in heroes:
		dist[h.cell] = 0
		frontier.append(h.cell)
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for dir in BattleState.DIRS:
			var n: Vector2i = c + dir
			if dist.has(n) or state.is_obstacle(n) or (e != null and state.avoids_cell(e, n)):
				continue
			dist[n] = dist[c] + 1
			frontier.append(n)
	return dist


## What the intent would do if executed right now: the path the enemy would
## walk and whether the attack would still connect (range + line of sight).
## Used both for execution and for the on-screen preview.
static func resolve_intent(state, e) -> Dictionary:
	var info: Dictionary = state.reachable(e)
	var dest: Vector2i = e.intent.get("move_to", e.cell)
	if not (info.has(dest) and info[dest]["stop"]):
		# Planned tile is blocked now: take the closest reachable tile to it.
		var best := INF
		for c in info:
			if info[c]["stop"]:
				var d: float = BattleState.manhattan(c, dest) * 10 + info[c]["dist"]
				if d < best:
					best = d
					dest = c
	var path: Array = BattleState.path_from(info, dest)
	var ab := GameData.ability(e.abilities[0])
	var has_target: bool = e.intent.get("has_target", false)
	var target: Vector2i = e.intent.get("target", dest)
	var ok := has_target and can_attack_from(state, dest, target, ab)
	return {"path": path, "dest": dest, "has_target": has_target, "target": target, "attack_ok": ok}
