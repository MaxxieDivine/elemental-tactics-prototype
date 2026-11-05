## Town flow smoke test: loads the real app and drives it the way a player
## would on a phone: Town -> talk/read -> cellar door -> fight -> back to
## town (after a loss, then a win), plus the direct Fight option.
## Run by run_tests.gd.
extends "res://tests/test_base.gd"

const GameSession = preload("res://scripts/core/game_session.gd")
const TownMap = preload("res://scripts/core/town_map.gd")

var tree: SceneTree
var app
var shots_dir := ""
var completed := false  # false if the run stopped early on a script error


func frames(n: int = 2) -> void:
	for i in n:
		await tree.process_frame


func shot(name: String) -> void:
	await frames(3)
	if shots_dir != "" and DisplayServer.get_name() != "headless":
		tree.root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func town():
	return app.screen


func town_def() -> Dictionary:
	return GameData.get_json("town")


func thing_cell(id: String) -> Vector2i:
	for t in town_def()["npcs"] + town_def()["objects"]:
		if t["id"] == id:
			return TownMap.cell_of(t["cell"])
	return Vector2i(-1, -1)


func data_lines(id: String, entry: int) -> Array:
	return GameData.get_json("dialogue")[id][entry]["lines"].map(func(l): return l["text"])


## Taps a cell and waits until the player has stopped walking.
func tap_cell(c: Vector2i) -> void:
	town().tap_cell(c)
	var guard := 0
	while not town().is_idle() and guard < 600:
		await frames(1)
		guard += 1


## Reads every line of the open dialogue, tapping like a player:
## first tap finishes the typing, second tap advances.
func read_dialogue(label: String) -> Array:
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
		box.tap()
	return seen


func run(t: SceneTree, shots: String) -> void:
	tree = t
	shots_dir = shots
	GameSession.current = null  # fresh story
	tree.root.size = Vector2i(390, 844)
	app = load("res://scenes/app.tscn").instantiate()
	tree.root.add_child(app)
	await frames(3)

	# --- Start screen ---------------------------------------------------------
	check(app.screen.get("town_btn") != null, "start screen shows first")
	check(app.screen.town_btn.text == "Town" and app.screen.fight_btn.text == "Fight", "Town and Fight buttons")
	await shot("town_00_menu")
	app.screen.town_btn.pressed.emit()
	await frames(3)
	check(town() != null and town().has_method("tap_cell"), "Town opens the town")
	town().step_time = 0.0
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
	check(town().zoom * town().ts * css >= 40.0, "town tiles are big enough to tap")
	check(town().sorted.y_sort_enabled and town().player.get_parent() == town().sorted, "player is depth-sorted with NPCs and objects")
	eq(town().player_cell, TownMap.cell_of(town_def()["player"]["cell"]), "player starts where data says")
	await shot("town_01_start")

	# --- Walk -------------------------------------------------------------------
	var start: Vector2i = town().player_cell
	var dest := start + Vector2i(0, -3)
	await tap_cell(dest)
	eq(town().player_cell, dest, "tap a walkable tile to walk there")
	eq(town().player.facing, "up", "player faces the way it walked")
	await tap_cell(Vector2i(0, town().map.size.y - 1))
	eq(town().player_cell, dest, "tapping water does not move")

	# --- Banner -----------------------------------------------------------------
	await tap_cell(thing_cell("welcome_banner"))
	check(box.is_open(), "tapping the banner walks over and opens dialogue")
	eq((thing_cell("welcome_banner") - town().player_cell).length_squared(), 1, "player stands next to the banner")
	eq(TownMap.facing_toward(town().player_cell, thing_cell("welcome_banner")), town().player.facing, "player faces the banner")
	await shot("town_02_banner")
	eq(read_dialogue("banner"), data_lines("welcome_banner", 0), "banner lines from data")
	check(not box.is_open(), "dialogue closes after the last line")

	# Taps on the map are ignored while a dialogue is open.
	await tap_cell(thing_cell("innkeeper"))
	check(box.is_open(), "innkeeper dialogue opens")
	var here: Vector2i = town().player_cell
	town().tap_cell(here + Vector2i(1, 0))
	eq(town().path, [], "map taps are ignored during dialogue")
	await shot("town_03_innkeeper")
	eq(read_dialogue("innkeeper"), data_lines("innkeeper", 1), "default innkeeper dialogue")
	eq(town().actors["innkeeper"].facing, TownMap.facing_toward(thing_cell("innkeeper"), town().player_cell), "innkeeper turns to face the player")

	# --- Letter, then the innkeeper changes --------------------------------------
	await tap_cell(thing_cell("letter"))
	eq(read_dialogue("letter"), data_lines("letter", 0), "letter lines")
	check(app.session.flags.has("read_letter"), "reading the letter sets read_letter")
	await tap_cell(thing_cell("innkeeper"))
	eq(read_dialogue("innkeeper after letter"), data_lines("innkeeper", 0), "innkeeper dialogue changes after the letter")

	# --- Cellar door -> fight -> lose -> back ----------------------------------
	await tap_cell(thing_cell("cellar_door"))
	var spot: Vector2i = town().player_cell
	eq(read_dialogue("cellar"), data_lines("cellar_door", 1), "cellar door before the fight")
	await frames(3)
	var fight = app.screen
	check(fight.get("encounter_id") == "first_fight", "cellar door opens the fight with encounter first_fight")
	check(fight.from_town, "fight knows it came from town")
	var names: Array = fight.state.units.filter(func(u): return u.team == "hero").map(func(u): return u.name)
	eq(names, ["tide", "volt", "ember"].map(func(id): return GameData.hero(id)["name"]), "existing heroes with names from data")
	await shot("town_04_fight")
	fight.state.phase = "lost"
	fight._after_action()
	check(fight.hud.over_layer.visible, "defeat screen shows")
	eq(fight.hud.over_btn.text, "Back to town", "end button returns to town")
	check(not fight.hud.menu_btn.visible, "no Menu button on a town fight")
	fight.hud.over_btn.pressed.emit()
	await frames(3)
	check(town() != null and town().has_method("tap_cell"), "back in town after a loss")
	town().step_time = 0.0
	eq(town().player_cell, spot, "player is where they left off")
	check(not app.session.flags.has("won_first_fight"), "a loss does not set won_first_fight")

	# --- Try again and win ------------------------------------------------------
	await tap_cell(thing_cell("cellar_door"))
	eq(read_dialogue("cellar retry"), data_lines("cellar_door", 1), "cellar door still hums after a loss")
	await frames(3)
	fight = app.screen
	for e in fight.state.living("enemy"):
		e.hp = 0
		e.alive = false
	fight.state.phase = "won"
	fight._after_action()
	fight.hud.over_btn.pressed.emit()
	await frames(3)
	town().step_time = 0.0
	check(app.session.flags.has("won_first_fight"), "a win sets won_first_fight")
	eq(town().player_cell, spot, "player is where they left off after a win")
	await tap_cell(thing_cell("cellar_door"))
	eq(read_dialogue("cellar after win"), data_lines("cellar_door", 0), "cellar door line changes after the win")
	check(app.screen.has_method("tap_cell"), "no second fight after the win")
	await shot("town_05_after_win")

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
