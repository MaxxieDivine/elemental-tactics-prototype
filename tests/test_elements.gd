## Core elemental rules: water, lightning, fire, oil, barrels, steam.
extends "res://tests/test_base.gd"


# --- Water ------------------------------------------------------------------

func test_splash_soaks_plus_shape_but_not_oil() -> void:
	var s = make([".....", ".....", "..o..", ".....", "....."], [["tide", 0, 4]], [["brute", 4, 0]])
	var tide = hero(s, "tide")
	Rules.use_ability(s, tide, "splash", Vector2i(2, 3))
	eq(s.get_surface(Vector2i(2, 3)), WATER, "center soaked")
	eq(s.get_surface(Vector2i(1, 3)), WATER, "left soaked")
	eq(s.get_surface(Vector2i(3, 3)), WATER, "right soaked")
	eq(s.get_surface(Vector2i(2, 4)), WATER, "below soaked")
	eq(s.get_surface(Vector2i(2, 2)), OIL, "oil is not washed away")
	eq(s.get_surface(Vector2i(0, 0)), NONE, "far tile untouched")


func test_wave_pushes_enemy_and_soaks_path() -> void:
	var s = make(["......", "......", "......", "......", "......", "......"], [["tide", 0, 2]], [["brute", 2, 2]])
	var tide = hero(s, "tide")
	var brute = at(s, 2, 2)
	var hp: int = brute.hp
	var ev: Array = Rules.use_ability(s, tide, "wave", Vector2i(3, 2))
	eq(brute.cell, Vector2i(4, 2), "pushed 2 tiles away from caster")
	eq(brute.hp, hp - ab_dmg("wave"), "wave damage")
	eq(s.get_surface(Vector2i(1, 2)), WATER, "path soaked")
	eq(s.get_surface(Vector2i(2, 2)), WATER, "hit tile soaked")
	check(types(ev).has("push"), "push event emitted")


func test_push_into_wall_deals_collision_damage() -> void:
	var s = make(["....#.", "......"], [["tide", 0, 0]], [["brute", 3, 0]])
	var brute = at(s, 3, 0)
	var hp: int = brute.hp
	Rules.use_ability(s, hero(s, "tide"), "wave", Vector2i(3, 0))
	eq(brute.cell, Vector2i(3, 0), "blocked by wall immediately")
	eq(brute.hp, hp - ab_dmg("wave") - GameData.rule("collision_damage"), "wave + collision damage")


func test_push_into_unit_damages_both() -> void:
	var s = make(["......", "......"], [["tide", 0, 0]], [["brute", 2, 0], ["spitter", 4, 0]])
	var brute = at(s, 2, 0)
	var spitter = at(s, 4, 0)
	var shp: int = spitter.hp
	Rules.use_ability(s, hero(s, "tide"), "wave", Vector2i(2, 0))
	eq(brute.cell, Vector2i(3, 0), "stopped next to the other enemy")
	eq(spitter.hp, shp - GameData.rule("collision_damage"), "the unit hit also takes collision damage")


func test_wave_slides_barrel_into_enemy_and_it_explodes() -> void:
	var s = make([".B....", "......"], [["tide", 0, 0]], [["brute", 3, 0]])
	var brute = at(s, 3, 0)
	var hp: int = brute.hp
	Rules.use_ability(s, hero(s, "tide"), "wave", Vector2i(1, 0))
	eq(s.get_terrain(Vector2i(1, 0)), FLOOR, "barrel left its tile")
	eq(s.get_terrain(Vector2i(2, 0)), FLOOR, "barrel exploded on impact")
	eq(brute.hp, hp - barrel_damage(), "enemy caught in blast")


func test_water_puts_out_burning() -> void:
	var s = make(["......", "......"], [["tide", 0, 0]], [["brute", 3, 0]])
	var brute = at(s, 3, 0)
	brute.burning = 2
	Rules.use_ability(s, hero(s, "tide"), "splash", Vector2i(3, 0))
	eq(brute.burning, 0, "doused")


# --- Lightning ----------------------------------------------------------------

func test_lightning_spreads_through_connected_water() -> void:
	var s = make([
		"wwww..",
		"......",
		"....w.",
		"......",
	], [["volt", 0, 3]], [["brute", 0, 0], ["brute", 3, 0], ["spitter", 4, 2]])
	var a = at(s, 0, 0)
	var b = at(s, 3, 0)
	var c = at(s, 4, 2)
	var ahp: int = a.hp
	var bhp: int = b.hp
	var chp: int = c.hp
	var ev: Array = Rules.use_ability(s, hero(s, "volt"), "zap", Vector2i(0, 0))
	eq(a.hp, ahp - ab_dmg("zap"), "target hit")
	eq(b.hp, bhp - ab_dmg("zap"), "enemy on connected water hit")
	eq(c.hp, chp, "enemy on separate puddle untouched")
	check(ev.any(func(e): return e["type"] == "text" and e["text"] == "SHOCK!"), "SHOCK event emitted")


func test_lightning_on_dry_tile_does_not_spread() -> void:
	var s = make([".www..", "......"], [["volt", 0, 1]], [["brute", 0, 0], ["brute", 2, 0]])
	var b = at(s, 2, 0)
	var bhp: int = b.hp
	Rules.use_ability(s, hero(s, "volt"), "zap", Vector2i(0, 0))
	eq(b.hp, bhp, "dry target does not conduct into nearby water")


func test_lightning_conducts_to_allies_in_water() -> void:
	var s = make(["wwww..", "......"], [["volt", 0, 1], ["tide", 3, 0]], [["brute", 0, 0]])
	var tide = hero(s, "tide")
	var hp: int = tide.hp
	Rules.use_ability(s, hero(s, "volt"), "zap", Vector2i(0, 0))
	eq(tide.hp, hp - ab_dmg("zap"), "friendly fire through water")


func test_each_unit_hit_once_by_area_lightning() -> void:
	var s = make(["www...", "www...", "www...", "......", "......"], [["volt", 1, 4]], [["brute", 1, 1]])
	var b = at(s, 1, 1)
	var hp: int = b.hp
	Rules.use_ability(s, hero(s, "volt"), "thunderclap", Vector2i(1, 1))
	eq(b.hp, hp - ab_dmg("thunderclap"), "hit exactly once")


# --- Fire ---------------------------------------------------------------------

func test_fire_damages_and_burns() -> void:
	var s = make(["......", "......"], [["ember", 0, 0]], [["brute", 3, 0]])
	var b = at(s, 3, 0)
	var hp: int = b.hp
	Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(3, 0))
	eq(b.hp, hp - ab_dmg("firebolt"), "fire damage")
	eq(b.burning, GameData.rule("burn_turns"), "burning applied")


func test_burning_ticks_at_start_of_enemy_phase() -> void:
	var s = make(["......", "......", "......"], [["ember", 0, 2]], [["brute", 5, 0]])
	var b = at(s, 5, 0)
	b.burning = 2
	var hp: int = b.hp
	Rules.end_player_turn(s)
	eq(b.hp, hp - GameData.rule("burn_damage"), "burn tick")
	eq(b.burning, 1, "burn duration decremented")


func test_fire_on_water_makes_steam_and_no_burn() -> void:
	var s = make(["...w..", "......"], [["ember", 0, 0]], [["brute", 3, 0]])
	var b = at(s, 3, 0)
	Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(3, 0))
	eq(s.get_surface(Vector2i(3, 0)), STEAM, "water became steam")
	eq(b.burning, 0, "standing in water protects from burning")


func test_steam_blocks_line_of_sight() -> void:
	var s = make(["......", "......"], [["ember", 0, 0]], [])
	check(s.has_los(Vector2i(0, 0), Vector2i(4, 0)), "clear sight before steam")
	s.set_surface(Vector2i(2, 0), STEAM, 2)
	check(not s.has_los(Vector2i(0, 0), Vector2i(4, 0)), "steam blocks sight")
	check(not Rules.ability_targets(s, hero(s, "ember"), "firebolt").has(Vector2i(4, 0)), "cannot target through steam")


func test_steam_fades_after_configured_rounds() -> void:
	var s = make(["........", "........", "........"], [["ember", 0, 2]], [["brute", 7, 0]])
	s.set_surface(Vector2i(4, 2), STEAM, steam_turns())
	for i in steam_turns():
		eq(s.get_surface(Vector2i(4, 2)), STEAM, "steam still present before round %d ends" % (i + 1))
		Rules.end_player_turn(s)
	eq(s.get_surface(Vector2i(4, 2)), NONE, "steam faded")


func test_fire_ignites_whole_oil_patch() -> void:
	var s = make([
		"ooo...",
		"..o...",
		"......",
		"....o.",
	], [["ember", 5, 2]], [["brute", 0, 0], ["spitter", 2, 1], ["brute", 4, 3]])
	var a = at(s, 0, 0)
	var b = at(s, 2, 1)
	var far = at(s, 4, 3)
	var ahp: int = a.hp
	var bhp: int = b.hp
	Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(2, 1))
	eq(s.get_surface(Vector2i(0, 0)), NONE, "oil burned away")
	eq(a.hp, ahp - oil_damage(), "unit elsewhere on patch hit by ignition")
	eq(b.hp, maxi(0, bhp - ab_dmg("firebolt") - oil_damage()), "target takes bolt + ignition")
	check(a.burning > 0, "unit on patch is burning")
	eq(s.get_surface(Vector2i(4, 3)), OIL, "disconnected oil untouched")
	eq(far.burning, 0, "unit on other oil not burning")


func test_burning_oil_sets_off_adjacent_barrel_in_order() -> void:
	var s = make([
		"oB....",
		"......",
		"......",
	], [["ember", 0, 2]], [["brute", 2, 1]])
	var b = at(s, 2, 1)
	var hp: int = b.hp
	var ev: Array = Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(0, 0))
	eq(s.get_terrain(Vector2i(1, 0)), FLOOR, "barrel gone")
	eq(b.hp, hp - barrel_damage(), "explosion hit nearby enemy")
	var t := types(ev)
	check(t.find("explosion") > ev.find(ev.filter(func(e): return e["type"] == "text" and e["text"] == "IGNITE!")[0]), "ignite plays before explosion")


func test_barrel_explodes_from_lightning_and_chains() -> void:
	var s = make([
		"......",
		"..BB..",
		"......",
		"......",
	], [["volt", 2, 3]], [["brute", 5, 1]])
	var b = at(s, 5, 1)
	var hp: int = b.hp
	var ev: Array = Rules.use_ability(s, hero(s, "volt"), "zap", Vector2i(2, 1))
	eq(s.get_terrain(Vector2i(2, 1)), FLOOR, "first barrel exploded")
	eq(s.get_terrain(Vector2i(3, 1)), FLOOR, "second barrel chained")
	eq(types(ev).count("explosion"), 2, "two explosions")
	eq(b.hp, hp, "enemy two tiles from second barrel not hit")


func test_explosion_boils_water_and_burns_dry_units() -> void:
	var s = make([
		"w.....",
		".B....",
		"......",
		"......",
	], [["ember", 1, 3]], [["brute", 2, 2], ["spitter", 0, 0]])
	var dry = at(s, 2, 2)
	var wet = at(s, 0, 0)
	Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(1, 1))
	eq(s.get_surface(Vector2i(0, 0)), STEAM, "explosion turns water to steam")
	check(dry.burning > 0, "dry unit burns")
	eq(wet.burning, 0, "wet unit does not burn")


func test_reactions_are_read_from_terrain_data() -> void:
	var r: Dictionary = GameData.reaction("fire", "oil")
	var old: int = r["damage"]
	r["damage"] = 5
	var s = make(["oo....", "......"], [["ember", 0, 1]], [["brute", 1, 0]])
	var b = at(s, 1, 0)
	var hp: int = b.hp
	Rules.use_ability(s, hero(s, "ember"), "firebolt", Vector2i(0, 0))
	r["damage"] = old
	eq(b.hp, hp - 5, "ignite damage taken from terrain.json")
