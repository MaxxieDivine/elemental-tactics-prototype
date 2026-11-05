## The cellar milestone in the world: the hatch opening after the first night,
## the dialogue step that changes maps, the cellar's trigger, fight returns
## after a win or a loss, the obstacle and rats clearing, the luggage, ???,
## the innkeeper, the dock office and its light, and the Cellar test shortcut.
extends "res://tests/test_base.gd"

const TownMap = preload("res://scripts/core/town_map.gd")
const StoryFlags = preload("res://scripts/core/story_flags.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const WorldLinks = preload("res://tests/world_links.gd")

const NIGHT_DONE := ["read_letter", "found_room_key", "met_new_guest", "first_night_started", "saw_ferry", "read_night_letter", "first_night_over"]
const LUGGAGE := ["agador_suitcase", "blank_tags", "ribbon_case", "humming_case"]


func _flags(names: Array, time: String = ""):
	var f = StoryFlags.new()
	for n in names:
		f.set_flag(n)
	if time != "":
		f.set_time_of_day(time)
	return f


func _texts(id: String, flags) -> Array:
	return Dialogue.select_entry(id, flags).get("lines", []).map(func(l): return l["text"])


## Plays an interaction to the end; returns its steps.
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


func _trigger(map_id: String, id: String) -> Dictionary:
	for t in TownMap.map_def(map_id).get("triggers", []):
		if t["id"] == id:
			return t
	return {}


func _cellar(names: Array):
	return TownMap.load_map("cellar", _flags(names))


# --- The hatch ------------------------------------------------------------------

func test_hatch_stays_locked_before_the_night_ends() -> void:
	for st in [[[], ""], [["read_letter"], ""], [["met_new_guest"], ""], [["met_new_guest", "first_night_started"], "night"], [["met_new_guest", "first_night_started", "read_night_letter"], "night"]]:
		var f = _flags(st[0], st[1])
		var steps := _play("cellar_hatch", f)
		check(steps.is_empty(), "%s: the hatch does not open" % str(st))
		var lines := _texts("cellar_hatch", f)
		check(lines == ["It's locked. Why is it humming?"] or lines == ["It's louder at night."], "%s: the old hatch lines (%s)" % [str(st), str(lines)])
		eq(TownMap.load_map("town", f).targets["cellar_hatch"]["def"]["shape"], "hatch", "%s: the padlock is still on" % str(st))


func test_hatch_opens_after_the_first_night() -> void:
	var f = _flags(NIGHT_DONE)
	eq(_texts("cellar_hatch", f), ["The lock's gone. It wasn't like that last night."], "the lock is gone")
	eq(Dialogue.select_entry("cellar_hatch", f)["lines"][0].get("button", ""), "Go down", "the button says Go down")
	var steps := _play("cellar_hatch", f)
	eq(steps.size(), 1, "one step")
	eq(steps[0].get("go_to", ""), "cellar", "it goes down to the cellar")
	var place := TownMap.cell_of(steps[0]["place"])
	check(_cellar(NIGHT_DONE).is_walkable(place), "onto a free cellar tile")
	eq(f.names(), _flags(NIGHT_DONE).names(), "going down sets no flags")
	f.set_flag("won_cellar_fight")
	eq(_texts("cellar_hatch", f), ["It's still humming."], "after the fight")
	eq(_play("cellar_hatch", f)[0].get("go_to", ""), "cellar", "and still goes down")


func test_cellar_stairs_lead_back_beside_the_hatch() -> void:
	var exit: Dictionary = {}
	for e in TownMap.map_def("cellar")["exits"]:
		exit = e
	eq(exit["to"], "town", "the stairs go up to the town")
	var town = TownMap.load_map("town", _flags(NIGHT_DONE))
	var back := TownMap.cell_of(exit["arrive"])
	check(town.can_use_from("cellar_hatch", back), "arriving beside the hatch")
	eq(TownMap.arrival(exit)["facing"], town.facing_to_target(back, "cellar_hatch"), "facing it")
	var down := TownMap.cell_of(_play("cellar_hatch", _flags(NIGHT_DONE))[0]["place"])
	var cellar = _cellar(NIGHT_DONE)
	check(cellar.can_use_from("cellar_stairs", down), "Agador arrives at the foot of the stairs")


func test_town_hatch_looks_unlocked_after_the_night() -> void:
	var t = TownMap.load_map("town", _flags(NIGHT_DONE))
	eq(t.targets["cellar_hatch"]["def"]["shape"], "hatch_unlocked", "no padlock")
	check(t.targets["cellar_hatch"]["def"].has("sprite"), "with its own art key")


# --- The trigger and the fight ----------------------------------------------------------

func test_fight_trigger_requirements() -> void:
	var t := _trigger("cellar", "cellar_fight_trigger")
	check(not t.is_empty(), "the trigger is in the cellar's data")
	eq(t["interaction"], "cellar_fight_trigger", "it plays its interaction")
	eq(t.get("requires", []), ["first_night_over"], "it needs the first night over")
	eq(t.get("unless", []), ["won_cellar_fight"], "and not after a win")
	check(not bool(t.get("once", false)), "it can run again after a loss")
	var cells: Array = TownMap.exit_cells_of(t)
	for names in [NIGHT_DONE, NIGHT_DONE + ["found_pell_name"]]:
		var f = _flags(names)
		var m = TownMap.load_map("cellar", f)
		for c in cells:
			check(m.is_walkable(c), "trigger cell %s is free floor" % str(c))
			eq(m.trigger_at(c, f).get("id", ""), "cellar_fight_trigger", "%s starts the fight" % str(c))
	var won = _flags(NIGHT_DONE + ["won_cellar_fight"])
	var mw = TownMap.load_map("cellar", won)
	check(cells.all(func(c): return mw.trigger_at(c, won).is_empty()), "no fight after a win")
	var early = _flags(["met_new_guest"])
	var me = TownMap.load_map("cellar", early)
	check(cells.all(func(c): return me.trigger_at(c, early).is_empty()), "no fight before the night ends")
	# Its dialogue starts cellar_rats and a win sets won_cellar_fight.
	var f = _flags(NIGHT_DONE)
	var d = Dialogue.new(f)
	check(d.start("cellar_fight_trigger"), "the trigger's dialogue plays")
	eq(d.line()["text"], "Something's moving behind the shelves.", "its line")
	eq(d.line()["button"], "Fight", "the button says Fight")
	d.advance()
	eq(d.fight_request, {"encounter": "cellar_rats", "win_flags": ["won_cellar_fight"]}, "it asks for cellar_rats")


func test_trigger_spans_the_passage() -> void:
	# The only way from the stairs to the luggage room crosses the trigger.
	var f = _flags(NIGHT_DONE + ["won_cellar_fight"])  # obstacle gone, to test the layout
	var m = TownMap.load_map("cellar", f)
	var cells: Array = TownMap.exit_cells_of(_trigger("cellar", "cellar_fight_trigger"))
	var start := TownMap.cell_of(_play("cellar_hatch", _flags(NIGHT_DONE))[0]["place"])
	for c in cells:
		m.things[c] = "probe"  # block the trigger row
	for id in LUGGAGE:
		check(m.approach_target(start, id).is_empty(), "%s can't be reached without crossing the trigger" % id)


func test_win_returns_to_the_passage_and_sets_the_flag() -> void:
	var s = GameSession.new()
	for n in NIGHT_DONE:
		s.flags.set_flag(n)
	var launch := {"map": "cellar", "cell": Vector2i(4, 3), "facing": "down"}
	s.begin_fight({"encounter": "cellar_rats", "win_flags": ["won_cellar_fight"]}, launch)
	check(s.end_fight(true), "back to the world")
	check(s.flags.has("won_cellar_fight"), "won_cellar_fight is set")
	var r: Dictionary = GameData.encounter("cellar_rats")["return"]["won"]
	eq(s.spot(), {"map": r["map"], "cell": TownMap.cell_of(r["cell"]), "facing": r["facing"]}, "Agador is where the data puts him")
	var m = TownMap.load_map("cellar", s.flags)
	check(m.is_walkable(s.spot()["cell"]), "on a free tile")
	var trig_rows: Array = TownMap.exit_cells_of(_trigger("cellar", "cellar_fight_trigger")).map(func(c): return c.y)
	check(s.spot()["cell"].y >= trig_rows.min(), "in the passage, past the stairs")
	check(m.trigger_at(s.spot()["cell"], s.flags).is_empty(), "no fight starts there")
	for id in LUGGAGE:
		check(not m.approach_target(s.spot()["cell"], id).is_empty(), "%s can be reached after the win" % id)


func test_loss_returns_by_the_stairs_and_allows_a_retry() -> void:
	var s = GameSession.new()
	for n in NIGHT_DONE:
		s.flags.set_flag(n)
	var req := {"encounter": "cellar_rats", "win_flags": ["won_cellar_fight"]}
	s.begin_fight(req, {"map": "cellar", "cell": Vector2i(4, 3), "facing": "down"})
	check(s.end_fight(false), "back to the world after a loss")
	check(not s.flags.has("won_cellar_fight"), "no flag after a loss")
	var spot: Dictionary = s.spot()
	eq(spot["map"], "cellar", "still in the cellar")
	var m = TownMap.load_map("cellar", s.flags)
	check(m.is_walkable(spot["cell"]), "on a free tile")
	check(m.can_use_from("cellar_stairs", spot["cell"]) or BattleState.manhattan(spot["cell"], m.cell_of_thing("cellar_stairs")) <= 2, "near the stairs")
	check(m.trigger_at(spot["cell"], s.flags).is_empty(), "not standing on the trigger")
	# Walking back down the passage crosses the trigger again.
	var cells: Array = TownMap.exit_cells_of(_trigger("cellar", "cellar_fight_trigger"))
	var p: Array = m.find_path(spot["cell"], cells[1])
	check(not p.is_empty(), "the trigger is reachable")
	eq(m.trigger_at(cells[1], s.flags).get("id", ""), "cellar_fight_trigger", "and starts the fight again")
	# Retry and win.
	s.begin_fight(req, {"map": "cellar", "cell": cells[1], "facing": "down"})
	eq(s.encounter_id(), "cellar_rats", "the retry is the same fight")
	s.end_fight(true)
	check(s.flags.has("won_cellar_fight"), "a retry can win")
	# The way out stays open after a loss: the stairs are usable.
	check(not m.approach_target(spot["cell"], "cellar_stairs").is_empty(), "the stairs stay usable after a loss")


func test_obstacle_and_rats_clear_after_a_win() -> void:
	var before = _cellar(NIGHT_DONE)
	var after = _cellar(NIGHT_DONE + ["won_cellar_fight"])
	for id in ["fallen_shelf", "rat_1", "rat_2", "candle_rat"]:
		check(before.things.values().has(id), "%s is there before the win" % id)
		check(not after.things.values().has(id), "%s is gone after the win" % id)
	var door: Vector2i = before.cell_of_thing("fallen_shelf")
	check(not before.is_walkable(door), "the fallen shelf blocks the doorway")
	check(after.is_walkable(door), "the doorway is open afterwards")
	for id in LUGGAGE:
		check(not before.targets.has(id), "%s can't be used before the win" % id)
		check(after.targets.has(id), "%s can be used after the win" % id)
		eq(after.targets[id]["interaction"], id, "%s plays its own dialogue" % id)


func test_luggage_is_easy_to_tell_apart() -> void:
	var shapes := {}
	for id in LUGGAGE:
		var t: Dictionary = _cellar(NIGHT_DONE + ["won_cellar_fight"]).targets[id]["def"]
		shapes[t["shape"]] = true
		check(str(t.get("sprite", "")) != "", "%s has an art key" % id)
	eq(shapes.size(), LUGGAGE.size(), "each piece of luggage has its own look")
	const TownActor = preload("res://scripts/view/town_actor.gd")
	check(TownActor.ANIMATED.has("humming_case"), "the humming case animates")
	check(not TownActor.ANIMATED.has("ribbon_case"), "the ribbon case does not")


# --- Story lines -----------------------------------------------------------------------

func test_luggage_dialogue_and_flags() -> void:
	var f = _flags(NIGHT_DONE + ["won_cellar_fight"])
	eq(_texts("agador_suitcase", f), ["That's my suitcase. I never gave it to anyone.", "'Hold for the Tuesday ferry.' They all say that.", "Received by Dockmaster Pell. Same signature on every tag."], "Agador's suitcase")
	_play("agador_suitcase", f)
	check(f.has("found_pell_name") and not f.has("found_ribbon"), "the suitcase sets found_pell_name only")
	eq(_texts("blank_tags", f), ["Two blank tags, ready to go. Someone's expecting more guests."], "blank tags")
	var before: Array = f.names()
	_play("blank_tags", f)
	eq(f.names(), before, "the tags set nothing")
	eq(_texts("humming_case", f), ["So that's what's humming. A suitcase.", "Locked. Of course it's locked."], "the humming case")
	_play("humming_case", f)
	eq(f.names(), before, "the humming case sets nothing")
	var r = _flags(NIGHT_DONE + ["won_cellar_fight"])
	eq(_texts("ribbon_case", r), ["Eleven years ago. Received by Dockmaster Pell.", "Someone tied a ribbon on this one. I know who should see it."], "the ribbon case")
	_play("ribbon_case", r)
	check(r.has("found_pell_name") and r.has("found_ribbon"), "the ribbon case sets found_pell_name and found_ribbon")


func test_innkeeper_after_the_cellar() -> void:
	eq(_texts("innkeeper", _flags(NIGHT_DONE)), ["I saw the ferry last night.", "The ferry will be back any day now.", "It was here.", "Any day now."], "before the fight: the morning lines")
	eq(_texts("innkeeper", _flags(NIGHT_DONE + ["won_cellar_fight"])), ["Find everything all right, dear? You've got a little rat on you."], "after the win")
	var pell := ["Who's Dockmaster Pell?", "Pell? Oh, you don't want to bother Pell on a Tuesday.", "It's Wednesday.", "Is it?"]
	eq(_texts("innkeeper", _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name"])), pell, "after Pell's name")
	eq(_texts("innkeeper", _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon", "gave_ribbon"])), pell, "still Pell later")


func test_new_guest_and_the_ribbon() -> void:
	eq(_texts("new_guest", _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name"])), ["She loved these things."], "no ribbon yet: the old line")
	var f = _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon"])
	eq(_texts("new_guest", f), ["I found this in the cellar, tied to an old suitcase.", "This was hers. Where did you find it?", "There's a room full of them. Dockmaster Pell signed for every one.", "Then Pell knows where she went."], "showing the ribbon")
	var speakers: Array = Dialogue.select_entry("new_guest", f)["lines"].map(func(l): return l["speaker"])
	eq(speakers, ["agador", "new_guest", "agador", "new_guest"], "Agador and ??? take turns")
	_play("new_guest", f)
	check(f.has("gave_ribbon"), "gave_ribbon is set")
	eq(_texts("new_guest", f), ["The dock office. Someone has to be there."], "afterwards")
	# ??? is beside the arcade, in the lounge, in the morning.
	check(TownMap.load_map("lounge", f).targets.has("new_guest"), "??? is in the lounge")


func test_dock_office_door_lines() -> void:
	eq(_texts("dock_office_door", _flags(NIGHT_DONE)), ["Dock office. Closed until the ferry gets back."], "before Pell's name")
	eq(_texts("dock_office_door", _flags([])), ["Dock office. Closed until the ferry gets back."], "from the start")
	eq(_texts("dock_office_door", _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name"])), ["Locked. There's a light on inside."], "after Pell's name")
	eq(_texts("dock_office_door", _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon"])), ["Locked. There's a light on inside."], "with the ribbon, before ???")
	var f = _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon", "gave_ribbon"])
	eq(_texts("dock_office_door", f), ["Hello? Dockmaster Pell?", "Someone just blew out the lamp."], "after the lead from ???")
	eq(_texts("dock_office_door", _flags(NIGHT_DONE + ["saw_office_light_go_out"])), ["Nobody's home. Very obviously nobody."], "once the light is out")


func test_office_light_fades_out_once() -> void:
	var f = _flags(NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon", "gave_ribbon"])
	var town = TownMap.load_map("town", f)
	check(town.things.values().has("dock_office_light"), "the light is on")
	var d = Dialogue.new(f)
	d.start("dock_office_door")
	check(d.advance(), "a line follows the step")
	var step: Dictionary = d.take_step()
	eq(step.get("fade_out", []), ["dock_office_light"], "the window light fades out between the lines")
	check(not (step.has("card") or step.has("place") or step.has("go_to")), "no screen fade")
	check(f.has("saw_office_light_go_out"), "saw_office_light_go_out is set as it fades")
	eq(d.line()["text"], "Someone just blew out the lamp.", "then the next line")
	d.advance()
	check(not TownMap.load_map("town", f).things.values().has("dock_office_light"), "the light stays out")
	check(_play("dock_office_door", f).is_empty(), "trying again does not fade anything")
	var lit = _flags(NIGHT_DONE + ["found_pell_name"])
	check(TownMap.load_map("town", lit).things.values().has("dock_office_light"), "lit before that")


# --- The dock office in the town ------------------------------------------------------

func test_dock_office_by_the_dock_without_blocking_it() -> void:
	for names in [[], NIGHT_DONE, NIGHT_DONE + ["saw_office_light_go_out"]]:
		var m = TownMap.load_map("town", _flags(names))
		var cells: Array = []
		for c in m.things:
			if str(m.things[c]).begins_with("dock_office"):
				cells.append(c)
		check(cells.size() >= 5, "the office blocks its footprint (%d cells)" % cells.size())
		for c in cells:
			check(m.tile_char(c) != "=", "%s is not on the dock" % str(c))
		var dock: Array = []
		for y in m.size.y:
			for x in m.size.x:
				if m.tile_char(Vector2i(x, y)) == "=":
					dock.append(Vector2i(x, y))
		var near := 99
		for c in cells:
			for dc in dock:
				near = mini(near, BattleState.manhattan(c, dc))
		check(near <= 4, "the office is near the dock (%d tiles)" % near)
		var start: Vector2i = GameSession.start_spot()["cell"]
		check(not m.approach_target(start, "dock_office_door").is_empty(), "its door can be reached from the dock")
		check(not m.approach_target(start, "inn_front_door").is_empty(), "the way from the dock to the inn is open")
		for c in dock:
			if m.is_walkable(c):
				check(not m.find_path(start, c).is_empty() or c == start, "dock tile %s still reachable" % str(c))
	var raw: Dictionary = {}
	for o in TownMap.map_def("town")["objects"]:
		if o["id"] == "dock_office":
			raw = o
	check(raw.has("cell") and raw.has("footprint"), "the office's position and size are data")
	check(not raw.has("interaction"), "the building itself is scenery; the door is the thing to tap")


func test_office_light_is_world_state_with_a_warm_glow() -> void:
	var raw: Dictionary = {}
	for o in TownMap.map_def("town")["objects"]:
		if o["id"] == "dock_office_light":
			raw = o
	check(raw.get("states", []).any(func(s): return s.get("requires", []) == ["saw_office_light_go_out"] and s.get("hidden", false)), "a state hides it once the light goes out")
	eq(raw.get("glow", ""), "office_window", "it glows at night")
	check(GameData.get_json("town")["lighting_presets"]["outdoor"]["night"]["glows"].has("office_window"), "the night preset draws it")


# --- The Cellar test shortcut ---------------------------------------------------------------

func test_cellar_test_shortcut_starts_beside_the_hatch() -> void:
	var all: Array = GameData.setting("shortcuts", [])
	var sc: Dictionary = {}
	for s in all:
		if s.get("label", "") == "Cellar test":
			sc = s
	check(not sc.is_empty(), "the Cellar test shortcut is in settings.json")
	check(bool(sc.get("enabled", false)), "it is switched on for this milestone")
	check(GameSession.shortcuts().has(sc), "so the start screen shows it")
	var s = GameSession.from_shortcut(sc)
	check(s.flags.has("first_night_over"), "the first night is over")
	check(not s.flags.has("won_cellar_fight"), "the cellar fight is still ahead")
	eq(s.flags.time_of_day(), "day", "it is day")
	eq(s.spot()["map"], "town", "in the town")
	var town = TownMap.load_map("town", s.flags)
	check(town.can_use_from("cellar_hatch", s.spot()["cell"]), "beside the hatch")
	check(town.is_walkable(s.spot()["cell"]), "on a free tile")
	eq(s.spot()["facing"], town.facing_to_target(s.spot()["cell"], "cellar_hatch"), "facing it")
	eq(_play("cellar_hatch", s.flags)[0].get("go_to", ""), "cellar", "the hatch opens")
	check(s.fight.is_empty(), "no fight in progress")
	# It is the state the first night leaves behind.
	eq(s.flags.names(), _flags(NIGHT_DONE).names(), "the flags the night leaves")
	# Switched off in data, it disappears.
	sc["enabled"] = false
	check(not GameSession.shortcuts().has(sc), "turned off in data, it is gone")
	sc["enabled"] = true


# --- No softlock ---------------------------------------------------------------------------

func test_no_softlock_in_or_around_the_cellar() -> void:
	# Every story state from the morning on: the cellar and town are reachable,
	# every arrival is free, every target reachable, and the way out works.
	var states := [
		NIGHT_DONE,
		NIGHT_DONE + ["won_cellar_fight"],
		NIGHT_DONE + ["won_cellar_fight", "found_pell_name"],
		NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon"],
		NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon", "gave_ribbon"],
		NIGHT_DONE + ["won_cellar_fight", "found_pell_name", "found_ribbon", "gave_ribbon", "saw_office_light_go_out"],
	]
	for names in states:
		var f = _flags(names)
		var reached: Dictionary = WorldLinks.reachable_maps(f)
		eq(reached.size(), WorldLinks.map_ids().size(), "%s: every map reachable" % str(names.slice(NIGHT_DONE.size())))
		for map_id in ["cellar", "town", "lounge", "lobby"]:
			var m = TownMap.load_map(map_id, f)
			for from in WorldLinks.arrivals(map_id):
				check(m.is_walkable(from), "%s %s: arrival %s free" % [map_id, str(names.slice(NIGHT_DONE.size())), str(from)])
				for tid in m.targets:
					check(not m.approach_target(from, tid).is_empty(), "%s %s: %s reachable from %s" % [map_id, str(names.slice(NIGHT_DONE.size())), tid, str(from)])
		# Revisiting: the hatch always goes down, the stairs always come up.
		eq(_play("cellar_hatch", _flags(names))[0].get("go_to", ""), "cellar", "%s: the hatch goes down" % str(names.slice(NIGHT_DONE.size())))
		check(TownMap.load_map("cellar", f).targets.has("cellar_stairs"), "the stairs lead up")
	# The next step is always somewhere you can go.
	check(TownMap.load_map("cellar", _flags(NIGHT_DONE + ["won_cellar_fight"])).targets.has("ribbon_case"), "the ribbon is there after the win")
	check(TownMap.load_map("lounge", _flags(states[3])).targets.has("new_guest"), "??? is there to see it")
	check(TownMap.load_map("town", _flags(states[4])).targets.has("dock_office_door"), "the dock office door is there")


func test_no_story_ids_in_code() -> void:
	for dir in ["res://scripts/core/", "res://scripts/view/"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + file)
			for word in ["cellar_rats", "won_cellar_fight", "first_night_over", "found_pell_name", "found_ribbon", "gave_ribbon", "saw_office_light", "cellar_fight_trigger", "agador_suitcase", "dock_office_door", "dock_office_light", "Dockmaster", "Pell", "\"cellar\""]:
				check(not src.contains(word), "%s does not mention %s" % [file, word])
