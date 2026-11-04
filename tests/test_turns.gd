## Turn flow, enemy intents and the real level.
extends "res://tests/test_base.gd"


func test_level_loads_with_expected_roster() -> void:
	var s = LevelLoader.build()
	eq(s.width, 10, "width")
	eq(s.height, 10, "height")
	eq(s.living("hero").size(), 3, "three heroes")
	var enemies: Array = s.living("enemy")
	check(enemies.size() >= 4 and enemies.size() <= 5, "4-5 enemies")
	var kinds := {}
	for e in enemies:
		kinds[e.type_id] = true
		check(not e.intent.is_empty(), "%s has an intent" % e.name)
	eq(kinds.size(), 2, "two enemy types")
	for h in s.living("hero"):
		eq(h.abilities.size(), 3, "%s has basic + 2 abilities" % h.name)


func test_enemy_attacks_planned_tile() -> void:
	var s = make(["......", "......", "......"], [["tide", 0, 0]], [["brute", 3, 0]])
	var brute = at(s, 3, 0)
	check(brute.intent["has_target"], "brute plans to attack")
	eq(brute.intent["target"], Vector2i(0, 0), "targets Tide's tile")
	var tide = hero(s, "tide")
	var hp: int = tide.hp
	Rules.end_player_turn(s)
	eq(tide.hp, hp - ab_dmg("smash"), "Tide hit")


func test_enemy_misses_if_hero_moves_away() -> void:
	var s = make(["......", "......", "......"], [["tide", 0, 0]], [["brute", 3, 0]])
	var tide = hero(s, "tide")
	var hp: int = tide.hp
	Rules.move_unit(s, tide, Vector2i(0, 2))
	Rules.end_player_turn(s)
	eq(tide.hp, hp, "attack hit an empty tile")


func test_steam_makes_ranged_attack_fizzle() -> void:
	var s = make(["......", "......", "......"], [["tide", 0, 0]], [["spitter", 4, 0]])
	var sp = at(s, 4, 0)
	check(sp.intent["has_target"], "spitter plans to shoot")
	var tide = hero(s, "tide")
	var hp: int = tide.hp
	var dest: Vector2i = sp.intent["move_to"]
	# Put steam between the spitter's planned spot and Tide.
	for x in range(1, dest.x):
		s.set_surface(Vector2i(x, 0), STEAM, 2)
	var preview := EnemyAI.resolve_intent(s, sp)
	check(not preview["attack_ok"], "preview shows the attack is blocked")
	Rules.end_player_turn(s)
	eq(tide.hp, hp, "no damage through steam")


func test_pushed_enemy_out_of_range_fizzles() -> void:
	var s = make(["......", "......", "......"], [["tide", 0, 0]], [["brute", 1, 0]])
	var brute = at(s, 1, 0)
	brute.move = 0
	EnemyAI.plan_all(s)
	Rules.use_ability(s, hero(s, "tide"), "wave", Vector2i(1, 0))
	var tide = hero(s, "tide")
	var hp: int = tide.hp
	Rules.end_player_turn(s)
	eq(tide.hp, hp, "pushed brute cannot reach")


func test_cooldown_blocks_reuse_next_turn() -> void:
	var s = make(["......", "......", "......"], [["volt", 0, 2]], [["brute", 5, 0]])
	var volt = hero(s, "volt")
	Rules.use_ability(s, volt, "thunderclap", Vector2i(2, 2))
	Rules.end_player_turn(s)
	check(not volt.can_use("thunderclap"), "on cooldown next turn")
	check(volt.can_use("zap"), "other ability fine")


func test_win_when_all_enemies_dead() -> void:
	var s = make(["......", "......"], [["ember", 0, 0]], [["spitter", 2, 0]])
	at(s, 2, 0).hp = 1
	var ev: Array = Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(2, 0))
	eq(s.phase, "won", "phase won")
	check(types(ev).has("game_over"), "game_over event")


func test_lose_when_all_heroes_dead() -> void:
	var s = make(["......", "......"], [["tide", 0, 0]], [["brute", 1, 0]])
	hero(s, "tide").hp = 1
	Rules.end_player_turn(s)
	eq(s.phase, "lost", "phase lost")


func test_preview_on_clone_does_not_touch_real_state() -> void:
	var s = make(["oB....", "......"], [["ember", 0, 1]], [["brute", 2, 0]])
	var c = s.clone()
	Rules.use_ability(c, c.unit_by_id(hero(s, "ember").id), "firebolt", Vector2i(0, 0))
	eq(s.get_terrain(Vector2i(1, 0)), BARREL, "real barrel untouched")
	eq(s.get_surface(Vector2i(0, 0)), OIL, "real oil untouched")
	eq(at(s, 2, 0).hp, at(c, 2, 0).hp + GameData.rule("barrel_damage"), "clone took damage")


## Plays many full fights with random legal hero actions. Catches crashes,
## stuck turn loops and broken invariants in the rules.
func test_random_fights_always_terminate_cleanly() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var finished := 0
	for game in 40:
		var s = LevelLoader.build()
		for round_i in 40:
			for h in s.living("hero"):
				if rng.randf() < 0.8:
					var dests: Array = s.move_destinations(h)
					if not dests.is_empty():
						Rules.move_unit(s, h, dests[rng.randi() % dests.size()])
				var usable: Array = h.abilities.filter(func(a): return h.can_use(a) and not Rules.ability_targets(s, h, a).is_empty())
				if not usable.is_empty() and s.phase == "player":
					var a: String = usable[rng.randi() % usable.size()]
					var ts: Array = Rules.ability_targets(s, h, a)
					Rules.use_ability(s, h, a, ts[rng.randi() % ts.size()])
			if s.phase == "player":
				Rules.end_player_turn(s)
			var occupied := {}
			for u in s.units:
				check(u.hp >= 0 and u.hp <= u.max_hp, "hp in range")
				if u.alive:
					check(not occupied.has(u.cell), "two units on one tile")
					occupied[u.cell] = true
				if u.alive:
					check(not s.is_obstacle(u.cell), "unit not inside a wall/barrel")
			if s.phase == "won" or s.phase == "lost":
				finished += 1
				break
		if not failures.is_empty():
			return
	check(finished > 0, "at least some random fights reach an ending")
