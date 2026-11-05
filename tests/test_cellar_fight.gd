## The cellar fight: cellar_rats loads from data, Agador's punch / kick /
## knock_over, oil, fire, water, the flare, rats avoiding oil, the candle rat,
## and a headless player that wins. first_fight stays as it was.
extends "res://tests/test_base.gd"

const ENC := "cellar_rats"


## A small board that uses the cellar's rules (its terrain overrides).
## map chars: . floor, # wall, o oil, w water, L lantern.
func cellar(map: Array, heroes: Array = [], enemies: Array = []):
	var lv: Dictionary = GameData.encounter(ENC).duplicate(true)
	lv["legend"] = {".": "floor", "#": "wall", "o": "oil", "w": "water", "L": "cellar_lantern"}
	lv["map"] = map
	lv["objects"] = []
	lv["party"] = heroes.map(func(h): return {"id": h[0], "cell": [h[1], h[2]]})
	lv["enemies"] = enemies.map(func(e): return {"type": e[0], "cell": [e[1], e[2]]})
	return LevelLoader.build(lv)


func lantern() -> int:
	return BattleState.terrain_index("cellar_lantern")


func agador(st):
	return hero(st, "agador")


func oil_rule(st) -> Dictionary:
	return st.reaction("fire", OIL)


# --- Loading -------------------------------------------------------------------

func test_cellar_rats_loads_from_data() -> void:
	var enc: Dictionary = GameData.encounter(ENC)
	var st = LevelLoader.build_encounter(ENC)
	eq(Vector2i(st.width, st.height), Vector2i(7, 9), "a 7 x 9 board")
	eq(st.living("hero").size(), 1, "Agador fights alone")
	eq(agador(st).name, GameData.get_json("characters")["agador"]["name"], "his name comes from characters.json")
	eq(agador(st).cell, Vector2i(enc["party"][0]["cell"][0], enc["party"][0]["cell"][1]), "where the data puts him")
	eq(agador(st).abilities, ["punch", "kick", "knock_over"], "punch, kick, knock over")
	var enemies: Array = st.living("enemy")
	check(enemies.size() >= 3 and enemies.size() <= 4, "three or four rats")
	eq(enemies.filter(func(e): return e.type_id == "candle_rat").size(), 1, "one candle rat")
	for i in enemies.size():
		eq(enemies[i].cell, Vector2i(enc["enemies"][i]["cell"][0], enc["enemies"][i]["cell"][1]), "rat %d placed from data" % i)
		eq(enemies[i].hp, int(GameData.enemy(enemies[i].type_id)["hp"]), "rat hp from data")
		check(enemies[i].avoids.has("oil"), "rats avoid oil")
	var o: Array = enc["objects"][0]["cell"]
	eq(st.get_terrain(Vector2i(o[0], o[1])), lantern(), "the lantern stands where the data puts it")
	var oil := 0
	var water := 0
	for y in st.height:
		for x in st.width:
			var c := Vector2i(x, y)
			check(st.get_terrain(c) != BARREL, "no TNT in the cellar (%s)" % str(c))
			oil += int(st.get_surface(c) == OIL)
			water += int(st.get_surface(c) == WATER)
	check(oil > 0 and water > 0, "oil and water on the board")
	check(int(oil_rule(st).get("flare", 0)) > 0, "the cellar's own oil rule (flare) applies")
	eq(st.rng_seed, int(enc["seed"]), "seed from data")


func test_first_fight_is_unchanged() -> void:
	var st = LevelLoader.build_encounter("first_fight")
	eq(Vector2i(st.width, st.height), Vector2i(10, 10), "10 x 10")
	eq(st.living("hero").map(func(h): return h.type_id), ["tide", "volt", "ember"], "Tide, Volt and Ember")
	eq(st.living("enemy").size(), 5, "five enemies")
	eq(st.get_terrain(Vector2i(4, 4)), BARREL, "the TNT barrel")
	eq(st.get_surface(Vector2i(5, 3)), OIL, "oil")
	eq(st.get_surface(Vector2i(6, 7)), WATER, "water")
	eq(st.get_terrain(Vector2i(2, 2)), BattleState.Terrain.WALL, "walls")
	eq(oil_rule(st), GameData.reaction("fire", "oil"), "its oil follows terrain.json")
	check(not oil_rule(st).has("flare"), "no cellar flare in the arcade")
	eq(st.terrain_data, GameData.get_json("terrain"), "no terrain overrides")
	for h in st.living("hero"):
		check(h.uses.is_empty() and h.avoids.is_empty() and h.carries == "", "%s: no new unit rules" % h.name)
		check(not GameData.hero(h.type_id).has("character"), "%s keeps its own name and colour" % h.name)
	eq(LevelLoader.make_hero("tide", Vector2i.ZERO).name, GameData.get_json("heroes")["tide"]["name"], "names as before")
	# Firebolt on the oil still ignites only the patch and sets off the barrel.
	var ember = hero(st, "ember")
	ember.cell = Vector2i(5, 7)
	var ev := Rules.use_ability(st, ember, "firebolt", Vector2i(5, 5))
	check(types(ev).has("explosion"), "the oil sets off the TNT")


# --- Punch and kick ---------------------------------------------------------------

func test_punch_damage() -> void:
	var st = cellar(["....", "....", "...."], [["agador", 1, 1]], [["rat", 2, 1]])
	var r = at(st, 2, 1)
	check(Rules.ability_targets(st, agador(st), "punch").has(Vector2i(2, 1)), "an adjacent rat can be punched")
	check(not Rules.ability_targets(st, agador(st), "punch").has(Vector2i(3, 1)), "nothing two tiles away")
	check(not Rules.ability_targets(st, agador(st), "punch").has(Vector2i(1, 0)), "no empty tiles")
	Rules.apply_command(st, Commands.use_ability(agador(st).id, "punch", Vector2i(2, 1)))
	eq(r.hp, r.max_hp - ab_dmg("punch"), "punch deals its data damage")
	eq(r.cell, Vector2i(2, 1), "punch does not push")
	check(agador(st).acted, "punch is his action")


func test_kick_damage_and_push() -> void:
	var st = cellar(["....", "....", "...."], [["agador", 0, 1]], [["rat", 1, 1]])
	var r = at(st, 1, 1)
	Rules.apply_command(st, Commands.use_ability(agador(st).id, "kick", Vector2i(1, 1)))
	eq(r.hp, r.max_hp - ab_dmg("kick"), "kick deals its data damage")
	eq(r.cell, Vector2i(2, 1), "and pushes one tile away")
	check(ab_dmg("kick") < ab_dmg("punch"), "a kick hurts less than a punch")
	eq(int(GameData.ability("kick")["push"]), 1, "push 1 from data")
	# Into a wall: collision damage, no move.
	var w = cellar(["#..", "...", "..."], [["agador", 2, 0]], [["rat", 1, 0]])
	var r2 = at(w, 1, 0)
	Rules.apply_command(w, Commands.use_ability(agador(w).id, "kick", Vector2i(1, 0)))
	eq(r2.cell, Vector2i(1, 0), "a wall stops the push")
	eq(r2.hp, r2.max_hp - ab_dmg("kick") - GameData.rule("collision_damage"), "and the crash hurts")


# --- Knock over ---------------------------------------------------------------------

func test_knock_over_needs_the_lantern() -> void:
	var st = cellar([".....", ".oL..", "....."], [["agador", 4, 2]], [["rat", 0, 0]])
	var a = agador(st)
	check(not Rules.ability_available(st, a, "knock_over"), "not available away from the lantern")
	eq(Rules.ability_targets(st, a, "knock_over"), [], "no targets away from it")
	eq(Rules.apply_command(st, Commands.use_ability(a.id, "knock_over", Vector2i(1, 1))), [], "the command is refused")
	a.cell = Vector2i(3, 1)
	check(Rules.ability_available(st, a, "knock_over"), "available next to the lantern")
	eq(Rules.ability_targets(st, a, "knock_over"), [Vector2i(1, 1)], "aimed at the oil tile beside the lantern only")
	a.cell = Vector2i(3, 2)  # diagonal
	check(not Rules.ability_available(st, a, "knock_over"), "diagonal does not count")


func test_knock_over_ignites_once() -> void:
	var st = cellar([".....", "ooL..", "....."], [["agador", 3, 1]], [["rat", 0, 1], ["rat", 4, 2]])
	var a = agador(st)
	var on_oil = at(st, 0, 1)
	var ev := Rules.apply_command(st, Commands.use_ability(a.id, "knock_over", Vector2i(1, 1)))
	check(not ev.is_empty(), "knocked over")
	check(ev.any(func(e): return e["type"] == "text" and e["text"] == "IGNITE!"), "the oil ignites")
	eq(st.get_surface(Vector2i(0, 1)), NONE, "the whole patch burns away")
	eq(st.get_surface(Vector2i(1, 1)), NONE, "including the aimed tile")
	eq(on_oil.hp, on_oil.max_hp - int(oil_rule(st)["damage"]), "a rat on the oil takes the oil's damage")
	check(on_oil.burning > 0, "and burns")
	eq(st.get_terrain(Vector2i(2, 1)), FLOOR, "the lantern is gone")
	eq(a.uses["knock_over"], 0, "no uses left")
	Rules.end_player_turn(st)
	a.cell = Vector2i(3, 1)
	check(not Rules.ability_available(st, a, "knock_over"), "once per fight")
	# With a second lantern it is still used up.
	st.set_terrain(Vector2i(2, 1), lantern())
	st.set_surface(Vector2i(1, 1), OIL)
	check(not Rules.ability_available(st, a, "knock_over"), "used up even with another lantern")
	eq(int(GameData.ability("knock_over")["uses"]), 1, "one use, from data")


func test_undo_restores_the_lantern_use() -> void:
	var st = cellar([".....", "ooL..", "....."], [["agador", 3, 1]], [["rat", 4, 2]])
	var before = st.clone()
	Rules.apply_command(st, Commands.use_ability(agador(st).id, "knock_over", Vector2i(1, 1)))
	eq(agador(before).uses["knock_over"], 1, "a clone keeps its own uses")
	eq(before.get_terrain(Vector2i(2, 1)), lantern(), "and its own lantern")


# --- Fire, oil and water --------------------------------------------------------------

func test_fire_spreads_through_connected_oil_and_stops_at_water() -> void:
	var st = cellar(["oooowoo", ".......", "......."], [["agador", 0, 2]], [["rat", 6, 2]])
	var events: Array = []
	Rules.apply_fire(st, Vector2i(0, 0), 0, events)
	for x in 4:
		eq(st.get_surface(Vector2i(x, 0)), NONE, "connected oil %d burns" % x)
	eq(st.get_surface(Vector2i(4, 0)), WATER, "water does not burn")
	eq(st.get_surface(Vector2i(5, 0)), OIL, "oil past the water is untouched")
	eq(st.get_surface(Vector2i(6, 0)), OIL, "all of it")


func test_flare_scorches_next_to_the_patch_but_not_on_water() -> void:
	var st = cellar(["ooo..", ".w...", "....."], [["agador", 1, 1]], [["rat", 3, 0], ["rat", 0, 2]])
	var beside = at(st, 3, 0)
	var far = at(st, 0, 2)
	var a = agador(st)
	var events: Array = []
	Rules.apply_fire(st, Vector2i(0, 0), 0, events)
	var flare := int(oil_rule(st)["flare"])
	eq(beside.hp, beside.max_hp - flare, "a rat next to the patch is scorched")
	eq(beside.burning > 0, bool(oil_rule(st).get("flare_burns", false)), "and set alight as the data says")
	eq(far.hp, far.max_hp, "two tiles away is safe")
	eq(a.hp, a.max_hp, "standing in water next to it is safe")
	# Agador can be hurt by his own fire.
	var st2 = cellar(["ooo..", "..L..", "....."], [["agador", 1, 1]], [["rat", 4, 2]])
	var a2 = agador(st2)
	var ev := Rules.apply_command(st2, Commands.use_ability(a2.id, "knock_over", Vector2i(2, 0)))
	check(not ev.is_empty(), "he knocks it over from beside the oil")
	eq(a2.hp, a2.max_hp - flare, "and scorches himself")


# --- Rats ---------------------------------------------------------------------------------

func test_rats_avoid_oil_on_their_own() -> void:
	var st = cellar([".....", "ooo..", "....."], [["agador", 0, 2]], [["rat", 0, 0]])
	var r = at(st, 0, 0)
	var info: Dictionary = st.reachable(r)
	for c in info:
		check(st.get_surface(c) != OIL, "never routes over oil (%s)" % str(c))
	# It walks around the oil toward Agador instead.
	check(r.intent["move_to"] != r.cell, "it still moves")
	check(st.get_surface(r.intent["move_to"]) != OIL, "not onto oil")
	for i in 6:
		Rules.end_player_turn(st)
		if st.phase != "player":
			break
		for e in st.living("enemy"):
			check(st.get_surface(e.cell) != OIL, "round %d: no rat stands on oil" % i)
	# Heroes walk on oil.
	check(st.reachable(agador(st)).keys().any(func(c): return st.get_surface(c) == OIL), "Agador can step on oil")


func test_candle_rat_pushed_onto_oil_ignites_it() -> void:
	# Kick the candle rat up into the oil; a rat sits beside the patch.
	var st = cellar(["..........", "...oo.....", "..........", ".........."], [["agador", 3, 3]], [["candle_rat", 3, 2], ["rat", 4, 0], ["rat", 9, 3]])
	var c = at(st, 3, 2)
	var beside = at(st, 4, 0)
	var ev := Rules.apply_command(st, Commands.use_ability(agador(st).id, "kick", Vector2i(3, 2)))
	check(ev.any(func(e): return e["type"] == "text" and e["text"] == "IGNITE!"), "landing on oil ignites it")
	eq(st.get_surface(Vector2i(3, 1)), NONE, "the patch burned")
	eq(st.get_surface(Vector2i(4, 1)), NONE, "all of it")
	check(c.hp < c.max_hp - ab_dmg("kick"), "the candle rat burns with it")
	check(beside.hp < beside.max_hp, "a rat beside the oil is scorched")
	# A plain rat pushed onto oil does nothing to it.
	var p = cellar(["..........", "...oo.....", "..........", ".........."], [["agador", 3, 3]], [["rat", 3, 2]])
	Rules.apply_command(p, Commands.use_ability(agador(p).id, "kick", Vector2i(3, 2)))
	eq(p.get_surface(Vector2i(3, 1)), OIL, "a plain rat on oil does not light it")
	eq(at(p, 3, 1).type_id, "rat", "it was pushed there")
	eq(GameData.enemy("candle_rat").get("carries", ""), "fire", "the candle rat carries fire (data)")


func test_rats_show_intents() -> void:
	var st = LevelLoader.build_encounter(ENC)
	for e in st.living("enemy"):
		check(not e.intent.is_empty(), "%s shows a plan" % e.name)
		check(e.order > 0, "%s has a turn number" % e.name)


# --- A whole fight -------------------------------------------------------------------

## One turn for a player who looks one turn ahead: tries every move (before
## or after acting) and every action, scores the result after the enemies act.
func _best_turn(st) -> void:
	var a = agador(st)
	var best_score := -INF
	var best: Array = []
	var dests: Array = [a.cell] + st.move_destinations(a)
	for move_first in [true, false]:
		for d in dests:
			var s1 = st.clone()
			var cmds: Array = []
			if move_first and d != a.cell:
				Rules.apply_command(s1, Commands.move(a.id, d))
				cmds.append(Commands.move(a.id, d))
			var acts: Array = [null]
			var a1 = s1.unit_by_id(a.id)
			for id in a1.abilities:
				if Rules.ability_available(s1, a1, id):
					for t in Rules.ability_targets(s1, a1, id):
						acts.append(Commands.use_ability(a.id, id, t))
			for act in acts:
				var s2 = s1.clone()
				var c2: Array = cmds.duplicate()
				if act != null:
					if Rules.apply_command(s2, act).is_empty():
						continue
					c2.append(act)
				if not move_first and d != a.cell and s2.phase == "player":
					if Rules.apply_command(s2, Commands.move(a.id, d)).is_empty():
						continue
					c2.append(Commands.move(a.id, d))
				var s3 = s2.clone()
				Rules.apply_command(s3, Commands.end_turn())
				var sc := _score(s3)
				if sc > best_score:
					best_score = sc
					best = c2
	for c in best:
		Rules.apply_command(st, c)
	Rules.apply_command(st, Commands.end_turn())


func _score(st) -> float:
	if st.phase == "lost":
		return -100000.0
	var enemy_hp := 0
	for e in st.living("enemy"):
		enemy_hp += e.hp + 3
	var h = st.living("hero")
	return -enemy_hp * 10.0 + (h[0].hp * 6.0 if not h.is_empty() else 0.0) + (10000.0 if st.phase == "won" else 0.0)


func test_a_headless_player_wins_the_encounter() -> void:
	var st = LevelLoader.build_encounter(ENC)
	var guard := 0
	while st.phase == "player" and guard < 20:
		_best_turn(st)
		guard += 1
	eq(st.phase, "won", "a player who plans wins the cellar fight")
	check(st.round_num <= 12, "in a short fight (%d rounds)" % st.round_num)


func test_the_lantern_plan_beats_waiting_it_out() -> void:
	# Wait by the lantern until rats line the oil, then knock it over.
	var st = LevelLoader.build_encounter(ENC)
	var a = agador(st)
	var knocked := false
	var guard := 0
	while st.phase == "player" and guard < 6 and not knocked:
		guard += 1
		for d in [a.cell] + st.move_destinations(a):
			var s1 = st.clone()
			if d != a.cell:
				Rules.apply_command(s1, Commands.move(a.id, d))
			var a1 = s1.unit_by_id(a.id)
			if not Rules.ability_available(s1, a1, "knock_over"):
				continue
			for t in Rules.ability_targets(s1, a1, "knock_over"):
				var s2 = s1.clone()
				Rules.apply_command(s2, Commands.use_ability(a.id, "knock_over", t))
				var burning: int = s2.living("enemy").filter(func(e): return e.burning > 0).size()
				if burning >= 2 and s2.unit_by_id(a.id).hp == a.max_hp and not knocked:
					if d != a.cell:
						Rules.apply_command(st, Commands.move(a.id, d))
					Rules.apply_command(st, Commands.use_ability(a.id, "knock_over", t))
					knocked = true
		if not knocked:
			Rules.apply_command(st, Commands.end_turn())
	check(knocked, "rats line up along the oil within a few rounds")
	check(st.living("enemy").filter(func(e): return e.burning > 0 or e.hp < e.max_hp).size() >= 2, "the lantern catches two or more rats at once")
