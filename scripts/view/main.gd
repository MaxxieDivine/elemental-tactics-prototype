## Controller. Turns gestures (tap, long-press, buttons, optional keys) into
## Commands, sends them to Rules.apply_command, and hands the returned events
## to BoardView. One input model for mouse and touch:
##   tap to select (a hero, a move tile, a target) -> tap the same thing again to confirm.
## Nothing depends on hover or right-click; long-press or the Info button show details.
## Started by the app with an encounter id; reports the result with
## fight_finished(won) when it was launched from the town.
extends Node2D

signal fight_finished(won: bool)
signal menu_requested

const BattleState = preload("res://scripts/core/battle_state.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Commands = preload("res://scripts/core/commands.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")
const LevelLoader = preload("res://scripts/core/level_loader.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const Hud = preload("res://scripts/view/hud.gd")

const NO_CELL := Vector2i(-1, -1)
const SLOT_KEYS := ["Q", "W", "E"]

var state
var hud
var board
var selected_id: int = -1
var mode: String = "move"  # "move" or "target"
var ability_id: String = ""
var pending: Vector2i = NO_CELL  # tapped once; tap again to confirm
var inspect: Vector2i = NO_CELL  # tile whose details are shown
var info_mode: bool = false  # taps only show details
var end_armed: bool = false  # End Turn tapped once while heroes still had actions
var undo_stack: Array = []
var busy: bool = false
var encounter_id: String = GameData.DEFAULT_ENCOUNTER
var from_town: bool = false  # the end screen returns to town instead of replaying


func _ready() -> void:
	hud = Hud.new()
	add_child(hud)
	board = hud.board
	hud.board_input.tapped.connect(on_tap)
	hud.board_input.long_pressed.connect(on_long_press)
	for i in 3:
		hud.hero_btns[i].pressed.connect(select_hero_slot.bind(i))
		hud.ability_btns[i].pressed.connect(select_ability.bind(i))
	hud.wait_btn.pressed.connect(wait_hero)
	hud.undo_btn.pressed.connect(undo)
	hud.cancel_btn.pressed.connect(cancel)
	hud.info_btn.pressed.connect(toggle_info)
	hud.end_btn.pressed.connect(end_turn)
	hud.restart_btn.pressed.connect(restart)
	hud.speed_btn.pressed.connect(toggle_speed)
	hud.over_btn.pressed.connect(_on_over_pressed)
	hud.over_btn.text = "Back to town" if from_town else "Play again"
	hud.menu_btn.visible = not from_town
	hud.menu_btn.pressed.connect(func(): menu_requested.emit())
	_apply_presentation()
	restart()


## Board size, tile size, party size and look, all from the encounter's data.
func _apply_presentation() -> void:
	var enc: Dictionary = GameData.encounter(encounter_id)
	var pres: Dictionary = enc.get("presentation", {})
	var party: Array = enc.get("party", enc.get("heroes", []))
	board.set_presentation(pres)
	hud.configure(enc["map"][0].length(), enc["map"].size(), float(pres.get("tile_css", 0)), party.size() == 1)


func _on_over_pressed() -> void:
	if from_town:
		fight_finished.emit(state.phase == "won")
	else:
		restart()


# =========================================================================
# Gestures
# =========================================================================

func on_tap(cell: Vector2i) -> void:
	if state == null or not state.in_bounds(cell):
		return
	if info_mode or not _can_command():
		show_details(cell)
		return
	end_armed = false
	var u = _selected()
	var tapped_unit = state.unit_at(cell)
	if u != null and mode == "target":
		if Rules.ability_targets(state, u, ability_id).has(cell):
			await _select_or_confirm(cell)
			return
		if tapped_unit != null and tapped_unit.team == "hero":
			select(tapped_unit.id)
			return
		pending = NO_CELL
		show_details(cell)
		return
	if tapped_unit != null and tapped_unit.team == "hero" and tapped_unit.id != selected_id:
		select(tapped_unit.id)
		return
	if u != null and not u.moved and state.move_destinations(u).has(cell):
		await _select_or_confirm(cell)
		return
	pending = NO_CELL
	show_details(cell)


func on_long_press(cell: Vector2i) -> void:
	if state != null and state.in_bounds(cell):
		show_details(cell)


func _select_or_confirm(cell: Vector2i) -> void:
	if pending == cell:
		await confirm()
	else:
		pending = cell
		inspect = NO_CELL
		refresh()


func show_details(cell: Vector2i) -> void:
	inspect = cell
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Optional desktop shortcuts. Everything is also reachable by tap/click.
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3: select_hero_slot(event.keycode - KEY_1)
		KEY_TAB: select_next()
		KEY_Q: select_ability(0)
		KEY_W: select_ability(1)
		KEY_E: select_ability(2)
		KEY_ENTER, KEY_KP_ENTER: await confirm()
		KEY_X: wait_hero()
		KEY_Z: undo()
		KEY_SPACE: end_turn()
		KEY_ESCAPE: cancel()
		KEY_I: toggle_info()
		KEY_R: restart()
		KEY_F: toggle_speed()


# =========================================================================
# Selection
# =========================================================================

func _can_command() -> bool:
	return not busy and state.phase == "player"


func _selected():
	var u = state.unit_by_id(selected_id) if selected_id >= 0 else null
	return u if u != null and u.alive else null


func _heroes() -> Array:
	return state.units.filter(func(u): return u.team == "hero")


func select(id: int) -> void:
	if not _can_command():
		return
	selected_id = id
	mode = "move"
	pending = NO_CELL
	inspect = NO_CELL
	end_armed = false
	refresh()


func select_hero_slot(i: int) -> void:
	var heroes := _heroes()
	if i < heroes.size() and heroes[i].alive:
		select(heroes[i].id)
	else:
		refresh()


func select_next() -> void:
	if not _can_command():
		return
	var heroes: Array = _heroes().filter(func(h): return h.alive)
	var start := 0
	for i in heroes.size():
		if heroes[i].id == selected_id:
			start = i + 1
	for n in heroes.size():
		var h = heroes[(start + n) % heroes.size()]
		if not h.is_done():
			select(h.id)
			return


func select_ability(slot: int) -> void:
	var u = _selected()
	if not _can_command() or u == null or slot >= u.abilities.size():
		refresh()
		return
	var id: String = u.abilities[slot]
	if mode == "target" and ability_id == id:
		mode = "move"
	elif Rules.ability_available(state, u, id):
		mode = "target"
		ability_id = id
	pending = NO_CELL
	end_armed = false
	refresh()


func cancel() -> void:
	if pending != NO_CELL:
		pending = NO_CELL
	elif mode == "target":
		mode = "move"
	elif inspect != NO_CELL:
		inspect = NO_CELL
	elif info_mode:
		info_mode = false
	else:
		selected_id = -1
	end_armed = false
	refresh()


func toggle_info() -> void:
	info_mode = not info_mode
	if not info_mode:
		inspect = NO_CELL
	refresh()


# =========================================================================
# Commands
# =========================================================================

func confirm() -> void:
	var u = _selected()
	if not _can_command() or u == null or pending == NO_CELL:
		return
	var cmd: Dictionary
	if mode == "target":
		cmd = Commands.use_ability(u.id, ability_id, pending)
		mode = "move"
	else:
		cmd = Commands.move(u.id, pending)
	pending = NO_CELL
	await _send(cmd)


func wait_hero() -> void:
	var u = _selected()
	if _can_command() and u != null:
		await _send(Commands.wait(u.id))


func end_turn() -> void:
	if not _can_command():
		return
	if not end_armed and _heroes().any(func(h): return h.alive and not h.is_done()):
		end_armed = true  # ask for a second tap: ending early is not undoable
		refresh()
		return
	end_armed = false
	undo_stack.clear()
	selected_id = -1
	mode = "move"
	pending = NO_CELL
	inspect = NO_CELL
	await _send(Commands.end_turn())
	select_next()


func undo() -> void:
	if not _can_command() or undo_stack.is_empty():
		return
	state = undo_stack.pop_back()
	mode = "move"
	pending = NO_CELL
	_after_action()


func restart() -> void:
	if busy:
		return
	state = LevelLoader.build_encounter(encounter_id)
	undo_stack.clear()
	mode = "move"
	pending = NO_CELL
	inspect = NO_CELL
	info_mode = false
	end_armed = false
	hud.over_layer.visible = false
	board.set_state(state)
	selected_id = _heroes()[0].id
	refresh()


func toggle_speed() -> void:
	board.speed = 2.5 if board.speed == 1.0 else 1.0
	refresh()


func _send(cmd: Dictionary) -> void:
	var before = state.clone()
	var events: Array = Rules.apply_command(state, cmd)
	if events.is_empty():
		refresh()
		return
	if cmd["type"] != "end_turn":
		undo_stack.append(before)
	busy = true
	_clear_overlays()
	refresh()
	await board.play(events)
	busy = false
	_after_action()


func _after_action() -> void:
	board.set_state(state)
	var u = _selected()
	if (u == null or u.is_done()) and not (_solo() and u != null):
		selected_id = -1
		for h in _heroes():
			if h.alive and not h.is_done():
				selected_id = h.id
				break
	if state.phase == "won" or state.phase == "lost":
		hud.over_label.text = ("VICTORY" if state.phase == "won" else "DEFEAT") + "\nRound %d" % state.round_num
		hud.over_layer.visible = true
	refresh()


# =========================================================================
# Overlays, previews and text
# =========================================================================

func _clear_overlays() -> void:
	board.move_cells = []
	board.target_cells = []
	board.area_cells = []
	board.path = []
	board.preview = {}
	board.highlight_intent_id = -1
	board.pending_cell = NO_CELL
	board.inspect_cell = NO_CELL


func refresh() -> void:
	_clear_overlays()
	board.selected_id = selected_id
	board.intents = []
	for e in state.living("enemy"):
		if e.intent.is_empty():
			continue
		var r := EnemyAI.resolve_intent(state, e)
		r["id"] = e.id
		r["order"] = e.order
		board.intents.append(r)
	var u = _selected()
	var lines: Array = [_prompt(u)]
	if not busy and state.phase == "player" and u != null:
		if mode == "target":
			board.target_cells = Rules.ability_targets(state, u, ability_id)
			if pending != NO_CELL:
				board.area_cells = Rules.shape_cells(state, u.cell, ability_id, pending)
				board.area_element = GameData.ability(ability_id)["element"]
				board.preview = _simulate(Commands.use_ability(u.id, ability_id, pending))
				lines.append(_describe_preview(board.preview))
		elif not u.moved:
			board.move_cells = state.move_destinations(u)
			if pending != NO_CELL:
				board.path = BattleState.path_from(state.reachable(u), pending)
	board.pending_cell = pending
	if inspect != NO_CELL and not busy:
		board.inspect_cell = inspect
		lines.append(_describe_tile(inspect))
		var e = state.unit_at(inspect)
		if e != null and e.team == "enemy" and not e.intent.is_empty():
			board.highlight_intent_id = e.id
			var eid: int = e.id
			if pending == NO_CELL:
				board.preview = _simulate_fn(func(s):
					var ev: Array = []
					Rules.execute_enemy_intent(s, s.unit_by_id(eid), ev)
					return ev)
			lines.append(_describe_intent(e))
			if pending == NO_CELL:
				lines.append(_describe_preview(board.preview))
	lines.append(_turn_order())
	hud.info_text.text = "\n".join(lines.filter(func(l): return l != ""))
	_update_buttons(u)
	board.queue_redraw()


func _prompt(u) -> String:
	var p := ""
	if state.phase == "won" or state.phase == "lost":
		p = "Fight over. Tap Play again."
	elif busy or state.phase != "player":
		p = "Watching the action..."
	elif info_mode:
		p = "Info mode: tap any tile for details. Tap Info again to exit."
	elif end_armed:
		p = ("%s can still act." % _heroes()[0].name if _solo() else "Some heroes can still act.") + " Tap End Turn again to end anyway."
	elif u == null:
		if _heroes().all(func(h): return not h.alive or h.is_done()):
			p = ("%s is done." % _heroes()[0].name if _solo() else "All heroes are done.") + " Tap End Turn."
		else:
			p = "Tap a hero to select it."
	elif mode == "target" and pending != NO_CELL:
		p = "Tap the same tile again to use %s." % GameData.ability(ability_id)["name"]
	elif mode == "target":
		var ab := GameData.ability(ability_id)
		p = "%s: tap a yellow tile to aim. %s" % [ab["name"], ab["desc"]]
	elif pending != NO_CELL:
		p = "Tap the same tile again to move there."
	elif u.is_done():
		p = "%s is done. Tap End Turn." % u.name
	elif not u.moved:
		p = "%s: tap a blue tile to move, or pick an ability." % u.name
	elif not u.acted:
		p = "%s: pick an ability, or Wait." % u.name
	return "[b][color=#ffe08a]%s[/color][/b]" % p


## Runs a command on a throwaway copy of the state and summarises its events.
func _simulate(cmd: Dictionary) -> Dictionary:
	return _simulate_fn(func(s): return Rules.apply_command(s, cmd))


func _simulate_fn(fn: Callable) -> Dictionary:
	var events: Array = fn.call(state.clone())
	var out := {"damage": {}, "deaths": {}, "burn": {}, "moves": {}, "cells": [], "tags": []}
	for ev in events:
		match ev["type"]:
			"damage":
				out["damage"][ev["unit"]] = out["damage"].get(ev["unit"], 0) + ev["amount"]
			"death":
				out["deaths"][ev["unit"]] = true
			"status":
				if ev["burning"] > 0:
					out["burn"][ev["unit"]] = true
			"push":
				out["moves"][ev["unit"]] = ev["to"]
			"surface", "terrain":
				if not out["cells"].has(ev["cell"]):
					out["cells"].append(ev["cell"])
			"text":
				if ev["text"] in ["IGNITE!", "SHOCK!", "BOOM!", "Steam", "Crash", "No sight", "Out of range"] and not out["tags"].has(ev["text"]):
					out["tags"].append(ev["text"])
	return out


func _describe_preview(p: Dictionary) -> String:
	var parts: Array = []
	for id in p["damage"]:
		var u = state.unit_by_id(id)
		var tag := " KO" if p["deaths"].has(id) else ""
		var col := "#ff9f43" if u.team == "hero" else "#ffe066"
		parts.append("[color=%s]%s -%d%s[/color]" % [col, u.name, p["damage"][id], tag])
	var s := "Hits: " + (", ".join(parts) if not parts.is_empty() else "nobody")
	if not p["tags"].is_empty():
		s += "   Chain: [b]" + "  ".join(p["tags"]) + "[/b]"
	return s


func _describe_intent(e) -> String:
	var ab := GameData.ability(e.abilities[0])
	var it: Dictionary = e.intent
	if not it["has_target"]:
		return "[b]%s #%d[/b]: advancing, no attack this turn." % [e.name, e.order]
	return "[b]%s #%d[/b] will %s the tile %s is on (%d %s dmg)." % [
		e.name, e.order, ab["name"], it["target_name"], int(ab["damage"]), ab["element"]]


func _describe_tile(c: Vector2i) -> String:
	return describe_tile(state, c, bool(GameData.setting("debug_tile_text", false)))


## Details for a tapped tile. Players see only what matters (terrain, surface,
## unit); raw text such as "Tile 5,6: floor" needs the debug_tile_text setting.
static func describe_tile(st, c: Vector2i, debug: bool) -> String:
	var bits: Array = []
	var t_desc := str(st.tile_info(st.get_terrain(c)).get("desc", ""))
	var s_desc := str(st.surface_info(st.get_surface(c)).get("desc", ""))
	match st.get_terrain(c):
		BattleState.Terrain.FLOOR: pass
		BattleState.Terrain.WALL: bits.append(t_desc if t_desc != "" else "Wall: blocks movement and sight")
		BattleState.Terrain.BARREL: bits.append(t_desc if t_desc != "" else "Explosive barrel: any hit, fire or lightning sets off a 3x3 blast")
		_: bits.append(t_desc if t_desc != "" else BattleState.terrain_name(st.get_terrain(c)).capitalize())
	match st.get_surface(c):
		BattleState.Surface.WATER: bits.append(s_desc if s_desc != "" else "Water: conducts lightning, fire turns it to steam")
		BattleState.Surface.OIL: bits.append(s_desc if s_desc != "" else "Oil: fire ignites the whole patch")
		BattleState.Surface.STEAM: bits.append("Steam: blocks sight, fades in %d" % st.steam_timer[st.idx(c)])
	var u = st.unit_at(c)
	if u != null:
		bits.append("%s %d/%d hp%s" % [u.name, u.hp, u.max_hp, ", burning" if u.burning > 0 else ""])
	if debug:
		return "[color=#aab]Tile %d,%d: %s[/color]" % [c.x, c.y, "; ".join(bits) if not bits.is_empty() else "floor"]
	if bits.is_empty():
		return ""
	return "[color=#aab]%s[/color]" % "; ".join(bits)


func _solo() -> bool:
	return _heroes().size() == 1


func _turn_order() -> String:
	var who := ("%s" % _heroes()[0].name) if _solo() else "heroes in any order"
	var o: Array = ["[b]Turn order[/b]: %s, then enemies 1 -> %d" % [who, state.living("enemy").size()]]
	var enemies: Array = state.living("enemy")
	enemies.sort_custom(func(a, b): return a.order < b.order)
	for e in enemies:
		var it: Dictionary = e.intent
		var desc := "advances"
		if it.get("has_target", false):
			var ok: bool = EnemyAI.resolve_intent(state, e)["attack_ok"]
			desc = "%s -> %s's tile" % [GameData.ability(e.abilities[0])["name"], it["target_name"]] + ("" if ok else " [color=#999](blocked)[/color]")
		o.append("[color=#ff6b6b]%d.[/color] %s %d/%d: %s" % [e.order, e.name, e.hp, e.max_hp, desc])
	return "\n".join(o)


func _update_buttons(u) -> void:
	var can := _can_command()
	hud.top_label.text = "Round %d\n%s" % [state.round_num, "Your turn" if state.phase == "player" else state.phase.capitalize()]
	var heroes := _heroes()
	for i in 3:
		var b: Button = hud.hero_btns[i]
		if i >= heroes.size():
			b.visible = false
			continue
		var h = heroes[i]
		var status := "down" if not h.alive else ("done" if h.is_done() else ("moved" if h.moved else ("acted" if h.acted else "ready")))
		b.text = "%s %d/%d\n%s%s" % [h.name, h.hp, h.max_hp, status, ", burning" if h.burning > 0 else ""]
		b.button_pressed = h.id == selected_id
		b.disabled = not h.alive or not can
		b.add_theme_color_override("font_color", Color(GameData.hero(h.type_id)["color"]))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var sel_slot := -1
	for i in heroes.size():
		if heroes[i].id == selected_id:
			sel_slot = i
	hud.show_ability_owner(u.name if u != null else "", Color(GameData.hero(u.type_id)["color"]) if u != null else Color.GRAY,
		sel_slot, heroes.map(func(h): return Color(GameData.hero(h.type_id)["color"])))
	for i in 3:
		var b: Button = hud.ability_btns[i]
		if u == null or i >= u.abilities.size():
			b.text = "-"
			b.disabled = true
			b.button_pressed = false
			continue
		var id: String = u.abilities[i]
		var ab := GameData.ability(id)
		var cd := int(u.cooldowns.get(id, 0))
		var line2 := "%s %d · r%d" % [ab["element"], int(ab["damage"]), int(ab["range"])]
		var left := int(u.uses.get(id, -1))  # -1: no limit
		if left == 0:
			line2 = "used"
		elif ab.has("source_tile") and Rules.source_cells(state, u, id).is_empty():
			line2 = str(ab.get("needs_text", "needs " + str(ab["source_tile"])))
		elif left > 0:
			line2 = "%d left" % left
		if cd > 0:
			line2 = "ready in %d" % cd
		b.text = "%s\n%s" % [ab["name"], line2]
		b.tooltip_text = "[%s] %s" % [SLOT_KEYS[i], ab["desc"]]
		b.disabled = not can or not Rules.ability_available(state, u, id)
		b.button_pressed = mode == "target" and ability_id == id
	hud.wait_btn.disabled = not can or u == null or u.is_done()
	hud.undo_btn.disabled = not can or undo_stack.is_empty()
	hud.cancel_btn.disabled = not can or (pending == NO_CELL and mode != "target" and inspect == NO_CELL and not info_mode and selected_id < 0)
	hud.info_btn.button_pressed = info_mode
	hud.end_btn.disabled = not can
	hud.end_btn.text = "Confirm?" if end_armed else "End Turn"
	hud.speed_btn.text = "x2.5" if board.speed > 1.0 else "x1"
