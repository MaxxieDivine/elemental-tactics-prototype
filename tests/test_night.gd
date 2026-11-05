## The first night: time of day as a story value, time-based world-state and
## dialogue rules, lighting presets, transition cards, trigger zones, object
## fades, and the night's story beats from data, with no softlocks.
extends "res://tests/test_base.gd"

const TownMap = preload("res://scripts/core/town_map.gd")
const WorldState = preload("res://scripts/core/world_state.gd")
const StoryFlags = preload("res://scripts/core/story_flags.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const Lighting = preload("res://scripts/core/lighting.gd")

const NIGHT_FLAGS := ["found_room_key", "met_new_guest", "first_night_started"]


func _flags(names: Array, time: String = ""):
	var f = StoryFlags.new()
	for n in names:
		f.set_flag(n)
	if time != "":
		f.set_time_of_day(time)
	return f


func _texts(id: String, flags) -> Array:
	return Dialogue.select_entry(id, flags).get("lines", []).map(func(l): return l["text"])


## Plays an interaction to the end. Returns the steps it handed out.
func _play(id: String, flags) -> Array:
	var d = Dialogue.new(flags)
	var steps: Array = []
	if not d.start(id):
		return steps
	var guard := 0
	while guard < 50:
		guard += 1
		var more: bool = d.advance()
		var s: Dictionary = d.take_step()
		if not s.is_empty():
			steps.append(s)
		if not more:
			break
	return steps


func _map_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/maps/"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


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


## Where an interaction is used from: [{"map", "id", "stand"}] for every
## NPC/object (in any state) that plays it.
func _users(interaction: String) -> Array:
	var out: Array = []
	for map_id in _map_ids():
		for list in ["npcs", "objects"]:
			for t in TownMap.map_def(map_id).get(list, []):
				var ids: Array = [str(t.get("interaction", ""))]
				for s in t.get("states", []):
					ids.append(str(s.get("interaction", "")))
				if ids.has(interaction):
					out.append({"map": map_id, "id": t["id"], "def": t})
	return out


func _raw(map_id: String, thing_id: String) -> Dictionary:
	for list in ["npcs", "objects"]:
		for t in TownMap.map_def(map_id).get(list, []):
			if t["id"] == thing_id:
				return t
	return {}


func _trigger(map_id: String, id: String) -> Dictionary:
	for t in TownMap.map_def(map_id).get("triggers", []):
		if t["id"] == id:
			return t
	return {}


# --- Time of day as a story value -------------------------------------------------

func test_time_of_day_starts_from_data_and_changes_only_when_set() -> void:
	var f = StoryFlags.new()
	eq(f.time_of_day(), GameData.get_json("town")["time_of_day"]["start"], "a new story starts at the data time")
	eq(f.time_of_day(), "day", "that is day")
	eq(StoryFlags.times(), ["day", "night"], "the story knows day and night")
	check(f.set_time_of_day("night"), "setting night changes the time")
	eq(f.time_of_day(), "night", "now night")
	check(not f.set_time_of_day("night"), "setting the same time is not a change")
	check(not f.set_time_of_day("dusk"), "an unknown time is refused")
	eq(f.time_of_day(), "night", "and leaves the time alone")
	check(f.names().is_empty(), "the time is not a flag")


func test_dialogue_data_changes_time_of_day() -> void:
	# A synthetic entry: its line's 'then' step sets the time and a flag the
	# moment the line is left, and hands the step to the view.
	var dlg: Dictionary = GameData.get_json("dialogue")
	dlg["_test_dusk"] = [{"lines": [
		{"speaker": "agador", "text": "One.", "then": {"card": "Later", "set_time": "night", "set_flags": ["t_slept"]}},
		{"speaker": "agador", "text": "Two."},
	], "set_time": "day", "set_flags": ["t_woke"]}]
	var f = StoryFlags.new()
	var d = Dialogue.new(f)
	# Underscore ids are not interactions; play the entry directly.
	d.interaction_id = "_test_dusk"
	d.entry = dlg["_test_dusk"][0]
	d.index = 0
	d.finished = false
	eq(f.time_of_day(), "day", "day before the line ends")
	check(d.advance(), "a line follows the step")
	eq(f.time_of_day(), "night", "the step set night")
	check(f.has("t_slept"), "the step set its flag")
	var step: Dictionary = d.take_step()
	eq(step.get("card", ""), "Later", "the view gets the step's card")
	check(d.take_step().is_empty(), "taking a step clears it")
	check(not d.advance(), "the entry ends")
	eq(f.time_of_day(), "day", "an entry's own set_time applies at the end")
	check(f.has("t_woke"), "with its flags")
	dlg.erase("_test_dusk")


func test_time_persists_across_map_changes_and_fights() -> void:
	var s = GameSession.new()
	s.flags.set_time_of_day("night")
	var exit: Dictionary = TownMap.map_def("lobby")["exits"][0]
	s.go_through(exit)
	eq(s.flags.time_of_day(), "night", "night after going through an exit")
	eq(TownMap.load_map(s.spot()["map"], s.flags).def.get("id"), s.spot()["map"], "maps load with the session's flags")
	s.begin_fight({"encounter": "first_fight", "win_flags": []}, {"map": "lounge", "cell": Vector2i(2, 2), "facing": "left"})
	eq(s.flags.time_of_day(), "night", "night during a town fight")
	check(s.end_fight(false), "a lost fight goes back to town")
	eq(s.flags.time_of_day(), "night", "night after losing")
	s.begin_fight({"encounter": "first_fight", "win_flags": ["w"]}, {"map": "lounge", "cell": Vector2i(2, 2), "facing": "left"})
	s.end_fight(true)
	eq(s.flags.time_of_day(), "night", "night after winning")
	eq(s.spot()["map"], "lounge", "back where the fight was launched")
	# A direct fight from the start screen leaves the story alone.
	var fresh = GameSession.new()
	fresh.begin_direct_fight()
	check(not fresh.end_fight(true), "a direct fight does not go to town")
	eq(fresh.flags.time_of_day(), "day", "a direct fight does not touch the time")
	s.begin_direct_fight()
	s.end_fight(true)
	eq(s.flags.time_of_day(), "night", "nor a story's time")


# --- Rules using flags and time ------------------------------------------------------

func test_rules_use_flags_time_or_both() -> void:
	var day = _flags(["a"])
	var night = _flags(["a"], "night")
	check(day.meets_rule({}), "an empty rule always matches")
	check(night.meets_rule({"time_of_day": "night"}), "time only")
	check(not day.meets_rule({"time_of_day": "night"}), "time only, wrong time")
	check(night.meets_rule({"requires": ["a"], "time_of_day": "night"}), "flags and time")
	check(not night.meets_rule({"requires": ["b"], "time_of_day": "night"}), "flags and time: flag missing")
	check(not night.meets_rule({"unless": ["a"], "time_of_day": "night"}), "flags and time: unless blocks")
	check(day.meets_rule({"time_of_day": ["day", "night"]}), "a list of times")
	var t := {"id": "x", "cell": [0, 0], "states": [{"time_of_day": "night", "cell": [1, 1]}]}
	eq(WorldState.resolve_thing(t, day)["cell"], [0, 0], "day: base definition")
	eq(WorldState.resolve_thing(t, night)["cell"], [1, 1], "night: the night state")
	check(not WorldState.resolve_thing(t, night).has("time_of_day"), "the rule key is not copied onto the thing")
	# Dialogue entries can ask for a time too.
	eq(_texts("cellar_hatch", _flags([], "night")), ["It's louder at night."], "hatch at night")
	eq(_texts("cellar_hatch", _flags([])), ["It's locked. Why is it humming?"], "hatch in the day")


func test_priority_when_several_states_match_with_time() -> void:
	var t := {"id": "x", "cell": [0, 0], "states": [
		{"time_of_day": "night", "cell": [1, 0]},
		{"requires": ["a"], "time_of_day": "night", "priority": 5, "cell": [2, 0]},
		{"requires": ["a"], "priority": 1, "cell": [3, 0]},
		{"requires": ["a", "b"], "priority": 9, "hidden": true},
	]}
	eq(WorldState.resolve_thing(t, _flags([], "night"))["cell"], [1, 0], "night alone")
	eq(WorldState.resolve_thing(t, _flags(["a"], "night"))["cell"], [2, 0], "flag + night beats the flag alone")
	eq(WorldState.resolve_thing(t, _flags(["a"]))["cell"], [3, 0], "day: the night states do not match")
	check(WorldState.resolve_thing(t, _flags(["a", "b"], "night")).is_empty(), "the highest priority wins, even hidden")
	var tie := {"id": "x", "cell": [0, 0], "states": [{"time_of_day": "night", "cell": [1, 1]}, {"requires": ["a"], "cell": [2, 2]}]}
	eq(WorldState.resolve_thing(tie, _flags(["a"], "night"))["cell"], [1, 1], "a tie goes to the first listed")


# --- Lighting ---------------------------------------------------------------------

func test_lighting_preset_by_map_and_time() -> void:
	var presets: Dictionary = GameData.get_json("town")["lighting_presets"]
	for map_id in _map_ids():
		var d := TownMap.map_def(map_id)
		var name := Lighting.preset_name(d)
		check(presets.has(name), "%s uses a known preset ('%s')" % [map_id, name])
		eq(Lighting.preset_for(d, "day"), presets[name]["day"], "%s: day preset from data" % map_id)
		eq(Lighting.preset_for(d, "night"), presets[name]["night"], "%s: night preset from data" % map_id)
	eq(Lighting.preset_name(TownMap.map_def("town")), "outdoor", "the town is outdoors")
	for inn in ["lobby", "lounge", "hallway", "room_1"]:
		eq(Lighting.preset_name(TownMap.map_def(inn)), "inn", "%s is inside the inn" % inn)
	var town_day := Lighting.preset_for(TownMap.map_def("town"), "day")
	var town_night := Lighting.preset_for(TownMap.map_def("town"), "night")
	var inn_night := Lighting.preset_for(TownMap.map_def("lobby"), "night")
	eq(Lighting.tint(town_day, "tint"), Color.WHITE, "day: no tint")
	check(Lighting.tint(town_night, "tint").get_luminance() < 0.45, "outdoor night is clearly dark")
	check(Lighting.tint(town_night, "tint").b > Lighting.tint(town_night, "tint").r, "outdoor night is blue")
	check(Lighting.tile_tint(town_night, "~").get_luminance() < Lighting.tint(town_night, "tint").get_luminance(), "water is darker still")
	check(Lighting.tile_tint(town_night, "=").get_luminance() > Lighting.tint(town_night, "tint").get_luminance(), "the dock path stays lighter than the ground")
	check(Lighting.tint(inn_night, "tint").get_luminance() > 0.7, "the inn at night only dims slightly")
	check(Lighting.tint(inn_night, "tint").r > Lighting.tint(inn_night, "tint").b, "and stays warm")
	for p in [town_night, inn_night]:
		check(Lighting.tint(p, "actor_tint").get_luminance() > 0.75, "characters and tappable things stay easy to see")
	# Inline presets, and unknown ones.
	var inline := {"lighting": {"night": {"tint": "#000000"}}}
	eq(Lighting.preset_for(inline, "night")["tint"], "#000000", "an inline preset")
	check(Lighting.preset_for(inline, "day").is_empty(), "a missing time is no change")
	check(Lighting.preset_for({}, "night").is_empty(), "no lighting: no change")


func test_tint_keys_and_glow_spots() -> void:
	eq(Lighting.tint_key("npc", {}), "actor_tint", "characters")
	eq(Lighting.tint_key("object", {"interaction": "letter"}), "actor_tint", "tappable objects")
	eq(Lighting.tint_key("prop", {}), "prop_tint", "props")
	eq(Lighting.tint_key("prop", {"glow": "lamp"}), "lit_tint", "lamps")
	var flags = _flags(NIGHT_FLAGS, "night")
	var town = TownMap.load_map("town", flags)
	var night := Lighting.preset_for(town.def, "night")
	var spots: Array = Lighting.glows(town, night, 16)
	var lamps := 0
	for p in town.def["props"]:
		if p.get("glow", "") == "lamp":
			lamps += 1
	check(lamps >= 2, "the town has lamps")
	eq(spots.filter(func(s): return s["id"].begins_with("prop_")).size(), lamps * Lighting.glow_shapes(night, "lamp").size(), "a pool for every lamp shape")
	check(spots.any(func(s): return s["id"] == "ferry_silhouette"), "the ferry's lantern glows")
	check(spots.any(func(s): return s["id"] == "" and s["shape"].get("blend", "add") == "mix"), "lit inn windows outside")
	eq(Lighting.glows(town, Lighting.preset_for(town.def, "day"), 16), [], "no pools in the day")
	for name in GameData.get_json("town")["lighting_presets"]:
		if name.begins_with("_"):
			continue
		for time in GameData.get_json("town")["lighting_presets"][name]:
			var p: Dictionary = GameData.get_json("town")["lighting_presets"][name][time]
			for kind in p.get("glows", {}):
				for sh in Lighting.glow_shapes(p, kind):
					check(sh.has("radius") or sh.has("rect"), "%s/%s/%s: a pool or a pane" % [name, time, kind])


# --- Transition cards and steps -----------------------------------------------------

func test_transition_cards_and_steps_in_data() -> void:
	var dlg: Dictionary = GameData.get_json("dialogue")
	var cards: Array = []
	for id in dlg:
		if id.begins_with("_"):
			continue
		for e in dlg[id]:
			for i in e["lines"].size():
				var st: Dictionary = e["lines"][i].get("then", {})
				if st.is_empty():
					continue
				check(i < e["lines"].size() - 1 or not st.has("card"), "%s: a card is followed by a line" % id)
				if st.has("card"):
					check(str(st["card"]).strip_edges() != "", "%s: card text is not empty" % id)
					cards.append(st["card"])
				if st.has("set_time"):
					check(StoryFlags.times().has(st["set_time"]), "%s: set_time '%s' is a known time" % [id, st["set_time"]])
				for k in st:
					check(["card", "card_time", "set_time", "set_flags", "place", "facing", "fade_out", "fade_in", "fade_time", "_comment"].has(k), "%s: step key '%s' is known" % [id, k])
				if st.has("place"):
					# Placed on a free cell where the thing that plays it can be used.
					for u in _users(id):
						var m = TownMap.load_map(u["map"], _flags(NIGHT_FLAGS + ["read_night_letter"], "night"))
						var c := TownMap.cell_of(st["place"])
						check(m.is_walkable(c), "%s: place %s is free on %s" % [id, str(c), u["map"]])
						check(m.can_use_from(u["id"], c), "%s: place %s is beside %s" % [id, str(c), u["id"]])
				for oid in st.get("fade_out", []) + st.get("fade_in", []):
					check(_users_of_id(oid), "%s: faded thing '%s' is on a map" % [id, oid])
	cards.sort()
	eq(cards, ["Later that night", "The next morning"], "the two cards, in data")
	check(float(GameData.get_json("town")["card_time"]) <= 3.0, "cards are brief")


func _users_of_id(thing_id: String) -> bool:
	for map_id in _map_ids():
		if not _raw(map_id, thing_id).is_empty():
			return true
	return false


# --- Trigger zones -----------------------------------------------------------------

func test_trigger_requirements_and_run_once() -> void:
	var def := {
		"tiles": {".": {"walkable": true}},
		"map": ["....", "...."],
		"triggers": [
			{"id": "t_any", "cell": [0, 0], "interaction": "letter"},
			{"id": "t_once", "cells": [[1, 0], [2, 0]], "interaction": "letter", "once": true, "requires": ["a"], "time_of_day": "night"},
		],
	}
	var m = TownMap.from_data(def)
	var f = _flags([])
	eq(m.trigger_at(Vector2i(0, 0), f).get("id", ""), "t_any", "a trigger with no rule always runs")
	check(m.trigger_at(Vector2i(3, 1), f).is_empty(), "no trigger on other cells")
	check(m.trigger_at(Vector2i(1, 0), f).is_empty(), "requires: flag missing")
	f.set_flag("a")
	check(m.trigger_at(Vector2i(1, 0), f).is_empty(), "requires: wrong time of day")
	f.set_time_of_day("night")
	eq(m.trigger_at(Vector2i(2, 0), f).get("id", ""), "t_once", "flags and time met, on any of its cells")
	f.mark_ran("t_once")
	check(m.trigger_at(Vector2i(1, 0), f).is_empty(), "a once trigger does not run again")
	f.mark_ran("t_any")
	eq(m.trigger_at(Vector2i(0, 0), f).get("id", ""), "t_any", "a trigger without once runs every time")


func test_dock_trigger_from_data() -> void:
	var t := _trigger("town", "dock_end_trigger")
	check(not t.is_empty(), "the dock trigger is in the town data")
	check(bool(t.get("once", false)), "it runs once")
	eq(t["interaction"], "dock_end_trigger", "it plays its interaction")
	var cells: Array = TownMap.exit_cells_of(t)
	for flags in [[], ["met_new_guest"], NIGHT_FLAGS + ["saw_ferry"], NIGHT_FLAGS + ["first_night_over"]]:
		for time in ["day", "night"]:
			var f = _flags(flags, time)
			var m = TownMap.load_map("town", f)
			check(cells.all(func(c): return m.trigger_at(c, f).is_empty()), "no dock scene with %s at %s" % [str(flags), time])
	check(cells.all(func(c): return TownMap.load_map("town", _flags(NIGHT_FLAGS)).trigger_at(c, _flags(NIGHT_FLAGS)).is_empty()), "not in the day")
	var night = _flags(NIGHT_FLAGS, "night")
	var town = TownMap.load_map("town", night)
	for c in cells:
		check(town.is_walkable(c), "trigger cell %s is free dock" % str(c))
		eq(town.trigger_at(c, night).get("id", ""), "dock_end_trigger", "the night of the first night: %s triggers" % str(c))
	# The only way onto the end of the dock goes through the trigger.
	var dock_end := Vector2i(6, 16)
	var p: Array = town.find_path(GameSession.start_spot()["cell"], dock_end)
	check(not p.is_empty() and p.any(func(c): return cells.has(c)), "walking to the end of the dock crosses the trigger")
	var ferry: Vector2i = town.cell_of_thing("ferry_silhouette")
	check(ferry.x > dock_end.x and absi(ferry.y - dock_end.y) <= 1, "the ferry is offshore, beside the dock end")


# --- The night's story beats --------------------------------------------------------

func test_ferry_disappears_and_saw_ferry_is_set() -> void:
	var f = _flags(NIGHT_FLAGS, "night")
	check(TownMap.load_map("town", f).targets.has("night_letter") == false, "no new letter before the dock")
	check(TownMap.load_map("town", f).things.values().has("ferry_silhouette"), "the ferry is offshore")
	check(TownMap.load_map("town", _flags(NIGHT_FLAGS)).things.values().has("ferry_silhouette") == false, "only at night")
	var d = Dialogue.new(f)
	check(d.start("dock_end_trigger"), "the dock scene starts")
	eq(d.line()["text"], "The ferry? At this hour?", "first line")
	check(d.advance(), "a second line follows")
	var step: Dictionary = d.take_step()
	eq(step.get("fade_out", []), ["ferry_silhouette"], "the ferry fades out between the lines")
	eq(step.get("fade_in", []), ["night_letter"], "and the new letter fades in")
	check(not (step.has("card") or step.has("set_time") or step.has("place")), "no screen fade for the ferry")
	check(f.has("saw_ferry"), "saw_ferry is set as the ferry fades")
	eq(d.line()["text"], "Where did it go?", "second line")
	var m = TownMap.load_map("town", f)
	check(not m.things.values().has("ferry_silhouette"), "the ferry is gone")
	check(m.targets.has("night_letter"), "the new letter is there")
	eq(m.cell_of_thing("night_letter"), TownMap.cell_of(_raw("town", "letter")["cell"]), "in the old letter's spot")
	check(not m.targets.has("letter"), "the old letter is not")


func test_night_letter_sets_read_night_letter() -> void:
	var f = _flags(NIGHT_FLAGS + ["saw_ferry"], "night")
	eq(_texts("night_letter", f), ["Another letter. The ink's still wet.", "'See you Tuesday.'"], "night letter lines")
	_play("night_letter", f)
	check(f.has("read_night_letter"), "reading it sets read_night_letter")
	check(TownMap.load_map("town", f).targets.has("night_letter"), "it stays readable")


func test_bed_before_during_and_after_the_night() -> void:
	var original := ["Turned down, with a mint on the pillow. Very welcoming. Very unsettling."]
	eq(_texts("room_1_bed", _flags([])), original, "before ???: the old line")
	eq(_texts("room_1_bed", _flags(["found_room_key", "read_letter", "won_first_fight"])), original, "no sleep before meeting ???")
	check(_play("room_1_bed", _flags(["found_room_key"])).is_empty(), "no sleep step before meeting ???")
	# Sleep after meeting ???.
	var f = _flags(["found_room_key", "met_new_guest"])
	eq(_texts("room_1_bed", f), ["It's been a long day.", "Was that a bell?"], "sleep after meeting ???")
	eq(Dialogue.select_entry("room_1_bed", f)["lines"][0].get("button", ""), "Sleep", "the button says Sleep")
	var steps: Array = _play("room_1_bed", f)
	eq(steps.size(), 1, "one step")
	eq(steps[0].get("card", ""), "Later that night", "the card")
	eq(f.time_of_day(), "night", "it is night")
	check(f.has("first_night_started"), "first_night_started")
	# During the night, before the letter.
	for extra in [[], ["saw_ferry"]]:
		var n = _flags(NIGHT_FLAGS + extra, "night")
		eq(_texts("room_1_bed", n), ["Not until I find out what that bell was."], "no sleep yet %s" % str(extra))
		check(_play("room_1_bed", n).is_empty(), "no step %s" % str(extra))
		eq(n.time_of_day(), "night", "still night %s" % str(extra))
	# After the letter: sleep to the morning.
	var l = _flags(NIGHT_FLAGS + ["saw_ferry", "read_night_letter"], "night")
	eq(_texts("room_1_bed", l), ["I won't sleep, but I should try.", "Morning. At least the sun still works."], "sleep after the letter")
	steps = _play("room_1_bed", l)
	eq(steps[0].get("card", ""), "The next morning", "the morning card")
	eq(l.time_of_day(), "day", "day again")
	check(l.has("first_night_over"), "first_night_over")
	eq(_texts("room_1_bed", l), original, "after the night: the old line")
	check(_play("room_1_bed", l).is_empty(), "no sleeping again")
	eq(l.time_of_day(), "day", "still day")


func test_night_world_state_from_data() -> void:
	var day_after = _flags(["found_room_key", "met_new_guest"])
	var night = _flags(NIGHT_FLAGS, "night")
	check(TownMap.load_map("lobby", day_after).targets.has("innkeeper"), "innkeeper in the lobby before the night")
	check(not TownMap.load_map("lobby", night).targets.has("innkeeper"), "innkeeper away at night")
	check(TownMap.load_map("lounge", night).targets.has("new_guest"), "??? beside the arcade at night")
	eq(TownMap.load_map("lounge", night).cell_of_thing("new_guest"), TownMap.load_map("lounge", day_after).cell_of_thing("new_guest"), "in the same spot")
	check(TownMap.load_map("lounge", night).targets.has("arcade"), "the arcade is there at night")
	check(not TownMap.load_map("town", night).targets.has("letter"), "the letter is hidden at night")
	check(TownMap.load_map("town", night).targets.has("inn_front_door"), "the inn door still works")
	eq(_texts("new_guest", night), ["Did you hear that bell?", "What bell?"], "??? at night")
	eq(_texts("welcome_banner", night), ["Even in the dark, it still says Heros."], "banner at night")
	eq(_texts("cellar_hatch", night), ["It's louder at night."], "hatch at night")
	var arcade_day: Array = _texts("arcade", day_after)
	eq(_texts("arcade", night), arcade_day, "the arcade is unchanged at night")
	eq(Dialogue.select_entry("arcade", night).get("start_fight", ""), "first_fight", "and still starts the fight")


func test_morning_restores_npcs_and_objects() -> void:
	var day_after = _flags(["found_room_key", "met_new_guest"])
	var morning = _flags(NIGHT_FLAGS + ["saw_ferry", "read_night_letter", "first_night_over"])
	for map_id in _map_ids():
		var before = TownMap.load_map(map_id, day_after)
		var after = TownMap.load_map(map_id, morning)
		eq(after.def["npcs"], before.def["npcs"], "%s: the same NPCs as before the night" % map_id)
		eq(after.def["objects"], before.def["objects"], "%s: the same objects as before the night" % map_id)
	var town = TownMap.load_map("town", morning)
	check(town.targets.has("letter") and not town.targets.has("night_letter"), "the old letter is back, the new one gone")
	check(not town.things.values().has("ferry_silhouette"), "no ferry in the morning")
	eq(_texts("innkeeper", morning), ["I saw the ferry last night.", "The ferry will be back any day now.", "It was here.", "Any day now."], "the innkeeper's morning line")
	eq(Dialogue.select_entry("innkeeper", morning)["lines"][2]["speaker"], "agador", "Agador insists")
	for id in ["new_guest", "welcome_banner", "cellar_hatch", "guest_book", "room_2_door", "fireplace", "key_board"]:
		eq(_texts(id, morning), _texts(id, day_after), "%s: daytime lines in the morning" % id)
	eq(morning.time_of_day(), "day", "the morning is day")


# --- No softlock ---------------------------------------------------------------------

## Every flag/time state the night can be in, as the story moves forward.
func _night_states() -> Array:
	return [
		[NIGHT_FLAGS, "night"],
		[NIGHT_FLAGS + ["saw_ferry"], "night"],
		[NIGHT_FLAGS + ["saw_ferry", "read_night_letter"], "night"],
		[NIGHT_FLAGS + ["saw_ferry", "read_night_letter", "first_night_over"], "day"],
		[NIGHT_FLAGS + ["read_letter", "won_first_fight"], "night"],
	]


func test_no_softlock_during_the_night() -> void:
	# In every state of the night, every map is reachable through exits, every
	# exit/NPC/object on a map is usable from every arrival, the arcade works,
	# and the next story step is somewhere you can reach.
	for st in _night_states():
		var f = _flags(st[0], st[1])
		var reached := {GameSession.start_spot()["map"]: true}
		var queue: Array = [GameSession.start_spot()["map"]]
		while not queue.is_empty():
			var id: String = queue.pop_front()
			var m = TownMap.load_map(id, f)
			for from in _arrivals(id):
				check(m.is_walkable(from), "%s %s: arrival %s free" % [id, str(st), str(from)])
				for tid in m.targets:
					var a: Dictionary = m.approach_target(from, tid)
					check(not a.is_empty(), "%s %s: %s reachable from %s" % [id, str(st), tid, str(from)])
			for e in m.def.get("exits", []):
				if not reached.has(e["to"]):
					reached[e["to"]] = true
					queue.append(e["to"])
		eq(reached.size(), _map_ids().size(), "%s: every map reachable" % str(st))
		var lounge = TownMap.load_map("lounge", f)
		check(lounge.targets.has("arcade") and Dialogue.select_entry("arcade", f).has("start_fight"), "%s: the arcade still starts its fight" % str(st))
	# Step by step: what moves the story on is always there.
	var f = _flags(NIGHT_FLAGS, "night")
	var town = TownMap.load_map("town", f)
	var dock: Dictionary = _trigger("town", "dock_end_trigger")
	check(TownMap.exit_cells_of(dock).any(func(c): return not town.find_path(GameSession.start_spot()["cell"], c).is_empty()), "the dock trigger can be reached")
	f.set_flag("saw_ferry")
	check(TownMap.load_map("town", f).targets.has("night_letter"), "the letter is there to read after the ferry")
	f.set_flag("read_night_letter")
	check(not _play("room_1_bed", f).is_empty(), "then the bed lets Agador sleep")


func test_time_only_changes_through_the_bed() -> void:
	# A fight, a map change or another conversation never changes the time, so
	# the night cannot end early or start twice.
	var setters: Array = []
	var dlg: Dictionary = GameData.get_json("dialogue")
	for id in dlg:
		if id.begins_with("_"):
			continue
		for e in dlg[id]:
			if e.has("set_time"):
				setters.append(id)
			for l in e["lines"]:
				if l.get("then", {}).has("set_time"):
					setters.append(id)
	eq(setters, ["room_1_bed", "room_1_bed"], "only the bed changes the time (to night, then to day)")
	# Sleeping to night only once: the entry needs first_night_started unset.
	var f = _flags(NIGHT_FLAGS + ["saw_ferry", "read_night_letter", "first_night_over"])
	_play("room_1_bed", f)
	eq(f.time_of_day(), "day", "the bed does not start another night")
