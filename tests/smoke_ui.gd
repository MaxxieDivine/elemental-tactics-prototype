## UI smoke test: loads the real scene and drives the controller through a
## scripted round (move, preview, combo, end turn, undo, restart).
##   godot --headless --path . --script res://tests/smoke_ui.gd
## With a display, pass `-- --shots=<dir>` to save screenshots along the way.
extends SceneTree

var main
var shots_dir := ""
var errors: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		print("  FAIL  " + msg)


func shot(name: String) -> void:
	await process_frame
	await process_frame
	if shots_dir != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func hover(c: Vector2i) -> void:
	main.hover = c
	main._update_hover()


func hero(id: String):
	for u in main.state.units:
		if u.type_id == id:
			return u


func _run() -> void:
	main.board.speed = 8.0
	await shot("01_start")
	check(main.state.living("enemy").size() == 5, "5 enemies at start")
	check(main.board.intents.size() == 5, "every enemy shows an intent")

	# Move Ember up next to the oil.
	var ember = hero("ember")
	main.select(ember.id)
	hover(Vector2i(6, 6))
	check(main.board.path.size() > 1, "move path preview")
	await shot("02_move_preview")
	await main.click(Vector2i(6, 6))
	check(ember.cell == Vector2i(6, 6), "Ember moved")

	# Aim Firebolt at the oil: preview should show IGNITE and BOOM.
	main.select_ability(1)
	check(main.mode == "target", "targeting mode")
	hover(Vector2i(5, 5))
	check(main.board.preview["tags"].has("IGNITE!"), "preview shows ignite")
	check(main.board.preview["tags"].has("BOOM!"), "preview shows barrel chain")
	await shot("03_fire_preview")
	await main.click(Vector2i(5, 5))
	check(ember.acted, "Ember acted")
	check(main.state.get_terrain(Vector2i(4, 4)) == 0, "barrel exploded")
	await shot("04_after_combo")

	# Tide splashes, Volt zaps the puddle (shows lightning preview), then undo.
	var tide = hero("tide")
	main.select(tide.id)
	main.select_ability(1)
	await main.click(Vector2i(3, 6))
	var volt = hero("volt")
	main.select(volt.id)
	await main.click(Vector2i(4, 7))
	main.select_ability(1)
	hover(Vector2i(3, 6))
	await shot("05_zap_preview")
	main.undo()
	check(not volt.moved or main.state.unit_by_id(volt.id).moved == false, "undo restored Volt")

	# Hover an enemy to see its plan, then end the turn.
	for e in main.state.living("enemy"):
		hover(e.cell)
		break
	await shot("06_enemy_hover")
	await main.end_turn()
	check(main.state.round_num == 2 or main.state.phase != "player", "round advanced")
	await shot("07_round2")

	# Restart.
	main.restart()
	check(main.state.round_num == 1 and main.state.living("enemy").size() == 5, "restart resets fight")

	print("\nsmoke: %s" % ("OK" if errors.is_empty() else "%d failures" % errors.size()))
	quit(1 if not errors.is_empty() else 0)
