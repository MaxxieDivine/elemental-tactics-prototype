## Combat rules. Every action mutates the BattleState immediately and returns
## an ordered list of event dictionaries describing what happened, in the
## order it happened. The view replays those events; it never decides rules.
##
## Event types: move, push, cast, damage, death, status, surface, terrain,
## explosion, flash, text, pause, phase, enemy_turn, game_over.
extends RefCounted

const BattleState = preload("res://scripts/core/battle_state.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")

const FLOOR := BattleState.Terrain.FLOOR
const WALL := BattleState.Terrain.WALL
const BARREL := BattleState.Terrain.BARREL
const NONE := BattleState.Surface.NONE
const WATER := BattleState.Surface.WATER
const OIL := BattleState.Surface.OIL
const STEAM := BattleState.Surface.STEAM


# =========================================================================
# Player-facing queries
# =========================================================================

static func ability_targets(state, u, ability_id: String) -> Array:
	var ab := GameData.ability(ability_id)
	var r := int(ab["range"])
	var out: Array = []
	if ab["shape"] == "line":
		for dir in BattleState.DIRS:
			for i in range(1, r + 1):
				var c: Vector2i = u.cell + dir * i
				if not state.in_bounds(c) or state.get_terrain(c) == WALL:
					break
				out.append(c)
		return out
	for y in state.height:
		for x in state.width:
			var c := Vector2i(x, y)
			var d := BattleState.manhattan(u.cell, c)
			if d < 1 or d > r or state.get_terrain(c) == WALL:
				continue
			if ab["los"] and not state.has_los(u.cell, c):
				continue
			if ab.get("needs_target", false) and state.unit_at(c) == null and state.get_terrain(c) != BARREL:
				continue
			out.append(c)
	return out


## The tiles an ability's shape covers (before any chain reactions).
static func shape_cells(state, caster_cell: Vector2i, ability_id: String, target: Vector2i) -> Array:
	var ab := GameData.ability(ability_id)
	var out: Array = []
	match ab["shape"]:
		"plus":
			out.append(target)
			for dir in BattleState.DIRS:
				out.append(target + dir)
		"square":
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					out.append(target + Vector2i(dx, dy))
		"line":
			var dir := _dir_to(caster_cell, target)
			for i in range(1, int(ab["range"]) + 1):
				var c: Vector2i = caster_cell + dir * i
				if not state.in_bounds(c) or state.get_terrain(c) == WALL:
					break
				out.append(c)
				if state.unit_at(c) != null or state.get_terrain(c) == BARREL:
					break
		_:
			out.append(target)
	return out.filter(func(c): return state.in_bounds(c) and state.get_terrain(c) != WALL)


# =========================================================================
# Player actions
# =========================================================================

static func move_unit(state, u, dest: Vector2i) -> Array:
	var events: Array = []
	var info: Dictionary = state.reachable(u)
	if u.moved or not info.has(dest) or not info[dest]["stop"]:
		return events
	var path := BattleState.path_from(info, dest)
	u.cell = dest
	u.moved = true
	events.append({"type": "move", "unit": u.id, "path": path})
	_on_enter_cell(state, u, events)
	return events


static func use_ability(state, u, ability_id: String, target: Vector2i) -> Array:
	var events: Array = []
	if not u.can_use(ability_id) or not ability_targets(state, u, ability_id).has(target):
		return events
	var ab := GameData.ability(ability_id)
	u.acted = true
	if int(ab["cooldown"]) > 0:
		u.cooldowns[ability_id] = int(ab["cooldown"]) + 1
	perform_ability(state, u, ability_id, target, events)
	_check_end(state, events)
	return events


static func wait_unit(_state, u) -> void:
	u.moved = true
	u.acted = true


## Resolves an ability's effects without any bookkeeping (shared by heroes and enemies).
static func perform_ability(state, u, ability_id: String, target: Vector2i, events: Array) -> void:
	var ab := GameData.ability(ability_id)
	var element: String = ab["element"]
	var dmg := int(ab["damage"])
	var cells := shape_cells(state, u.cell, ability_id, target)
	events.append({"type": "cast", "unit": u.id, "name": ab["name"], "element": element, "target": target})
	events.append({"type": "flash", "cells": cells, "element": element})

	if ab["shape"] == "line":
		# Soak/burn the path, then hit and push the first thing in the way.
		var last: Vector2i = cells[-1] if not cells.is_empty() else u.cell
		for c in cells:
			if c != last or (state.unit_at(c) == null and state.get_terrain(c) != BARREL):
				apply_element(state, c, element, 0, events)
		if cells.is_empty():
			return
		var hit = state.unit_at(last)
		var dir := _dir_to(u.cell, target)
		if state.get_terrain(last) == BARREL:
			if int(ab["push"]) > 0:
				push_barrel(state, last, dir, int(ab["push"]), events)
			else:
				apply_element(state, last, element, dmg, events)
		elif hit != null:
			apply_element(state, last, element, dmg, events)
			if hit.alive and int(ab["push"]) > 0:
				push_unit(state, hit, dir, int(ab["push"]), events)
		return

	if element == "lightning":
		apply_lightning(state, cells, dmg, events)
	else:
		for c in cells:
			apply_element(state, c, element, dmg, events)
	if int(ab["push"]) > 0:
		var pushed = state.unit_at(target)
		if pushed != null and pushed.alive:
			push_unit(state, pushed, _dir_to(u.cell, target), int(ab["push"]), events)


# =========================================================================
# Elements
# =========================================================================

static func apply_element(state, c: Vector2i, element: String, dmg: int, events: Array) -> void:
	match element:
		"water":
			soak(state, c, events)
			var u = state.unit_at(c)
			if u != null:
				damage_unit(state, u, dmg, "water", events)
		"fire":
			apply_fire(state, c, dmg, events)
		"lightning":
			apply_lightning(state, [c], dmg, events)
		_:
			hit_cell(state, c, dmg, element, events)


## Physical hit: damages a unit, or sets off a barrel.
static func hit_cell(state, c: Vector2i, dmg: int, element: String, events: Array) -> void:
	if state.get_terrain(c) == BARREL:
		explode_barrel(state, c, events)
		return
	var u = state.unit_at(c)
	if u != null:
		damage_unit(state, u, dmg, element, events)


## Water: turns the tile to water (oil floats and is unaffected), clears
## steam, and puts out a burning unit standing there.
static func soak(state, c: Vector2i, events: Array) -> void:
	if state.is_obstacle(c):
		return
	var s: int = state.get_surface(c)
	if s != OIL and s != WATER:
		state.set_surface(c, WATER)
		events.append({"type": "surface", "cell": c, "surface": WATER})
	var u = state.unit_at(c)
	if u != null and u.burning > 0:
		_set_burning(state, u, 0, events)
		events.append({"type": "text", "cell": c, "text": "Doused", "element": "water"})


## Fire: explodes barrels, boils water into steam (and the steam protects
## from burning), damages + ignites units, and ignites connected oil.
static func apply_fire(state, c: Vector2i, dmg: int, events: Array) -> void:
	if not state.in_bounds(c) or state.get_terrain(c) == WALL:
		return
	if state.get_terrain(c) == BARREL:
		explode_barrel(state, c, events)
		return
	var s: int = state.get_surface(c)
	var protected := false
	if s == WATER:
		state.set_surface(c, STEAM, GameData.rule("steam_turns"))
		events.append({"type": "surface", "cell": c, "surface": STEAM})
		events.append({"type": "text", "cell": c, "text": "Steam", "element": "steam"})
		protected = true
	var u = state.unit_at(c)
	if u != null:
		damage_unit(state, u, dmg, "fire", events)
		if u.alive and not protected:
			_set_burning(state, u, GameData.rule("burn_turns"), events)
	if s == OIL:
		ignite_oil(state, c, events)


## Burns away the whole connected oil patch. Everyone standing in it takes
## damage and catches fire; barrels touching it explode.
static func ignite_oil(state, start: Vector2i, events: Array) -> void:
	var patch: Array = state.surface_component(start, OIL)
	if patch.is_empty():
		return
	events.append({"type": "pause", "time": 0.2})
	events.append({"type": "text", "cell": start, "text": "IGNITE!", "element": "fire"})
	events.append({"type": "flash", "cells": patch, "element": "fire"})
	for c in patch:
		state.set_surface(c, NONE)
		events.append({"type": "surface", "cell": c, "surface": NONE})
	var dmg := GameData.rule("oil_ignite_damage")
	var barrels: Array = []
	for c in patch:
		var u = state.unit_at(c)
		if u != null:
			damage_unit(state, u, dmg, "fire", events)
			if u.alive:
				_set_burning(state, u, GameData.rule("burn_turns"), events)
		for dir in BattleState.DIRS:
			var n: Vector2i = c + dir
			if state.get_terrain(n) == BARREL and not barrels.has(n):
				barrels.append(n)
	for b in barrels:
		explode_barrel(state, b, events)


## Barrel: removed, then fire hits all 8 surrounding tiles (chains freely).
static func explode_barrel(state, c: Vector2i, events: Array) -> void:
	if state.get_terrain(c) != BARREL:
		return
	state.set_terrain(c, FLOOR)
	events.append({"type": "pause", "time": 0.2})
	events.append({"type": "terrain", "cell": c, "terrain": FLOOR})
	events.append({"type": "explosion", "cell": c})
	events.append({"type": "text", "cell": c, "text": "BOOM!", "element": "fire"})
	var dmg := GameData.rule("barrel_damage")
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				apply_fire(state, c + Vector2i(dx, dy), dmg, events)


## Lightning: hits the given tiles, plus every tile of any water body that
## touches them. Each unit is hit once. Barrels in the zone explode.
static func apply_lightning(state, cells: Array, dmg: int, events: Array) -> void:
	var zone: Array = []
	for c in cells:
		if state.in_bounds(c) and state.get_terrain(c) != WALL and not zone.has(c):
			zone.append(c)
	var conducted: Array = []
	for c in cells:
		for w in state.surface_component(c, WATER):
			if not zone.has(w) and not conducted.has(w):
				conducted.append(w)
	if not conducted.is_empty():
		events.append({"type": "pause", "time": 0.15})
		events.append({"type": "text", "cell": conducted[0], "text": "SHOCK!", "element": "lightning"})
		events.append({"type": "flash", "cells": conducted, "element": "lightning"})
	for c in zone + conducted:
		if state.get_terrain(c) == BARREL:
			explode_barrel(state, c, events)
			continue
		var u = state.unit_at(c)
		if u != null:
			damage_unit(state, u, dmg, "lightning", events)


# =========================================================================
# Movement effects
# =========================================================================

## Pushes a unit up to dist tiles. Hitting a wall, unit or barrel stops it
## and deals collision damage (barrels explode).
static func push_unit(state, u, dir: Vector2i, dist: int, events: Array) -> void:
	var from: Vector2i = u.cell
	var blocked := false
	var block_cell := Vector2i.ZERO
	for i in dist:
		var n: Vector2i = u.cell + dir
		if state.is_obstacle(n) or state.unit_at(n) != null:
			blocked = true
			block_cell = n
			break
		u.cell = n
	if u.cell != from:
		events.append({"type": "push", "unit": u.id, "from": from, "to": u.cell})
		_on_enter_cell(state, u, events)
	if blocked:
		var cd := GameData.rule("collision_damage")
		events.append({"type": "text", "cell": u.cell, "text": "Crash", "element": "physical"})
		damage_unit(state, u, cd, "physical", events)
		var other = state.unit_at(block_cell)
		if other != null:
			damage_unit(state, other, cd, "physical", events)
		elif state.get_terrain(block_cell) == BARREL:
			explode_barrel(state, block_cell, events)


## Slides a barrel. If it slams into a wall, unit or another barrel it explodes.
static func push_barrel(state, c: Vector2i, dir: Vector2i, dist: int, events: Array) -> void:
	var at := c
	var blocked := false
	for i in dist:
		var n: Vector2i = at + dir
		if state.is_obstacle(n) or state.unit_at(n) != null:
			blocked = true
			break
		at = n
	if at != c:
		state.set_terrain(c, FLOOR)
		state.set_terrain(at, BARREL)
		events.append({"type": "barrel_push", "from": c, "to": at})
	if blocked:
		events.append({"type": "text", "cell": at, "text": "Crash", "element": "physical"})
		explode_barrel(state, at, events)


static func _on_enter_cell(state, u, events: Array) -> void:
	if u.burning > 0 and state.get_surface(u.cell) == WATER:
		_set_burning(state, u, 0, events)
		events.append({"type": "text", "cell": u.cell, "text": "Doused", "element": "water"})


# =========================================================================
# Damage / status
# =========================================================================

static func damage_unit(state, u, amount: int, element: String, events: Array) -> void:
	if not u.alive or amount <= 0:
		return
	u.hp -= amount
	events.append({"type": "damage", "unit": u.id, "amount": amount, "element": element, "hp": u.hp})
	if u.hp <= 0:
		u.hp = 0
		u.alive = false
		events.append({"type": "death", "unit": u.id})


static func _set_burning(_state, u, turns: int, events: Array) -> void:
	if u.burning == turns:
		return
	u.burning = turns
	events.append({"type": "status", "unit": u.id, "burning": turns})


static func _tick_burning(state, team: String, events: Array) -> void:
	for u in state.living(team):
		if u.burning > 0:
			events.append({"type": "text", "cell": u.cell, "text": "Burn", "element": "fire"})
			damage_unit(state, u, GameData.rule("burn_damage"), "fire", events)
			if u.alive:
				_set_burning(state, u, u.burning - 1, events)


# =========================================================================
# Turn flow
# =========================================================================

## Ends the player phase: enemy burn ticks, enemies execute their intents in
## order, the round ends (steam fades), enemies plan, then a new player phase
## starts (cooldowns tick, hero burn ticks).
static func end_player_turn(state) -> Array:
	var events: Array = []
	if state.phase != "player":
		return events
	state.phase = "enemy"
	events.append({"type": "phase", "phase": "enemy", "round": state.round_num})
	_tick_burning(state, "enemy", events)
	if _check_end(state, events):
		return events
	var enemies: Array = state.living("enemy")
	enemies.sort_custom(func(a, b): return a.order < b.order)
	for e in enemies:
		if not e.alive:
			continue
		execute_enemy_intent(state, e, events)
		if _check_end(state, events):
			return events

	# End of round.
	for y in state.height:
		for x in state.width:
			var c := Vector2i(x, y)
			if state.get_surface(c) == STEAM:
				var t: int = state.steam_timer[state.idx(c)] - 1
				if t <= 0:
					state.set_surface(c, NONE)
					events.append({"type": "surface", "cell": c, "surface": NONE})
				else:
					state.steam_timer[state.idx(c)] = t
	state.round_num += 1
	EnemyAI.plan_all(state)

	state.phase = "player"
	for h in state.living("hero"):
		h.moved = false
		h.acted = false
		for k in h.cooldowns.keys():
			h.cooldowns[k] = maxi(0, int(h.cooldowns[k]) - 1)
	events.append({"type": "phase", "phase": "player", "round": state.round_num})
	_tick_burning(state, "hero", events)
	_check_end(state, events)
	return events


static func execute_enemy_intent(state, e, events: Array) -> void:
	events.append({"type": "enemy_turn", "unit": e.id})
	var plan := EnemyAI.resolve_intent(state, e)
	if plan["path"].size() > 1:
		e.cell = plan["dest"]
		events.append({"type": "move", "unit": e.id, "path": plan["path"]})
		_on_enter_cell(state, e, events)
	if plan["attack_ok"]:
		perform_ability(state, e, e.abilities[0], plan["target"], events)
	elif plan["has_target"]:
		var why := "No sight" if BattleState.manhattan(e.cell, plan["target"]) <= int(GameData.ability(e.abilities[0])["range"]) else "Out of range"
		events.append({"type": "text", "cell": e.cell, "text": why, "element": "physical"})
	e.intent = {}
	events.append({"type": "pause", "time": 0.25})


static func _check_end(state, events: Array) -> bool:
	if state.phase == "won" or state.phase == "lost":
		return true
	if state.living("hero").is_empty():
		state.phase = "lost"
	elif state.living("enemy").is_empty():
		state.phase = "won"
	else:
		return false
	events.append({"type": "game_over", "result": state.phase})
	return true


static func _dir_to(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))
