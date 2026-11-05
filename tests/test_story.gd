## Story flags, dialogue data and fight launch/return bookkeeping.
extends "res://tests/test_base.gd"

const StoryFlags = preload("res://scripts/core/story_flags.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")


func _texts(id: String, flags) -> Array:
	return Dialogue.select_entry(id, flags).get("lines", []).map(func(l): return l["text"])


func _data_texts(id: String, entry_index: int) -> Array:
	return GameData.get_json("dialogue")[id][entry_index]["lines"].map(func(l): return l["text"])


func test_dialogue_data_is_well_formed() -> void:
	var chars: Dictionary = GameData.get_json("characters")
	var encounters: Dictionary = GameData.get_json("encounters")
	for id in GameData.get_json("dialogue"):
		if id.begins_with("_"):
			continue
		var entries: Array = GameData.get_json("dialogue")[id]
		check(not entries.is_empty(), "%s has entries" % id)
		# The last entry should always play, so an interaction never goes silent.
		check(entries[-1].get("requires", []).is_empty(), "%s ends with an entry that needs no flags" % id)
		for e in entries:
			for l in e.get("lines", []):
				check(chars.has(l.get("speaker", "")), "%s: speaker '%s' is in characters.json" % [id, l.get("speaker", "")])
				check(str(l.get("text", "")) != "", "%s: line has text" % id)
			if e.has("start_fight"):
				check(encounters.has(e["start_fight"]), "%s: fight '%s' is in encounters.json" % [id, e["start_fight"]])


func test_flags_set_and_meet() -> void:
	var f = StoryFlags.new()
	check(not f.has("read_letter"), "flags start empty")
	check(f.meets([]), "no requirements are always met")
	f.set_flag("read_letter")
	check(f.has("read_letter"), "flag set")
	check(f.meets(["read_letter"]), "requires met")
	check(not f.meets(["read_letter", "won_first_fight"]), "all requirements needed")
	check(not f.meets([], ["read_letter"]), "unless blocks")
	f.clear_flag("read_letter")
	check(not f.has("read_letter"), "flag cleared")


func test_dialogue_advances_line_by_line() -> void:
	var f = StoryFlags.new()
	var d = Dialogue.new(f)
	check(d.start("innkeeper"), "innkeeper dialogue starts")
	var expected := _data_texts("innkeeper", 1)
	var seen: Array = []
	var speakers: Array = []
	var guard := 0
	while not d.finished and guard < 20:
		seen.append(d.line()["text"])
		speakers.append(d.line()["speaker"])
		d.advance()
		guard += 1
	eq(seen, expected, "all default innkeeper lines in order")
	eq(speakers[0], "innkeeper", "first speaker")
	eq(d.line(), {}, "no line after the end")
	check(not d.advance(), "advance after the end does nothing")


func test_line_uses_character_name_and_portrait_from_data() -> void:
	var d = Dialogue.new(StoryFlags.new())
	d.start("innkeeper")
	var c: Dictionary = GameData.get_json("characters")["innkeeper"]
	eq(d.line()["name"], c["name"], "speaker display name from characters.json")
	eq(d.line()["portrait"], c["portrait"], "portrait key from characters.json")


func test_letter_sets_read_letter_only_at_the_end() -> void:
	var f = StoryFlags.new()
	var d = Dialogue.new(f)
	d.start("letter")
	check(not f.has("read_letter"), "flag not set on the first line")
	while d.advance():
		pass
	check(f.has("read_letter"), "reading the whole letter sets read_letter")


func test_innkeeper_changes_after_read_letter() -> void:
	var f = StoryFlags.new()
	eq(_texts("innkeeper", f), _data_texts("innkeeper", 1), "default innkeeper dialogue")
	f.set_flag("read_letter")
	eq(_texts("innkeeper", f), _data_texts("innkeeper", 0), "innkeeper dialogue after read_letter")


func _finish(d) -> void:
	var guard := 0
	while d.advance() and guard < 50:
		guard += 1


func test_hatch_no_longer_launches_a_fight() -> void:
	check(not GameData.get_json("dialogue").has("cellar_door"), "old cellar_door interaction is gone")
	var f = StoryFlags.new()
	for flags in [[], ["read_letter"], ["won_first_fight"], ["read_letter", "won_first_fight"]]:
		f.flags.clear()
		for fl in flags:
			f.set_flag(fl)
		var d = Dialogue.new(f)
		check(d.start("cellar_hatch"), "hatch has dialogue with flags %s" % str(flags))
		eq(d.line()["text"], "It's locked. Why is it humming?", "hatch line")
		_finish(d)
		check(d.fight_request.is_empty(), "hatch never asks for a fight (flags %s)" % str(flags))
	for e in GameData.get_json("dialogue")["cellar_hatch"]:
		check(not e.has("start_fight"), "no hatch entry starts a fight")


func test_guest_book_changes_after_read_letter() -> void:
	var f = StoryFlags.new()
	eq(_texts("guest_book", f), ["My name's already in here. I haven't signed anything."], "guest book before the letter")
	f.set_flag("read_letter")
	eq(_texts("guest_book", f), ["My name's already in here. I haven't signed anything.", "The ink's wet. Just like my letter."], "guest book after the letter")
	eq(_texts("guest_book", f), _data_texts("guest_book", 0), "guest book reads data")


func test_arcade_dialogue_and_fight_request() -> void:
	var f = StoryFlags.new()
	var d = Dialogue.new(f)
	check(d.start("arcade"), "arcade starts")
	eq(_texts("arcade", f), _data_texts("arcade", 1), "first-time arcade dialogue")
	eq(d.line()["speaker"], "agador", "Agador speaks first")
	d.advance()
	eq(d.line()["speaker"], "innkeeper", "the innkeeper answers")
	d.advance()
	check(d.is_last_line(), "coin line is last")
	eq(d.line()["button"], "Insert coin", "last line's button says Insert coin (from data)")
	check(d.fight_request.is_empty(), "no fight before the last tap")
	_finish(d)
	eq(d.fight_request.get("encounter", ""), "first_fight", "Insert coin asks for first_fight")
	eq(d.fight_request.get("win_flags", []), ["won_first_fight"], "win flag comes from data")
	check(not f.has("won_first_fight"), "starting the fight does not set the win flag")


func test_arcade_after_a_win_shows_high_score_and_replays() -> void:
	var f = StoryFlags.new()
	f.set_flag("won_first_fight")
	var d = Dialogue.new(f)
	d.start("arcade")
	eq(d.line()["text"], "High score: Agador. I never entered my name.", "high-score line after a win")
	eq(_texts("arcade", f), _data_texts("arcade", 0), "after-win dialogue from data")
	_finish(d)
	eq(d.fight_request.get("encounter", ""), "first_fight", "the fight can be replayed after a win")
	# And again, and again.
	d.start("arcade")
	_finish(d)
	eq(d.fight_request.get("encounter", ""), "first_fight", "replayable more than once")


func test_locked_rooms_and_room_1_lines() -> void:
	var f = StoryFlags.new()
	var want := {
		"key_board": ["Keys for Rooms 2 and 3. Nothing for Room 4."],
		"fireplace": ["It's the coziest room I've ever seen. I don't trust it."],
		"room_1_key": ["A key to a room I never booked."],
		"room_1_bed": ["Turned down, with a mint on the pillow. Very welcoming. Very unsettling."],
		"room_2_door": ["Locked. The card says Reserved, but not for whom."],
		"room_3_door": ["Also reserved. Business must be booming."],
		"room_4_door": ["Locked, with no key on the board. There's a light on under the door."],
	}
	for id in want:
		eq(_texts(id, f), want[id], "%s dialogue" % id)
		var d = Dialogue.new(f)
		d.start(id)
		_finish(d)
		check(d.fight_request.is_empty(), "%s does not start a fight" % id)


func test_unknown_interaction_does_not_crash() -> void:
	var d = Dialogue.new(StoryFlags.new())
	check(not d.start("no_such_thing"), "unknown interaction does not start")
	check(d.finished, "runner stays finished")


func test_fight_win_sets_flag_and_keeps_town_spot() -> void:
	var s = GameSession.new()
	var spot := {"map": "lounge", "cell": Vector2i(1, 3), "facing": "up"}
	s.begin_fight({"encounter": "first_fight", "win_flags": ["won_first_fight"]}, spot)
	eq(s.encounter_id(), "first_fight", "encounter id passed to the fight")
	check(s.end_fight(true), "a fight from town returns to town")
	check(s.flags.has("won_first_fight"), "win sets won_first_fight")
	eq(s.spot(), spot, "spot (map, cell, facing) remembered")
	check(s.fight.is_empty(), "fight cleared")


func test_fight_loss_returns_without_flag() -> void:
	var s = GameSession.new()
	s.begin_fight({"encounter": "first_fight", "win_flags": ["won_first_fight"]}, {"map": "lounge", "cell": Vector2i(2, 2), "facing": "left"})
	check(s.end_fight(false), "a lost fight still returns to town")
	check(not s.flags.has("won_first_fight"), "loss does not set the flag")
	eq(s.last_result, "lost", "result recorded")
	eq(s.spot()["cell"], Vector2i(2, 2), "spot kept after a loss")
	eq(s.spot()["map"], "lounge", "map kept after a loss")


func test_replay_after_win_keeps_flag_and_loss_does_not_clear_it() -> void:
	var s = GameSession.new()
	var req := {"encounter": "first_fight", "win_flags": ["won_first_fight"]}
	var spot := {"map": "lounge", "cell": Vector2i(1, 3), "facing": "up"}
	s.begin_fight(req, spot)
	s.end_fight(true)
	s.begin_fight(req, spot)
	eq(s.encounter_id(), "first_fight", "second fight runs the same encounter")
	check(s.end_fight(false), "replay returns to town")
	check(s.flags.has("won_first_fight"), "losing a replay keeps won_first_fight")
	eq(s.spot(), spot, "replay returns to the same spot")


func test_direct_fight_does_not_return_to_town() -> void:
	var s = GameSession.new()
	s.begin_direct_fight()
	eq(s.encounter_id(), GameData.DEFAULT_ENCOUNTER, "direct fight uses the default encounter")
	check(not s.end_fight(true), "direct fight stays out of town")
	check(s.flags.names().is_empty(), "direct fight sets no story flags")


func test_encounter_id_builds_that_encounter() -> void:
	var st = LevelLoader.build_encounter("first_fight")
	var enc: Dictionary = GameData.encounter("first_fight")
	eq(st.living("enemy").size(), enc["enemies"].size(), "encounter by id has its enemies")
	eq(st.rng_seed, int(enc["seed"]), "encounter seed used")


func test_hero_display_names_come_from_data() -> void:
	var heroes: Dictionary = GameData.get_json("heroes")
	for id in ["tide", "volt", "ember"]:
		check(heroes.has(id), "hero %s in heroes.json" % id)
		eq(LevelLoader.make_hero(id, Vector2i.ZERO).name, heroes[id]["name"], "%s display name read from data" % id)
	# Renaming in data renames the unit, with no code change.
	var old: String = heroes["tide"]["name"]
	heroes["tide"]["name"] = "Renamed"
	eq(LevelLoader.make_hero("tide", Vector2i.ZERO).name, "Renamed", "renamed hero picks up the new name")
	heroes["tide"]["name"] = old
	# No script hard-codes a hero display name.
	for dir in ["res://scripts/core/", "res://scripts/view/"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + file)
			for id in heroes:
				check(not src.contains('"%s"' % heroes[id]["name"]), "%s does not hard-code '%s'" % [file, heroes[id]["name"]])


func test_agador_id_name_and_portrait_from_data() -> void:
	const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")
	var chars: Dictionary = GameData.get_json("characters")
	check(chars.has("agador") and not chars.has("believer"), "town character id is agador")
	eq(chars["agador"]["name"], "Agador", "display name lives in data")
	eq(chars["agador"]["portrait"], "agador.portrait.neutral", "portrait key")
	eq(AssetCatalog.path(chars["agador"]["portrait"]), GameData.get_json("assets")["paths"]["agador.portrait.neutral"], "portrait key resolves through assets.json")
	eq(AssetCatalog.path(chars["agador"]["sprite"]), GameData.get_json("assets")["paths"]["agador.sprite"], "sprite key resolves through assets.json")
	# A dialogue line spoken by agador shows the data name and portrait key.
	var f = StoryFlags.new()
	var d = Dialogue.new(f)
	d.start("welcome_banner")
	eq(d.line()["speaker"], "agador", "banner is spoken by agador")
	eq(d.line()["name"], chars["agador"]["name"], "line shows Agador's display name")
	eq(d.line()["portrait"], chars["agador"]["portrait"], "line uses Agador's portrait key")
	# Renaming in data renames the speaker, no code change.
	chars["agador"]["name"] = "Renamed"
	eq(d.line()["name"], "Renamed", "rename through data")
	chars["agador"]["name"] = "Agador"
	for dir in ["res://scripts/core/", "res://scripts/view/"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				check(not FileAccess.get_file_as_string(dir + file).to_lower().contains("believer"), "%s has no leftover 'believer'" % file)
				check(not FileAccess.get_file_as_string(dir + file).contains('"Agador"'), "%s does not hard-code Agador's name" % file)
