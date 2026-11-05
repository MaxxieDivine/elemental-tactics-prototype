## Flag-based world state (NPCs/objects appearing, moving, changing by story
## flags), pacing NPCs, and the second guest's story beats.
extends "res://tests/test_base.gd"

const TownMap = preload("res://scripts/core/town_map.gd")
const WorldState = preload("res://scripts/core/world_state.gd")
const Pacer = preload("res://scripts/core/pacer.gd")
const StoryFlags = preload("res://scripts/core/story_flags.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")


## Flags (and a time of day, in a set as "time_of_day=night").
func _flags(names: Array):
	var f = StoryFlags.new()
	for n in names:
		if n.begins_with("time_of_day="):
			f.set_time_of_day(n.substr(12))
		else:
			f.set_flag(n)
	return f


func _texts(id: String, flags) -> Array:
	return Dialogue.select_entry(id, flags).get("lines", []).map(func(l): return l["text"])


func _finish(d) -> void:
	var guard := 0
	while d.advance() and guard < 50:
		guard += 1


## The raw data definition of a thing on a map.
func _raw(map_id: String, thing_id: String) -> Dictionary:
	var d: Dictionary = TownMap.map_def(map_id)
	for list in ["npcs", "objects"]:
		for t in d.get(list, []):
			if t["id"] == thing_id:
				return t
	return {}


func _small(things: Array) -> Dictionary:
	return {
		"tiles": {".": {"walkable": true}, "#": {"walkable": false}},
		"map": ["......", "......", "......", "......"],
		"npcs": things,
		"objects": [],
		"props": [],
	}


func _map_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/maps/"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## Every cell the player can arrive at on a map (the start, exit arrivals).
func _arrivals(map_id: String) -> Array:
	var out: Array = []
	var start: Dictionary = GameSession.start_spot()
	if start["map"] == map_id:
		out.append(start["cell"])
	for other in _map_ids():
		for e in TownMap.map_def(other).get("exits", []):
			if e["to"] == map_id:
				out.append(TownMap.cell_of(e["arrive"]))
	return out


## Every combination of the flags a map's states look at, at every time of
## day when its rules look at the time.
func _flag_sets(map_id: String) -> Array:
	var used: Array = WorldState.flags_used(TownMap.map_def(map_id))
	var times: Array = StoryFlags.times() if WorldState.uses_time(TownMap.map_def(map_id)) else [StoryFlags.start_time()]
	var out: Array = []
	for t in times:
		for mask in 1 << used.size():
			var s: Array = ["time_of_day=" + t]
			for i in used.size():
				if mask & (1 << i):
					s.append(used[i])
			out.append(s)
	return out


# --- Visibility, position and priority -------------------------------------------

func test_states_show_hide_and_move_a_thing() -> void:
	var def := _small([{
		"id": "ghost", "cell": [0, 0], "interaction": "letter", "hidden": true,
		"states": [
			{"requires": ["a"], "hidden": false, "cell": [3, 2], "facing": "left"},
		],
	}])
	var none = TownMap.from_data(def, _flags([]))
	check(not none.targets.has("ghost") and none.thing_at(Vector2i(0, 0)) == "", "hidden by default: no target, blocks nothing")
	check(none.is_walkable(Vector2i(0, 0)), "a hidden thing's cell is free")
	var a = TownMap.from_data(def, _flags(["a"]))
	eq(a.cell_of_thing("ghost"), Vector2i(3, 2), "the state's cell is used")
	eq(a.targets["ghost"]["def"]["facing"], "left", "the state's facing is used")
	check(not a.is_walkable(Vector2i(3, 2)), "a shown thing blocks its cell")
	check(not a.targets["ghost"]["def"].has("states") and not a.targets["ghost"]["def"].has("hidden"), "resolved defs hold no rule keys")
	check(TownMap.from_data(def).targets.is_empty(), "no flags given: nothing set")


func test_unless_and_base_definition() -> void:
	var t := {"id": "x", "cell": [1, 1], "states": [{"unless": ["gone"], "cell": [2, 2]}]}
	eq(WorldState.resolve_thing(t, _flags([]))["cell"], [2, 2], "unless met: state applies")
	eq(WorldState.resolve_thing(t, _flags(["gone"]))["cell"], [1, 1], "no state matches: base definition")
	eq(WorldState.resolve_thing({"id": "y", "cell": [0, 0]}, _flags([]))["cell"], [0, 0], "a thing with no states is as written")


func test_highest_priority_state_wins() -> void:
	var t := {"id": "x", "cell": [0, 0], "states": [
		{"requires": ["a"], "cell": [1, 0]},
		{"requires": ["a", "b"], "priority": 5, "cell": [2, 0]},
		{"requires": ["b"], "priority": 5, "cell": [3, 0]},
		{"requires": ["c"], "priority": -1, "hidden": true},
	]}
	eq(WorldState.resolve_thing(t, _flags(["a"]))["cell"], [1, 0], "only one state matches")
	eq(WorldState.resolve_thing(t, _flags(["a", "b"]))["cell"], [2, 0], "higher priority beats the earlier state")
	eq(WorldState.resolve_thing(t, _flags(["b"]))["cell"], [3, 0], "priority 5 beats default 0")
	eq(WorldState.resolve_thing(t, _flags(["a", "c"]))["cell"], [1, 0], "a negative-priority state loses")
	check(WorldState.resolve_thing(t, _flags(["c"])).is_empty(), "the hidden state applies when it is the only match")
	# Ties go to the state listed first.
	var tie := {"id": "x", "cell": [0, 0], "states": [{"requires": ["a"], "cell": [1, 1]}, {"requires": ["a"], "cell": [2, 2]}]}
	eq(WorldState.resolve_thing(tie, _flags(["a"]))["cell"], [1, 1], "a tie goes to the first listed")
	# Only the winning state applies: keys do not pile up across states.
	var one := {"id": "x", "cell": [0, 0], "states": [{"requires": ["a"], "mood": "upset"}, {"requires": ["b"], "priority": 1, "cell": [4, 0]}]}
	check(not WorldState.resolve_thing(one, _flags(["a", "b"])).has("mood"), "a losing state's keys are not applied")


func test_new_guest_states_from_data() -> void:
	var before = TownMap.load_map("lobby", _flags([]))
	check(not before.targets.has("new_guest"), "??? is not in the lobby before found_room_key")
	var lounge_before = TownMap.load_map("lounge", _flags(["found_room_key"]))
	check(not lounge_before.targets.has("new_guest"), "??? is not in the lounge before met_new_guest")
	var pacing = TownMap.load_map("lobby", _flags(["found_room_key"]))
	check(pacing.targets.has("new_guest"), "??? is in the lobby after found_room_key")
	eq(pacing.targets["new_guest"]["interaction"], "new_guest", "tapping ??? plays the new_guest interaction")
	eq(pacing.targets["new_guest"]["def"].get("mood", ""), "upset", "??? is upset in the lobby")
	check(pacing.pacers.has("new_guest"), "??? paces in the lobby")
	check(pacing.targets.has("innkeeper"), "the innkeeper stays in the lobby")
	var after = _flags(["found_room_key", "met_new_guest"])
	var lobby_after = TownMap.load_map("lobby", after)
	check(not lobby_after.targets.has("new_guest"), "??? leaves the lobby after met_new_guest (higher priority wins)")
	check(lobby_after.targets.has("innkeeper"), "the innkeeper is still in the lobby")
	var lounge = TownMap.load_map("lounge", after)
	check(lounge.targets.has("new_guest"), "??? is in the lounge after met_new_guest")
	eq(lounge.cell_of_thing("new_guest"), TownMap.cell_of(_raw("lounge", "new_guest")["cell"]), "lounge cell from data")
	check(not lounge.targets["new_guest"]["def"].has("mood"), "no upset mark in the lounge")
	check(lounge.pacers.is_empty(), "no pacing in the lounge")
	var hall = TownMap.load_map("hallway", after)
	eq(hall.targets["room_2_door"]["def"]["shape"], "door_name", "Room 2 loses its Reserved card after the scene")
	eq(TownMap.load_map("hallway", _flags([])).targets["room_2_door"]["def"]["shape"], "door_reserved", "Room 2 is reserved before")


func test_world_state_follows_flag_changes() -> void:
	# The state is rebuilt from the session's flags whenever a map loads, so a
	# flag set by a conversation shows up on the next build (the town view
	# rebuilds the current map right after the conversation).
	var s = GameSession.new()
	check(not TownMap.load_map("lobby", s.flags).targets.has("new_guest"), "fresh session: no ???")
	var d = Dialogue.new(s.flags)
	d.start("room_1_key")
	_finish(d)
	check(TownMap.load_map("lobby", s.flags).targets.has("new_guest"), "after the key: ??? appears")
	d.start("new_guest")
	_finish(d)
	check(not TownMap.load_map("lobby", s.flags).targets.has("new_guest"), "after the scene: ??? left the lobby")
	check(TownMap.load_map("lounge", s.flags).targets.has("new_guest"), "after the scene: ??? is in the lounge")


# --- Story beats ------------------------------------------------------------------

func test_room_1_key_sets_found_room_key() -> void:
	var f = _flags([])
	var d = Dialogue.new(f)
	check(d.start("room_1_key"), "key interaction starts")
	eq(d.line()["text"], "A key to a room I never booked.", "the key line is unchanged")
	check(not f.has("found_room_key"), "not set before the end")
	_finish(d)
	check(f.has("found_room_key"), "the key sets found_room_key")
	eq(_raw("room_1", "room_1_key").get("interaction", ""), "room_1_key", "the key object uses that interaction")


func test_lobby_conversation_and_met_new_guest() -> void:
	var f = _flags(["found_room_key"])
	var d = Dialogue.new(f)
	check(d.start("new_guest"), "conversation starts")
	var want := [
		["new_guest", "She came here. Someone must've seen her."],
		["innkeeper", "The ferry will be back any day now."],
		["new_guest", "Why does everyone keep saying that?"],
		["agador", "Are you okay?"],
		["new_guest", "Did you get a letter too?"],
		["agador", "On Tuesday. Same as yours?"],
		["new_guest", "Mine came Tuesday too. So how is it this old?"],
		["new_guest", "My sister got one just like it. That was eleven years ago."],
		["innkeeper", "And such a lovely Tuesday it was."],
	]
	var got: Array = []
	var guard := 0
	while not d.finished and guard < 20:
		got.append([d.line()["speaker"], d.line()["text"]])
		if not d.is_last_line():
			check(not f.has("met_new_guest"), "met_new_guest not set mid-conversation")
		d.advance()
		guard += 1
	eq(got, want, "the full lobby conversation with three speakers")
	check(f.has("met_new_guest"), "met_new_guest set at the end")
	check(d.fight_request.is_empty(), "no fight")
	eq(_texts("new_guest", f), ["She loved these things."], "afterwards ??? talks about the arcade")


func test_inn_dialogue_changes_after_met_new_guest() -> void:
	var dlg: Dictionary = GameData.get_json("dialogue")
	var before := {}
	for flags in [[], ["read_letter"], ["found_room_key"], ["read_letter", "found_room_key", "won_first_fight"]]:
		for id in ["innkeeper", "guest_book", "room_2_door"]:
			before[id] = _texts(id, _flags(flags))
			check(not before[id].is_empty(), "%s has lines with %s" % [id, str(flags)])
		check(before["innkeeper"] != ["What happened to her sister?", "Have you tried the fireplace? It's lovely this time of year."], "innkeeper keeps old lines before the scene (%s)" % str(flags))
	eq(_texts("room_2_door", _flags(["found_room_key"])), ["Locked. The card says Reserved, but not for whom."], "Room 2 before the scene")
	eq(_texts("guest_book", _flags(["read_letter"])), ["My name's already in here. I haven't signed anything.", "The ink's wet. Just like my letter."], "guest book with the letter, before the scene")
	for extra in [[], ["read_letter"], ["read_letter", "won_first_fight"]]:
		var f = _flags(["found_room_key", "met_new_guest"] + extra)
		eq(_texts("innkeeper", f), ["What happened to her sister?", "Have you tried the fireplace? It's lovely this time of year."], "innkeeper after the scene %s" % str(extra))
		eq(_texts("guest_book", f), ["There's a page torn out. About eleven years back."], "guest book after the scene %s" % str(extra))
		eq(_texts("room_2_door", f), ["The Reserved card is gone. There's a name here now, but the ink's too wet to read."], "Room 2 after the scene %s" % str(extra))
		var d = Dialogue.new(f)
		d.start("innkeeper")
		eq(d.line()["speaker"], "agador", "Agador asks first")
	# Other interactions keep their lines after the scene.
	var after = _flags(["found_room_key", "met_new_guest"])
	for id in ["key_board", "fireplace", "room_3_door", "room_4_door", "welcome_banner", "cellar_hatch"]:
		eq(_texts(id, after), _texts(id, _flags([])), "%s unchanged by the scene" % id)
	eq(_texts("arcade", after), dlg["arcade"][1]["lines"].map(func(l): return l["text"]), "arcade unchanged by the scene")


# --- Pacing --------------------------------------------------------------------

func test_pacer_route_and_turnaround() -> void:
	eq(Pacer.route_through([[1, 1], [3, 1], [3, 2]]), [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2)], "straight lines between points")
	var p = Pacer.new([[0, 0], [2, 0]], Vector2i(0, 0))
	check(p.at_stop(), "starts on a point")
	var never := func(_c): return false
	var cells: Array = []
	for i in 6:
		p.step(never)
		cells.append(p.cell)
	eq(cells, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "paces back and forth")
	p = Pacer.new([[0, 0], [2, 0]], Vector2i(1, 0))
	check(not p.at_stop(), "the middle is not a stop")
	check(not p.step(func(c): return c == Vector2i(2, 0)), "blocked: does not move")
	eq(p.cell, Vector2i(1, 0), "stays put when blocked")
	check(p.step(never), "then moves")
	eq(p.cell, Vector2i(0, 0), "after a block it turns around")
	eq(Pacer.new([[5, 5]], Vector2i(0, 0)).cell, Vector2i(5, 5), "a one-point route holds the NPC there")
	check(not Pacer.new([[5, 5]]).step(never), "a one-point route never moves")


func test_pacing_moves_the_thing_and_its_stand_cells() -> void:
	var def := _small([{"id": "pacer", "cell": [9, 9], "interaction": "letter", "pace": [[1, 1], [3, 1]]}])
	var m = TownMap.from_data(def)
	eq(m.cell_of_thing("pacer"), Vector2i(1, 1), "a pacer off its route starts on the route")
	check(m.step_pacer("pacer"), "one step")
	eq(m.cell_of_thing("pacer"), Vector2i(2, 1), "moved along the route")
	check(m.is_walkable(Vector2i(1, 1)) and not m.is_walkable(Vector2i(2, 1)), "the old cell frees up, the new one blocks")
	eq(m.target_at(Vector2i(2, 1)), "pacer", "tap where it is now")
	check(m.can_use_from("pacer", Vector2i(2, 2)) and not m.can_use_from("pacer", Vector2i(1, 2)), "stand cells follow it")
	check(not m.step_pacer("pacer", func(c): return c == Vector2i(3, 1)), "blocked by the player's path")
	eq(m.cell_of_thing("pacer"), Vector2i(2, 1), "held still")
	check(m.step_pacer("pacer"), "turns around")
	eq(m.cell_of_thing("pacer"), Vector2i(1, 1), "went back")
	check(not TownMap.from_data(_small([{"id": "still", "cell": [0, 0]}])).step_pacer("still"), "a still NPC does not pace")


func test_pacing_and_upset_mark_stop_after_the_scene() -> void:
	var lobby = TownMap.load_map("lobby", _flags(["found_room_key"]))
	check(lobby.pacers.has("new_guest") and lobby.targets["new_guest"]["def"].get("mood", "") == "upset", "pacing and upset before the scene")
	for map_id in ["lobby", "lounge"]:
		var m = TownMap.load_map(map_id, _flags(["found_room_key", "met_new_guest"]))
		check(m.pacers.is_empty(), "%s: nobody paces after the scene" % map_id)
		for id in m.targets:
			check(m.targets[id]["def"].get("mood", "") == "", "%s: %s shows no mood after the scene" % [map_id, id])


func test_upset_mark_on_the_actor() -> void:
	const TownActor = preload("res://scripts/view/town_actor.gd")
	var a = TownActor.new()
	a.kind = "character"
	a.mood = "upset"
	a.setup("new_guest.sprite")
	check(a.shows_mood() and a.is_processing(), "an upset actor shows and animates the mark")
	var b = TownActor.new()
	b.kind = "character"
	b.setup("new_guest.sprite")
	check(not b.shows_mood() and not b.is_processing(), "no mood: no mark")
	a.free()
	b.free()


# --- Never in the way -------------------------------------------------------------

func test_nobody_blocks_required_paths_in_any_state() -> void:
	# For every map, every flag combination its states use, and every cell a
	# pacing NPC can be on, every exit/NPC/object stays reachable and usable
	# from every arrival cell.
	for map_id in _map_ids():
		for flags in _flag_sets(map_id):
			var probe = TownMap.load_map(map_id, _flags(flags))
			var positions: Array = [{}]
			for pid in probe.pacers:
				positions = []
				for c in probe.pacers[pid].route:
					positions.append({pid: c})
			for pos in positions:
				var m = TownMap.load_map(map_id, _flags(flags))
				for pid in pos:
					m.move_thing(pid, pos[pid])
				for from in _arrivals(map_id):
					check(m.is_walkable(from), "%s %s %s: arrival %s is free" % [map_id, str(flags), str(pos), str(from)])
					for tid in m.targets:
						var a: Dictionary = m.approach_target(from, tid)
						check(not a.is_empty(), "%s %s %s: %s reachable from %s" % [map_id, str(flags), str(pos), tid, str(from)])


func test_pace_route_avoids_stand_cells_and_arrivals() -> void:
	for map_id in _map_ids():
		for flags in _flag_sets(map_id):
			var m = TownMap.load_map(map_id, _flags(flags))
			for pid in m.pacers:
				for c in m.pacers[pid].route:
					check(m.is_ground(c), "%s: %s paces on floor" % [map_id, pid])
					check(not _arrivals(map_id).has(c), "%s: %s never paces onto an arrival cell %s" % [map_id, pid, str(c)])
					for tid in m.targets:
						if tid != pid:
							check(not m.targets[tid]["stand"].has(c), "%s: %s's route %s is not where %s is used from" % [map_id, pid, str(c), tid])


func test_new_guest_beside_the_arcade_without_blocking_it() -> void:
	var m = TownMap.load_map("lounge", _flags(["found_room_key", "met_new_guest"]))
	var g: Vector2i = m.cell_of_thing("new_guest")
	var arcade: Vector2i = m.cell_of_thing("arcade")
	check(maxi(absi(g.x - arcade.x), absi(g.y - arcade.y)) <= 1, "??? stands right next to the arcade")
	for st in m.targets["arcade"]["stand"]:
		check(st != g, "??? is not on the arcade's stand cell %s" % str(st))
	var free := 0
	for st in m.targets["arcade"]["stand"]:
		if m.is_walkable(st):
			free += 1
	eq(free, m.targets["arcade"]["stand"].size(), "every arcade stand cell is still free")
	for from in _arrivals("lounge"):
		var a: Dictionary = m.approach_target(from, "arcade")
		check(not a.is_empty() and m.can_use_from("arcade", a["cell"]), "arcade usable from %s" % str(from))


# --- Character and portrait -------------------------------------------------------

func test_new_guest_character_and_portrait_fallback() -> void:
	var c: Dictionary = GameData.get_json("characters")["new_guest"]
	eq(c["name"], "???", "display name ??? lives in data")
	eq(c["portrait"], "new_guest.portrait.upset", "portrait key")
	eq(AssetCatalog.path(c["portrait"]), GameData.get_json("assets")["paths"]["new_guest.portrait.upset"], "portrait key resolves through assets.json")
	for other in GameData.get_json("characters"):
		if other != "new_guest":
			check(Color(GameData.get_json("characters")[other]["color"]) != Color(c["color"]), "??? has a colour distinct from %s" % other)
	AssetCatalog.clear_cache()
	if not AssetCatalog.exists(c["portrait"]):
		check(AssetCatalog.try_texture(c["portrait"]) == null, "no portrait art yet: the box draws its placeholder")
		check(AssetCatalog.is_placeholder(AssetCatalog.texture(c["portrait"])), "texture() gives the placeholder, no crash")
	var d = Dialogue.new(_flags(["found_room_key"]))
	d.start("new_guest")
	eq(d.line()["name"], "???", "the line shows ???")
	eq(d.line()["initials"], "???", "the placeholder portrait shows ???")
	eq(d.line()["portrait"], "new_guest.portrait.upset", "the line uses the portrait key")
	eq(d.line()["color"], c["color"], "the placeholder uses ???'s colour")
	# Renaming through data renames the speaker and the placeholder text.
	c["name"] = "Mara"
	eq(d.line()["name"], "Mara", "rename through data")
	eq(d.line()["initials"], "M", "a longer name shows its initial")
	c["name"] = "???"
	eq(Dialogue.initials_of("Agador"), "A", "Agador's placeholder shows A")
	AssetCatalog.clear_cache()


func test_new_guest_art_keys_are_listed() -> void:
	var paths: Dictionary = GameData.get_json("assets")["paths"]
	for key in ["new_guest.sprite", "new_guest.portrait.upset", "mood.upset", "inn.door_name"]:
		check(paths.has(key), "%s is listed in assets.json" % key)
	for map_id in _map_ids():
		for list in ["npcs", "objects"]:
			for t in TownMap.map_def(map_id).get(list, []):
				for s in t.get("states", []):
					if s.has("sprite"):
						check(paths.has(s["sprite"]), "%s: state sprite '%s' is listed" % [map_id, s["sprite"]])
					if s.has("mood"):
						check(paths.has("mood." + s["mood"]), "%s: mood art key 'mood.%s' is listed" % [map_id, s["mood"]])
					for k in s.get("requires", []) + s.get("unless", []):
						check(k is String and k != "", "%s: %s state flags are names" % [map_id, t["id"]])


func test_no_story_ids_in_code() -> void:
	# The scene is all data: no script names the guest, the flags or its lines.
	for dir in ["res://scripts/core/", "res://scripts/view/"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + file)
			for word in ["new_guest", "found_room_key", "met_new_guest", "She came here", "ferry_silhouette", "night_letter", "dock_end", "first_night", "saw_ferry", "Later that night"]:
				check(not src.contains(word), "%s does not mention %s" % [file, word])
