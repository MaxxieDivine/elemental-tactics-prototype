## World flow smoke test: loads the real app and plays it the way a player
## would on a phone: Town -> into the inn -> lobby, lounge, hallway, Room 1
## -> arcade fight (loss, win, replay) -> back beside the arcade, plus the
## letter changing the innkeeper and the guest book, the locked hatch and
## doors, and the direct Fight option. Run by run_tests.gd.
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
	await talk("welcome_banner", "welcome_banner", 0, "banner")
	check(not box.is_open(), "dialogue closes after the last line")
	await shot("town_02_banner")

	# --- Hatch: locked, humming, no fight --------------------------------------------
	await use("cellar_hatch")
	var hatch: Vector2i = town().map.cell_of_thing("cellar_hatch")
	eq(town().player_cell.y, hatch.y, "Agador stands beside the hatch, not in front of it")
	check(town().actors["cellar_hatch"].is_processing(), "the hatch animates (humming)")
	await shot("town_03_hatch")
	eq(read_dialogue("hatch"), data_lines("cellar_hatch", 0), "hatch line")
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
	await shot("town_04_lobby")
	await talk("innkeeper", "innkeeper", 1, "innkeeper default")
	eq(town().actors["innkeeper"].facing, TownMap.facing_toward(town().map.cell_of_thing("innkeeper"), town().player_cell), "innkeeper turns to face the player")
	await talk("guest_book", "guest_book", 1, "guest book before the letter")
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
	await talk("room_2_door", "room_2_door", 0, "room 2")
	await talk("room_3_door", "room_3_door", 0, "room 3")
	await talk("room_4_door", "room_4_door", 0, "room 4")
	eq(town().map_id, "hallway", "locked doors keep you in the hallway")
	await go("room_1_door")
	await talk("room_1_key", "room_1_key", 0, "room 1 key")
	await talk("room_1_bed", "room_1_bed", 0, "room 1 bed")
	await shot("town_09_room_1")
	await go("room_1_exit")
	await go("stairs_down")
	await go("lobby_front_door")
	eq(town().map_id, "town", "back outside")

	# --- Letter, then the innkeeper and guest book change ------------------------------------
	await talk("letter", "letter", 0, "letter")
	check(app.session.flags.has("read_letter"), "reading the letter sets read_letter")
	await go("inn_front_door")
	await talk("innkeeper", "innkeeper", 0, "innkeeper after the letter")
	await talk("guest_book", "guest_book", 0, "guest book after the letter")

	# --- Menu keeps the place; Town resumes there ---------------------------------------
	var before: Dictionary = town().current_spot()
	town().menu_btn.pressed.emit()
	await frames(3)
	app.screen.town_btn.pressed.emit()
	await fresh_town()
	eq(town().current_spot(), before, "Town resumes where the player left off")

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
