## UI smoke test: loads the real scene and drives it with the same taps a
## player would make (tap to select, tap again to confirm), in a portrait
## phone layout and a landscape desktop layout. Run by run_tests.gd.
extends "res://tests/test_base.gd"

const NO := Vector2i(-1, -1)

var tree: SceneTree
var main
var shots_dir := ""
var completed := false  # false if the run stopped early on a script error


func frames(n: int = 2) -> void:
	for i in n:
		await tree.process_frame


func shot(name: String) -> void:
	await frames()
	if shots_dir != "" and DisplayServer.get_name() != "headless":
		tree.root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func tap(c: Vector2i) -> void:
	await main.on_tap(c)


func hero_u(id: String):
	for u in main.state.units:
		if u.type_id == id:
			return u


func set_window(size: Vector2i) -> void:
	tree.root.size = size
	await frames(3)
	main.hud.relayout()
	await frames(2)


func check_layout(label: String) -> void:
	var hud = main.hud
	var view: Vector2 = hud.metrics["size"]
	var css: float = hud.metrics["css_per_unit"]
	for b in hud.hero_btns + hud.ability_btns + [hud.wait_btn, hud.undo_btn, hud.cancel_btn, hud.info_btn, hud.end_btn, hud.restart_btn, hud.speed_btn]:
		check(b.size.y * css >= 47.9, "%s: button '%s' is at least 48 CSS px tall" % [label, b.text.split("\n")[0]])
		var r: Rect2 = b.get_global_rect()
		check(r.position.x >= -0.5 and r.end.x <= view.x + 0.5 and r.end.y <= view.y + 0.5, "%s: button '%s' on screen" % [label, b.text.split("\n")[0]])
	var br: Rect2 = hud.board_input.get_global_rect()
	check(br.end.x <= view.x + 0.5 and br.end.y <= view.y + 0.5, "%s: whole board on screen" % label)
	check(hud.info_text.size.y >= 40, "%s: info panel visible" % label)


func run(t: SceneTree, shots: String) -> void:
	tree = t
	shots_dir = shots
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	main.board.speed = 8.0

	# --- Portrait phone (390 x 844 CSS px) ------------------------------------
	await set_window(Vector2i(390, 844))
	check(main.hud.portrait, "portrait layout on a phone")
	check(main.hud.board_input.cell_size * main.hud.metrics["css_per_unit"] >= 34.0, "phone grid cells >= 34 CSS px")
	check_layout("phone")
	eq(main.state.living("enemy").size(), 5, "5 enemies at start")
	eq(main.board.intents.size(), 5, "every enemy shows an intent")
	await shot("phone_01_start")

	var ember = hero_u("ember")
	main.select_hero_slot(2)
	eq(main.selected_id, ember.id, "hero button selects Ember")
	await tap(Vector2i(6, 6))
	eq(main.pending, Vector2i(6, 6), "first tap only selects the move tile")
	eq(ember.cell, Vector2i(7, 9), "first tap does not move")
	check(main.board.path.size() > 1, "move path shown")
	await shot("phone_02_move_pending")
	await tap(Vector2i(6, 6))
	eq(ember.cell, Vector2i(6, 6), "second tap confirms the move")

	main.select_ability(1)
	eq(main.mode, "target", "ability button enters targeting")
	await tap(Vector2i(5, 5))
	check(main.board.preview["tags"].has("IGNITE!"), "preview shows ignite")
	check(main.board.preview["tags"].has("BOOM!"), "preview shows barrel chain")
	check(not ember.acted, "first tap on a target only previews")
	await shot("phone_03_fire_preview")
	await tap(Vector2i(5, 5))
	check(ember.acted, "second tap fires")
	eq(main.state.get_terrain(Vector2i(4, 4)), BattleState.Terrain.FLOOR, "barrel exploded")

	# Long-press / Info show enemy details without acting.
	var e = main.state.living("enemy")[0]
	main.on_long_press(e.cell)
	eq(main.board.highlight_intent_id, e.id, "long-press highlights an enemy's plan")
	main.toggle_info()
	var tide = hero_u("tide")
	await tap(tide.cell + Vector2i(0, -1))
	check(main.inspect == tide.cell + Vector2i(0, -1) and not tide.moved, "info mode taps only inspect")
	main.toggle_info()
	await shot("phone_04_inspect")

	# Undo, then End Turn needs a second tap while heroes can still act.
	main.select(tide.id)
	await tap(tide.cell + Vector2i(0, -1))
	await tap(tide.cell + Vector2i(0, -1))
	check(tide.moved, "Tide moved")
	main.undo()
	check(not hero_u("tide").moved, "undo restored Tide")
	await main.end_turn()
	eq(main.state.round_num, 1, "first End Turn tap only arms it")
	check(main.end_armed, "end turn armed")
	await main.end_turn()
	check(main.state.round_num == 2 or main.state.phase != "player", "second tap ends the turn")
	await shot("phone_05_round2")

	# --- Landscape desktop ---------------------------------------------------
	await set_window(Vector2i(1280, 720))
	check(not main.hud.portrait, "landscape layout on desktop")
	check_layout("desktop")
	await shot("desktop_01")

	main.restart()
	check(main.state.round_num == 1 and main.state.living("enemy").size() == 5, "restart resets fight")
	main.queue_free()
	await frames()
	completed = true
