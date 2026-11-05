## World flow smoke test: loads the real app and plays it the way a player
## would on a phone: Town -> into the inn -> lobby, lounge, hallway, Room 1
## -> arcade fight (loss, win, replay) -> back beside the arcade, plus the
## letter changing the innkeeper and the guest book, the locked hatch and
## doors, the Room 1 key bringing the new guest into the lobby, their scene,
## the inn changing afterwards, the first night (sleep, a card, the inn and
## town at night, the arcade at night, the dock trigger and the ferry, the
## night letter, sleep again, morning), and the direct Fight option. Run by
## run_tests.gd.
extends "res://tests/test_base.gd"

const GameSession = preload("res://scripts/core/game_session.gd")
const TownMap = preload("res://scripts/core/town_map.gd")

var tree: SceneTree
var app
var shots_dir := ""
var completed := false  # false if the run stopped early on a script error
var max_fade := 0.0  # highest fade alpha seen while walking (proves the fade ran)


func frames(n: int = 2) -> void:
	for i in n:
		await tree.process_frame


func shot(name: String) -> void:
	await frames(3)
	if shots_dir != "" and DisplayServer.get_name() != "headless":
		tree.root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func town():
	return app.screen


func data_lines(id: String, entry: int) -> Array:
	return GameData.get_json("dialogue")[id][entry]["lines"].map(func(l): return l["text"])


## Fast walking for the test (the fade keeps its data time).
func fresh_town() -> void:
	await frames(3)
	check(town() != null and town().has_method("tap_cell"), "town screen is showing")
	town().step_time = 0.0


## Taps a cell and waits until the player has stopped walking and any map
## change has finished.
func tap_cell(c: Vector2i) -> void:
	town().tap_cell(c)
	max_fade = 0.0
	var guard := 0
	while not town().is_idle() and guard < 900:
		await frames(1)
		max_fade = maxf(max_fade, town().fade.color.a)
		guard += 1


## Taps a thing (NPC, object or exit) by id on the current map.
func use(id: String) -> void:
	check(town().map.targets.has(id), "%s is on map %s" % [id, town().map_id])
	await tap_cell(town().map.cell_of_thing(id))


## Goes through an exit and checks the arrival against its data.
func go(exit_id: String) -> void:
	var exit: Dictionary = town().map.exit_def(exit_id)
	check(not exit.is_empty(), "exit %s on map %s" % [exit_id, town().map_id])
	var flags_before: Array = app.session.flags.names()
	await use(exit_id)
	var a := TownMap.arrival(exit)
	eq(town().map_id, a["map"], "%s leads to %s" % [exit_id, a["map"]])
	eq(town().player_cell, a["cell"], "%s: arrival cell from data" % exit_id)
	eq(town().player.facing, a["facing"], "%s: arrival facing from data" % exit_id)
	check(max_fade > 0.9, "%s: the screen faded during the change" % exit_id)
	eq(town().fade.color.a, 0.0, "%s: fade cleared afterwards" % exit_id)
	eq(app.session.flags.names(), flags_before, "%s: story flags unchanged by the map change" % exit_id)
	eq(app.session.spot()["map"], a["map"], "%s: session knows the current map" % exit_id)


## Reads every line of the open dialogue, tapping like a player:
## first tap finishes the typing, second tap advances. Returns the texts;
## `buttons` collects each line's button label once typing is done.
func read_dialogue(label: String, buttons: Array = []) -> Array:
	var box = town().dialogue_box
	var seen: Array = []
	var guard := 0
	while box.is_open() and guard < 30:
		guard += 1
		var line: String = box.text.text
		seen.append(line)
		check(box.is_typing(), "%s: line '%s' types out over time" % [label, line.left(20)])
		box.tap()
		check(box.is_open() and not box.is_typing() and box.text.text == line, "%s: first tap completes the line" % label)
		buttons.append(box.next_btn.text)
		box.tap()
	return seen


## Uses something and checks its dialogue against data entry `entry`.
func talk(id: String, interaction: String, entry: int, label: String) -> Array:
	await use(id)
	check(town().dialogue_box.is_open(), "%s: dialogue opens" % label)
	check(town().map.can_use_from(id, town().player_cell), "%s: player stands where it can be used" % label)
	eq(town().player.facing, town().map.facing_to_target(town().player_cell, id), "%s: player faces it" % label)
	var buttons: Array = []
	eq(read_dialogue(label, buttons), data_lines(interaction, entry), "%s: lines from data" % label)
	return buttons


## From the arcade's dialogue into the fight; returns the fight screen.
func arcade_to_fight(entry: int, label: String) -> Variant:
	var buttons: Array = await talk("arcade", "arcade", entry, label)
	eq(buttons[-1], "Insert coin", "%s: last button says Insert coin" % label)
	for i in buttons.size() - 1:
		eq(buttons[i], "Next", "%s: other lines use the default Next" % label)
	await frames(3)
	var fight = app.screen
	check(fight.get("encounter_id") == "first_fight", "%s: Insert coin starts first_fight" % label)
	check(fight.get("from_town") == true, "%s: fight knows it came from the world" % label)
	return fight


## Back in the lobby after the Room 1 key: ??? paces in front of the desk,
## upset, and never steps onto the player or the player's path.
func check_guest_pacing() -> void:
	eq(town().map_id, "lobby", "in the lobby")
	check(town().actors.has("new_guest"), "??? appears in the lobby after the Room 1 key")
	if not town().actors.has("new_guest"):
		return
	check(town().actors["new_guest"].shows_mood(), "??? shows the upset mark")
	check(town().actors["new_guest"].is_processing(), "the upset mark animates")
	check(town().pacing.has("new_guest"), "??? is pacing")
	var pacer = town().map.pacers["new_guest"]
	town().pacing["new_guest"]["dur"] = 0.01  # fast pacing for the test
	town().pacing["new_guest"]["wait"] = 0.01
	var seen := {pacer.cell: true}
	var guard := 0
	while seen.size() < pacer.route.size() and guard < 600:
		await frames(1)
		seen[pacer.cell] = true
		check(pacer.cell != town().player_cell, "??? never steps onto Agador")
		guard += 1
	eq(seen.size(), pacer.route.size(), "??? paces the whole data route")
	var lobby_def: Dictionary = TownMap.map_def("lobby")["npcs"].filter(func(n): return n["id"] == "new_guest")[0]
	var route: Array = lobby_def["states"].filter(func(s): return s.has("pace"))[0]["pace"]
	check(seen.has(TownMap.cell_of(route[0])) and seen.has(TownMap.cell_of(route[-1])), "route between the data points")


## Taps ??? in the lobby and plays the whole conversation like a player.
func guest_scene() -> void:
	eq(town().map_id, "lobby", "the scene is in the lobby")
	var guest = town().actors["new_guest"]
	await use("new_guest")
	var box = town().dialogue_box
	check(box.is_open(), "tapping ??? starts the conversation")
	check(town().map.can_use_from("new_guest", town().player_cell), "Agador stands next to ???")
	var held: Vector2i = town().map.cell_of_thing("new_guest")
	var held_pos: Vector2 = guest.position
	var speakers: Array = []
	var names: Array = []
	var texts: Array = []
	var guard := 0
	while box.is_open() and guard < 30:
		guard += 1
		speakers.append(box.runner.line()["speaker"])
		names.append(box.name_label.text)
		texts.append(box.text.text)
		if guard == 1:
			eq(box.portrait_initial.text, "???", "??? placeholder portrait shows ???")
			check(box.portrait_box.visible and not box.portrait_tex.visible, "placeholder portrait while there is no art")
			eq(box.portrait_box.color, Color(GameData.get_json("characters")["new_guest"]["color"]), "placeholder in ???'s colour")
			box.tap()  # finish typing for the screenshot
			await shot("town_10b_guest_talk")
			box.tap()
			continue
		await frames(5)
		eq(town().map.cell_of_thing("new_guest"), held, "??? stops pacing during the conversation")
		check(not app.session.flags.has("met_new_guest") or not box.is_open(), "met_new_guest is only set at the end")
		box.tap()
		box.tap()
	var entry: Dictionary = GameData.get_json("dialogue")["new_guest"][4]
	eq(texts, entry["lines"].map(func(l): return l["text"]), "the full lobby conversation, from data")
	eq(speakers, entry["lines"].map(func(l): return l["speaker"]), "three speakers take turns")
	eq(names[0], GameData.get_json("characters")["new_guest"]["name"], "??? display name from data")
	check(guest.position.distance_to(held_pos) < 16.0, "??? stayed put while talking")
	check(app.session.flags.has("met_new_guest"), "the conversation sets met_new_guest")
	# The inn changes behind a short fade.
	var peak := 0.0
	guard = 0
	while (town().transitioning or guard == 0) and guard < 600:
		await frames(1)
		peak = maxf(peak, town().fade.color.a)
		guard += 1
	check(peak > 0.9, "the screen fades as ??? leaves")
	eq(town().fade.color.a, 0.0, "fade cleared after the scene")
	check(not town().actors.has("new_guest") and not town().map.targets.has("new_guest"), "??? has left the lobby")
	check(town().actors.has("innkeeper"), "the innkeeper stays in the lobby")
	eq(app.session.spot()["map"], "lobby", "Agador is still in the lobby")
	await shot("town_11_after_scene")


## Waits while a dialogue step (fade, card, object fade) plays. Returns
## {"peak": highest screen fade, "card": card text seen ("" if none)}.
func wait_step(skip_card: bool = false) -> Dictionary:
	var box = town().dialogue_box
	var out := {"peak": 0.0, "card": ""}
	var guard := 0
	while box.busy and guard < 2000:
		await frames(1)
		out["peak"] = maxf(out["peak"], town().fade.color.a)
		if town().card_showing():
			if out["card"] == "":
				await shot("town_night_card_" + town().card.text.to_lower().replace(" ", "_"))
			out["card"] = town().card.text
			if skip_card:
				var tap := InputEventMouseButton.new()
				tap.button_index = MOUSE_BUTTON_LEFT
				tap.pressed = false
				town().card_catch.gui_input.emit(tap)  # a tap skips the card
		guard += 1
	check(not box.busy, "the step finished")
	return out


## Uses the Room 1 bed and sleeps: the line's button says Sleep, the screen
## fades, a card shows, and the next line starts at the data's place.
func sleep_in_bed(entry: int, card_text: String, time_after: String, flag: String, skip_card: bool) -> void:
	var lines: Array = GameData.get_json("dialogue")["room_1_bed"][entry]["lines"]
	await use("room_1_bed")
	var box = town().dialogue_box
	check(box.is_open(), "the bed starts its dialogue")
	eq(box.text.text, lines[0]["text"], "bed line before sleeping")
	box.tap()
	eq(box.next_btn.text, "Sleep", "the button says Sleep")
	check(not app.session.flags.has(flag), "%s not set before sleeping" % flag)
	box.tap()
	check(box.busy and town().transitioning, "sleeping starts a step")
	box.tap()  # taps during the step are ignored
	town().tap_cell(town().player_cell + Vector2i(0, 1))
	eq(town().path, [], "map taps are ignored during the step")
	var seen: Dictionary = await wait_step(skip_card)
	check(seen["peak"] > 0.9, "the screen fades out to sleep")
	eq(seen["card"], card_text, "the transition card shows its data text")
	check(not town().card_showing(), "the card is gone afterwards")
	eq(town().fade.color.a, 0.0, "the fade clears")
	eq(app.session.flags.time_of_day(), time_after, "time of day after sleeping")
	check(app.session.flags.has(flag), "sleeping sets %s" % flag)
	eq(town().time_of_day, time_after, "the room is rebuilt for the new time")
	var step: Dictionary = lines[0]["then"]
	eq(town().player_cell, TownMap.cell_of(step["place"]), "Agador wakes where the data places him")
	eq(town().player.facing, step["facing"], "facing from data")
	check(box.is_open(), "the dialogue carries on after the step")
	eq(box.text.text, lines[1]["text"], "the line after waking")
	read_dialogue("wake up")
	check(not box.is_open(), "the bed dialogue closes")


func night_lighting(label: String, outdoor: bool) -> void:
	var g: Color = town().ground.modulate
	check(g != Color.WHITE, "%s: the ground is tinted at night" % label)
	check(town().player.modulate.get_luminance() > g.get_luminance(), "%s: Agador stays brighter than the ground" % label)
	if outdoor:
		check(g.get_luminance() < 0.5, "%s: outdoors is clearly dark" % label)
		check(town().lighting.count("add") >= 4, "%s: warm pools at lamps, windows and the door" % label)
	else:
		check(g.get_luminance() > 0.7, "%s: the inn is only slightly dimmer" % label)
		check(town().lighting.count() >= 1, "%s: lanterns glow" % label)
		if town().map.rows.any(func(r): return r.contains("n")):
			check(town().lighting.count("mix") >= 1, "%s: dark window panes" % label)


func day_lighting(label: String) -> void:
	eq(town().ground.modulate, Color.WHITE, "%s: day lighting has no tint" % label)
	eq(town().lighting.count(), 0, "%s: no light pools in the day" % label)


## The first night, from the Room 1 bed to the next morning.
func first_night() -> void:
	await go("stairs_up")
	await go("room_1_door")
	day_lighting("Room 1 before the night")
	town().card_time = 0.4
	await sleep_in_bed(2, "Later that night", "night", "first_night_started", false)
	night_lighting("Room 1", false)
	await shot("town_13_room_1_night")
	await talk("room_1_bed", "room_1_bed", 1, "bed before the letter")
	check(app.session.flags.time_of_day() == "night", "the bed will not sleep yet")

	await go("room_1_exit")
	night_lighting("hallway", false)
	await go("stairs_down")
	check(not town().actors.has("innkeeper") and not town().map.targets.has("innkeeper"), "the innkeeper is away at night")
	await shot("town_14_lobby_night")
	await go("lounge_doorway")
	check(town().actors.has("new_guest"), "??? stays beside the arcade at night")
	await talk("new_guest", "new_guest", 2, "??? at night")

	# The arcade works at night and brings you back to the night.
	var spot: Dictionary = app.session.spot()
	var fight = await arcade_to_fight(0, "arcade at night")
	eq(app.session.flags.time_of_day(), "night", "night during the fight")
	await finish_fight(fight, false)
	eq(town().map_id, "lounge", "back in the lounge after a night fight")
	eq(town().time_of_day, "night", "the lounge is still at night after the fight")
	night_lighting("lounge after the fight", false)
	check(town().actors.has("new_guest"), "??? is still there after the fight")
	fight = await arcade_to_fight(0, "arcade at night, win")
	await finish_fight(fight, true)
	eq(app.session.flags.time_of_day(), "night", "a won fight keeps the night")

	await go("lobby_doorway")
	await go("lobby_front_door")
	eq(town().map_id, "town", "the front door still leads outside at night")
	night_lighting("town", true)
	check(town().actors.has("ferry_silhouette"), "the ferry is offshore")
	check(not town().map.targets.has("ferry_silhouette"), "the ferry is scenery, not a tap target")
	check(not town().actors.has("letter") and not town().actors.has("night_letter"), "no letter on the dock yet")
	await shot("town_15_town_night")
	await talk("welcome_banner", "welcome_banner", 0, "banner at night")
	await talk("cellar_hatch", "cellar_hatch", 2, "hatch at night")

	# The end of the dock.
	var trig: Dictionary = town().map.triggers[0]
	var trig_cells: Array = TownMap.exit_cells_of(trig)
	var flags_before: int = app.session.flags.names().size()
	await tap_cell(Vector2i(6, 16))
	var box = town().dialogue_box
	check(box.is_open(), "walking onto the end of the dock starts the trigger")
	check(trig_cells.has(town().player_cell), "Agador stops on the first trigger cell")
	eq(town().path, [], "the walk stops at the trigger")
	eq(town().player.facing, trig["facing"], "Agador turns toward the water")
	check(app.session.flags.has_run(trig["id"]), "the trigger is remembered as run")
	await frames(40)  # let the camera settle above the box
	await shot("town_16_ferry")
	var lines: Array = GameData.get_json("dialogue")[trig["interaction"]][0]["lines"]
	eq(box.text.text, lines[0]["text"], "first dock line")
	box.tap()
	box.tap()
	check(box.busy, "the ferry starts fading")
	var mid := 0
	while box.busy and mid < 2000:
		await frames(1)
		if town().actors.has("ferry_silhouette"):
			check(town().fade.color.a < 0.01, "the screen does not fade while the ferry does")
		mid += 1
	check(not town().actors.has("ferry_silhouette"), "the ferry is gone")
	check(app.session.flags.has("saw_ferry"), "saw_ferry is set")
	check(town().actors.has("night_letter"), "the new letter is on the dock")
	eq(town().actors.get("night_letter").modulate.a if town().actors.has("night_letter") else 0.0, 1.0, "the letter has faded in")
	eq(town().map.cell_of_thing("night_letter"), TownMap.cell_of(_raw_cell("town", "letter")), "in the old letter's spot")
	eq(box.text.text, lines[1]["text"], "second dock line")
	read_dialogue("dock")
	await shot("town_17_night_letter")
	check(app.session.flags.names().size() == flags_before + 1, "the dock adds only saw_ferry")

	# Walking off and back on does not run it again.
	await tap_cell(Vector2i(6, 13))
	await tap_cell(trig_cells[0])
	check(not box.is_open(), "the trigger runs only once")
	await talk("night_letter", "night_letter", 0, "night letter")
	check(app.session.flags.has("read_night_letter"), "reading it sets read_night_letter")

	# Back to bed; the morning.
	await go("inn_front_door")
	await go("stairs_up")
	await go("room_1_door")
	await sleep_in_bed(0, "The next morning", "day", "first_night_over", true)
	day_lighting("Room 1 in the morning")
	await shot("town_18_morning")
	await talk("room_1_bed", "room_1_bed", 3, "bed in the morning")
	await go("room_1_exit")
	await go("stairs_down")
	check(town().actors.has("innkeeper"), "the innkeeper is back in the morning")
	await talk("innkeeper", "innkeeper", 2, "innkeeper in the morning")
	await go("lobby_front_door")
	day_lighting("town in the morning")
	check(town().actors.has("letter"), "the old letter is back")
	check(not town().actors.has("night_letter") and not town().actors.has("ferry_silhouette"), "no ferry or night letter in the morning")
	await talk("welcome_banner", "welcome_banner", 1, "banner in the morning")
	await shot("town_19_town_morning")


func _raw_cell(map_id: String, thing_id: String) -> Array:
	for t in TownMap.map_def(map_id)["objects"]:
		if t["id"] == thing_id:
			return t["cell"]
	return [-1, -1]


func finish_fight(fight, won: bool) -> void:
	if won:
		for e in fight.state.living("enemy"):
			e.hp = 0
			e.alive = false
	fight.state.phase = "won" if won else "lost"
	fight._after_action()
	check(fight.hud.over_layer.visible, "end screen shows")
	eq(fight.hud.over_btn.text, "Back to town", "end button returns to the world")
	check(not fight.hud.menu_btn.visible, "no Menu button on a world fight")
	fight.hud.over_btn.pressed.emit()
	await fresh_town()


func run(t: SceneTree, shots: String) -> void:
	tree = t
	shots_dir = shots
	GameSession.current = null  # fresh story
	tree.root.size = Vector2i(390, 844)
	app = load("res://scenes/app.tscn").instantiate()
	tree.root.add_child(app)
	await frames(3)

	# --- Start screen -----------------------------------------------------------
	check(app.screen.get("town_btn") != null, "start screen shows first")
	check(app.screen.town_btn.text == "Town" and app.screen.fight_btn.text == "Fight", "Town and Fight buttons")
	await shot("town_00_menu")
	app.screen.town_btn.pressed.emit()
	await fresh_town()
	town().relayout()
	await frames(2)

	# Phone layout: touch targets and dialogue box on screen.
	var m: Dictionary = town()._metrics
	var css: float = m["css_per_unit"]
	var view: Vector2 = m["size"]
	check(town().menu_btn.size.y * css >= 47.9, "town Menu button >= 48 CSS px")
	var box = town().dialogue_box
	check(box.next_btn.size.y * css >= 47.9 and box.next_btn.size.x * css >= 47.9, "dialogue advance button >= 48 CSS px")
	var pr: Rect2 = box.panel.get_global_rect()
	check(pr.position.x >= 0 and pr.end.x <= view.x + 0.5 and pr.end.y <= view.y + 0.5, "dialogue box on screen")
	check(town().zoom * town().ts * css >= 40.0, "tiles are big enough to tap")
	check(town().sorted.y_sort_enabled and town().player.get_parent() == town().sorted, "player is depth-sorted with NPCs and objects")
	var start := GameSession.start_spot()
	eq(town().map_id, start["map"], "play starts on the data start map")
	eq(town().player_cell, start["cell"], "player starts where data says")
	await shot("town_01_start")

	# --- Walk -------------------------------------------------------------------
	var dest: Vector2i = town().player_cell + Vector2i(0, -3)
	await tap_cell(dest)
	eq(town().player_cell, dest, "tap a walkable tile to walk there")
	eq(town().player.facing, "up", "player faces the way it walked")
	await tap_cell(Vector2i(0, town().map.size.y - 1))
	eq(town().player_cell, dest, "tapping water does not move")

	# --- Banner -------------------------------------------------------------------
	await talk("welcome_banner", "welcome_banner", 1, "banner")
	check(not box.is_open(), "dialogue closes after the last line")
	await shot("town_02_banner")

	# --- Hatch: locked, humming, no fight --------------------------------------------
	await use("cellar_hatch")
	var hatch: Vector2i = town().map.cell_of_thing("cellar_hatch")
	eq(town().player_cell.y, hatch.y, "Agador stands beside the hatch, not in front of it")
	check(town().actors["cellar_hatch"].is_processing(), "the hatch animates (humming)")
	await shot("town_03_hatch")
	eq(read_dialogue("hatch"), data_lines("cellar_hatch", 3), "hatch line")
	await frames(3)
	check(town() != null and town().has_method("tap_cell"), "the hatch does not start a fight")
	# Taps on the map are ignored while a dialogue is open.
	town().interact("cellar_hatch")
	var here: Vector2i = town().player_cell
	town().tap_cell(here + Vector2i(0, 1))
	eq(town().path, [], "map taps are ignored during dialogue")
	read_dialogue("hatch again")

	# --- Into the inn ----------------------------------------------------------------
	await go("inn_front_door")
	eq(town().map_id, "lobby", "the inn door leads into the lobby")
	check(not town().actors.has("new_guest") and not town().map.targets.has("new_guest"), "??? is not in the lobby before the Room 1 key")
	await shot("town_04_lobby")
	await talk("innkeeper", "innkeeper", 5, "innkeeper default")
	eq(town().actors["innkeeper"].facing, TownMap.facing_toward(town().map.cell_of_thing("innkeeper"), town().player_cell), "innkeeper turns to face the player")
	await talk("guest_book", "guest_book", 2, "guest book before the letter")
	await talk("key_board", "key_board", 0, "key board")

	# --- Lounge: fireplace and the arcade ---------------------------------------------
	await go("lounge_doorway")
	await talk("fireplace", "fireplace", 0, "fireplace")
	check(town().actors["arcade"].is_processing(), "the arcade screen animates")
	await use("arcade")
	await shot("town_05_arcade")
	read_dialogue("arcade first look")
	await frames(3)
	var fight = app.screen
	check(fight.get("encounter_id") == "first_fight", "arcade starts first_fight")
	var names: Array = fight.state.units.filter(func(u): return u.team == "hero").map(func(u): return u.name)
	eq(names, ["tide", "volt", "ember"].map(func(id): return GameData.hero(id)["name"]), "existing heroes with names from data")
	await shot("town_06_fight")
	var spot: Dictionary = app.session.spot()
	eq(spot["map"], "lounge", "fight remembers the lounge")
	check(TownMap.load_map("lounge").can_use_from("arcade", spot["cell"]), "fight remembers a spot beside the arcade")

	# Lose: back beside the arcade, no flag.
	await finish_fight(fight, false)
	eq(town().map_id, "lounge", "back in the lounge after a loss")
	eq(town().player_cell, spot["cell"], "back beside the arcade after a loss")
	eq(town().player.facing, spot["facing"], "facing the arcade again")
	check(not app.session.flags.has("won_first_fight"), "a loss does not set won_first_fight")

	# Try again and win.
	fight = await arcade_to_fight(1, "arcade retry")
	await finish_fight(fight, true)
	check(app.session.flags.has("won_first_fight"), "a win sets won_first_fight")
	eq(town().map_id, "lounge", "back in the lounge after a win")
	eq(town().player_cell, spot["cell"], "back beside the arcade after a win")

	# High score, and the fight replays.
	fight = await arcade_to_fight(0, "arcade high score")
	await finish_fight(fight, false)
	check(app.session.flags.has("won_first_fight"), "losing a replay keeps won_first_fight")
	eq(town().player_cell, spot["cell"], "back beside the arcade after the replay")
	await shot("town_07_after_fights")

	# --- Upstairs ------------------------------------------------------------------------
	await go("lobby_doorway")
	await go("stairs_up")
	await shot("town_08_hallway")
	await talk("room_2_door", "room_2_door", 1, "room 2")
	await talk("room_3_door", "room_3_door", 0, "room 3")
	await talk("room_4_door", "room_4_door", 0, "room 4")
	eq(town().map_id, "hallway", "locked doors keep you in the hallway")
	await go("room_1_door")
	await talk("room_1_key", "room_1_key", 0, "room 1 key")
	await talk("room_1_bed", "room_1_bed", 3, "room 1 bed")
	await shot("town_09_room_1")
	check(app.session.flags.has("found_room_key"), "the Room 1 key sets found_room_key")
	await go("room_1_exit")
	await go("stairs_down")
	await check_guest_pacing()
	await shot("town_10_new_guest")
	await go("lobby_front_door")
	eq(town().map_id, "town", "back outside")

	# --- Letter, then the innkeeper and guest book change ------------------------------------
	await talk("letter", "letter", 0, "letter")
	check(app.session.flags.has("read_letter"), "reading the letter sets read_letter")
	await go("inn_front_door")
	await talk("innkeeper", "innkeeper", 4, "innkeeper after the letter")
	await talk("guest_book", "guest_book", 1, "guest book after the letter")
	check(town().actors.has("new_guest") and not town().pacing.is_empty(), "??? is still pacing after Agador walked around them")

	# --- The second guest's scene ----------------------------------------------------------
	await guest_scene()
	await talk("innkeeper", "innkeeper", 3, "innkeeper after the scene")
	await talk("guest_book", "guest_book", 0, "guest book after the scene")
	await talk("key_board", "key_board", 0, "key board unchanged after the scene")
	await go("lounge_doorway")
	var lounge_def: Dictionary = TownMap.map_def("lounge")["npcs"].filter(func(n): return n["id"] == "new_guest")[0]
	eq(town().map.cell_of_thing("new_guest"), TownMap.cell_of(lounge_def["cell"]), "??? waits in the lounge at the data cell")
	check(not town().actors["new_guest"].shows_mood(), "no upset mark in the lounge")
	check(town().pacing.is_empty() and town().map.pacers.is_empty(), "??? no longer paces")
	check(not town().map.targets["arcade"]["stand"].has(town().map.cell_of_thing("new_guest")), "??? does not stand where the arcade is used from")
	await shot("town_12_lounge_guest")
	await talk("new_guest", "new_guest", 3, "??? at the arcade")
	await talk("fireplace", "fireplace", 0, "fireplace unchanged after the scene")
	fight = await arcade_to_fight(0, "arcade after the scene")
	await finish_fight(fight, true)
	eq(town().map_id, "lounge", "back in the lounge after the arcade")
	check(town().actors.has("new_guest"), "??? is still beside the arcade after a fight")
	await go("lobby_doorway")
	check(not town().actors.has("new_guest"), "??? is gone from the lobby")
	await go("stairs_up")
	eq(town().actors["room_2_door"].shape, "door_name", "Room 2's Reserved card is replaced (world state)")
	await talk("room_2_door", "room_2_door", 0, "room 2 after the scene")
	await talk("room_3_door", "room_3_door", 0, "room 3 unchanged after the scene")
	await talk("room_4_door", "room_4_door", 0, "room 4 unchanged after the scene")
	await go("stairs_down")

	# --- Menu keeps the place; Town resumes there ---------------------------------------
	var before: Dictionary = town().current_spot()
	town().menu_btn.pressed.emit()
	await frames(3)
	app.screen.town_btn.pressed.emit()
	await fresh_town()
	eq(town().current_spot(), before, "Town resumes where the player left off")

	# --- The first night ---------------------------------------------------------------
	await first_night()

	# --- Long text fits the phone box -------------------------------------------
	var longest := ""
	for id in GameData.get_json("dialogue"):
		if id.begins_with("_"):
			continue
		for e in GameData.get_json("dialogue")[id]:
			for l in e["lines"]:
				if l["text"].length() > longest.length():
					longest = l["text"]
	tree.root.size = Vector2i(360, 640)
	await frames(3)
	town().relayout()
	await frames(2)
	box = town().dialogue_box
	town().interact("innkeeper")
	box.text.text = longest
	box.text.visible_characters = -1
	await frames(3)
	check(box.text.get_content_height() <= box.text.size.y + 1.0, "longest data line fits the box on a small phone")
	box.text.text = "A much longer line. ".repeat(20)
	await frames(3)
	check(box.text.get_global_rect().end.y <= box.panel.get_global_rect().end.y + 0.5, "very long text stays inside the box (scrolls)")
	while box.is_open():
		box.tap()

	# --- Menu -> direct Fight still works ---------------------------------------
	town().menu_btn.pressed.emit()
	await frames(3)
	app.screen.fight_btn.pressed.emit()
	await frames(3)
	fight = app.screen
	check(fight.get("from_town") == false, "direct Fight opens the fight on its own")
	eq(fight.state.living("enemy").size(), GameData.encounter()["enemies"].size(), "direct fight has the full encounter")
	fight.state.phase = "won"
	fight._after_action()
	eq(fight.hud.over_btn.text, "Play again", "direct fight keeps Play again")
	check(fight.hud.menu_btn.visible, "direct fight offers Menu")
	fight.hud.over_btn.pressed.emit()
	eq(fight.state.phase, "player", "Play again restarts the direct fight")
	fight.hud.menu_btn.pressed.emit()
	await frames(3)
	check(app.screen.get("town_btn") != null, "Menu returns to the start screen")

	app.queue_free()
	await frames()
	completed = true
