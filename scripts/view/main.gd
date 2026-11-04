## Controller: input, selection, UI text and previews. Asks Rules to resolve
## actions, then hands the resulting events to BoardView to play back.
extends Node2D

const BattleState = preload("res://scripts/core/battle_state.gd")
const Rules = preload("res://scripts/core/rules.gd")
const EnemyAI = preload("res://scripts/core/enemy_ai.gd")
const LevelLoader = preload("res://scripts/core/level_loader.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const BoardView = preload("res://scripts/view/board_view.gd")

const BOARD_ORIGIN := Vector2(20, 64)
const PANEL_X := 640.0
const SLOT_KEYS := ["Q", "W", "E"]

var state
var board
var selected_id: int = -1
var mode: String = "move"  # "move" or "target"
var ability_id: String = ""
var hover: Vector2i = Vector2i(-1, -1)
var undo_stack: Array = []
var busy: bool = false

var top_label: Label
var order_text: RichTextLabel
var hero_text: RichTextLabel
var info_text: RichTextLabel
var ability_buttons: Array = []
var wait_btn: Button
var undo_btn: Button
var end_btn: Button
var fast_btn: Button
var over_layer: Control
var over_label: Label


func _ready() -> void:
	board = BoardView.new()
	board.position = BOARD_ORIGIN
	add_child(board)
	_build_ui()
	restart()


# =========================================================================
# UI construction
# =========================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	top_label = Label.new()
	top_label.position = Vector2(20, 14)
	top_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(top_label)

	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X + 20, 14)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_constant_override("separation", 6)
	layer.add_child(panel)

	order_text = _rich(panel, 170)
	panel.add_child(HSeparator.new())
	hero_text = _rich(panel, 64)

	var abil_box := VBoxContainer.new()
	panel.add_child(abil_box)
	for i in 3:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(select_ability.bind(i))
		b.mouse_entered.connect(_on_button_hover.bind(i))
		abil_box.add_child(b)
		ability_buttons.append(b)

	var row := HBoxContainer.new()
	panel.add_child(row)
	wait_btn = _button(row, "Wait [X]", wait_hero)
	undo_btn = _button(row, "Undo [Z]", undo)
	end_btn = _button(row, "End Turn [Space]", end_turn)
	var row2 := HBoxContainer.new()
	panel.add_child(row2)
	_button(row2, "Restart [R]", restart)
	fast_btn = _button(row2, "Speed x1 [F]", toggle_speed)

	panel.add_child(HSeparator.new())
	info_text = _rich(panel, 150)
	var help := Label.new()
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "Click hero / 1-3 / Tab: select   Click blue tile: move\nQ W E: attack / abilities   Click yellow tile: use\nRight-click / Esc: cancel   Hover an enemy: see its plan"
	panel.add_child(help)

	over_layer = ColorRect.new()
	over_layer.color = Color(0, 0, 0, 0.7)
	over_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.visible = false
	layer.add_child(over_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	over_label = Label.new()
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_font_size_override("font_size", 44)
	box.add_child(over_label)
	var again := Button.new()
	again.text = "  Restart [R]  "
	again.add_theme_font_size_override("font_size", 22)
	again.pressed.connect(restart)
	box.add_child(again)


func _rich(parent: Control, min_h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(420, min_h)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 15)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# =========================================================================
# Input
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c: Vector2i = board.cell_at(board.get_local_mouse_position())
		if c != hover:
			hover = c
			_update_hover()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			click(board.cell_at(board.get_local_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				var heroes := _heroes()
				var i: int = event.keycode - KEY_1
				if i < heroes.size():
					select(heroes[i].id)
			KEY_TAB: select_next()
			KEY_Q: select_ability(0)
			KEY_W: select_ability(1)
			KEY_E: select_ability(2)
			KEY_X: wait_hero()
			KEY_Z: undo()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: end_turn()
			KEY_ESCAPE: cancel()
			KEY_R: restart()
			KEY_F: toggle_speed()


func _can_command() -> bool:
	return not busy and state.phase == "player"


func _selected():
	var u = state.unit_by_id(selected_id) if selected_id >= 0 else null
	return u if u != null and u.alive else null


func _heroes() -> Array:
	return state.units.filter(func(u): return u.team == "hero" and u.alive)


func select(id: int) -> void:
	if not _can_command():
		return
	selected_id = id
	mode = "move"
	refresh()


func select_next() -> void:
	if not _can_command():
		return
	var heroes := _heroes()
	if heroes.is_empty():
		return
	var start := 0
	for i in heroes.size():
		if heroes[i].id == selected_id:
			start = i + 1
	for k in heroes.size():
		var h = heroes[(start + k) % heroes.size()]
		if not h.is_done():
			select(h.id)
			return


func select_ability(slot: int) -> void:
	var u = _selected()
	if not _can_command() or u == null or slot >= u.abilities.size():
		return
	var id: String = u.abilities[slot]
	if not u.can_use(id):
		return
	if mode == "target" and ability_id == id:
		mode = "move"
	else:
		mode = "target"
		ability_id = id
	refresh()


func cancel() -> void:
	if mode == "target":
		mode = "move"
	else:
		selected_id = -1
	refresh()


func click(cell: Vector2i) -> void:
	if not _can_command() or not state.in_bounds(cell):
		return
	var u = _selected()
	if u != null and mode == "target":
		if Rules.ability_targets(state, u, ability_id).has(cell):
			_push_undo()
			var events: Array = Rules.use_ability(state, u, ability_id, cell)
			mode = "move"
			await _run(events)
			return
	var clicked = state.unit_at(cell)
	if clicked != null and clicked.team == "hero":
		select(clicked.id)
		return
	if u != null and mode == "move" and not u.moved and state.move_destinations(u).has(cell):
		_push_undo()
		await _run(Rules.move_unit(state, u, cell))


func wait_hero() -> void:
	var u = _selected()
	if not _can_command() or u == null or u.is_done():
		return
	_push_undo()
	Rules.wait_unit(state, u)
	_after_action()


func undo() -> void:
	if not _can_command() or undo_stack.is_empty():
		return
	state = undo_stack.pop_back()
	mode = "move"
	_after_action()


func end_turn() -> void:
	if not _can_command():
		return
	undo_stack.clear()
	selected_id = -1
	mode = "move"
	await _run(Rules.end_player_turn(state))
	select_next()


func restart() -> void:
	if busy:
		return
	state = LevelLoader.build()
	undo_stack.clear()
	mode = "move"
	over_layer.visible = false
	board.set_state(state)
	selected_id = _heroes()[0].id
	refresh()


func toggle_speed() -> void:
	board.speed = 2.5 if board.speed == 1.0 else 1.0
	fast_btn.text = "Speed x%s [F]" % ("2.5" if board.speed > 1.0 else "1")


func _push_undo() -> void:
	undo_stack.append(state.clone())


func _run(events: Array) -> void:
	busy = true
	_clear_overlays()
	board.show_intents = true
	await board.play(events)
	busy = false
	_after_action()


func _after_action() -> void:
	board.set_state(state)
	var u = _selected()
	if u == null or u.is_done():
		selected_id = -1
		for h in _heroes():
			if not h.is_done():
				selected_id = h.id
				break
	if state.phase == "won" or state.phase == "lost":
		over_label.text = ("VICTORY\n" if state.phase == "won" else "DEFEAT\n") + "Round %d" % state.round_num
		over_layer.visible = true
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
	if u != null and state.phase == "player":
		if mode == "move" and not u.moved:
			board.move_cells = state.move_destinations(u)
		elif mode == "target":
			board.target_cells = Rules.ability_targets(state, u, ability_id)
	_update_texts()
	_update_hover()


func _update_hover() -> void:
	if busy or state == null:
		return
	board.area_cells = []
	board.path = []
	board.preview = {}
	board.highlight_intent_id = -1
	var u = _selected()
	var lines: Array = []
	if state.in_bounds(hover):
		lines.append(_describe_tile(hover))
		if u != null and mode == "target" and board.target_cells.has(hover):
			board.area_cells = Rules.shape_cells(state, u.cell, ability_id, hover)
			board.area_element = GameData.ability(ability_id)["element"]
			var uid: int = u.id
			var aid := ability_id
			var h := hover
			board.preview = _simulate(func(s): return Rules.use_ability(s, s.unit_by_id(uid), aid, h))
			lines.push_front("[b]%s preview[/b] - click to use" % GameData.ability(ability_id)["name"])
			lines.append(_describe_preview(board.preview))
		elif u != null and mode == "move" and board.move_cells.has(hover):
			board.path = BattleState.path_from(state.reachable(u), hover)
		var e = state.unit_at(hover)
		if e != null and e.team == "enemy" and not e.intent.is_empty() and mode != "target":
			board.highlight_intent_id = e.id
			var eid: int = e.id
			board.preview = _simulate(func(s):
				var ev: Array = []
				Rules.execute_enemy_intent(s, s.unit_by_id(eid), ev)
				return ev)
			lines.append(_describe_intent(e))
			lines.append(_describe_preview(board.preview))
	elif u != null and mode == "target":
		var ab := GameData.ability(ability_id)
		lines.append("[b]%s[/b]: %s\nPick a yellow tile." % [ab["name"], ab["desc"]])
	info_text.text = "\n".join(lines.filter(func(l): return l != ""))
	board.queue_redraw()


## Runs an action on a throwaway copy of the state and summarises its events.
func _simulate(fn: Callable) -> Dictionary:
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
		s += "\nChain: [b]" + "  ".join(p["tags"]) + "[/b]"
	return s


func _describe_intent(e) -> String:
	var ab := GameData.ability(e.abilities[0])
	var it: Dictionary = e.intent
	if not it["has_target"]:
		return "[b]%s #%d[/b] (%d/%d hp): advancing, no attack this turn." % [e.name, e.order, e.hp, e.max_hp]
	return "[b]%s #%d[/b] (%d/%d hp): %s on the tile %s is standing on (%d dmg, %s)." % [
		e.name, e.order, e.hp, e.max_hp, ab["name"], it["target_name"], int(ab["damage"]), ab["element"]]


func _describe_tile(c: Vector2i) -> String:
	var bits: Array = []
	match state.get_terrain(c):
		BattleState.Terrain.WALL: bits.append("Wall (blocks movement and sight)")
		BattleState.Terrain.BARREL: bits.append("Explosive barrel (any hit, fire or lightning: 3x3 blast)")
	match state.get_surface(c):
		BattleState.Surface.WATER: bits.append("Water (conducts lightning, fire turns it to steam)")
		BattleState.Surface.OIL: bits.append("Oil (fire ignites the whole patch)")
		BattleState.Surface.STEAM: bits.append("Steam (blocks sight, fades in %d)" % state.steam_timer[state.idx(c)])
	var u = state.unit_at(c)
	if u != null:
		bits.append("%s %d/%d hp%s" % [u.name, u.hp, u.max_hp, ", burning" if u.burning > 0 else ""])
	return "[color=#aab]Tile %d,%d: %s[/color]" % [c.x, c.y, "; ".join(bits) if not bits.is_empty() else "floor"]


func _update_texts() -> void:
	var phase_name: String = "YOUR TURN" if state.phase == "player" else state.phase.to_upper()
	top_label.text = "Round %d  -  %s" % [state.round_num, phase_name]

	var o: Array = ["[b]Turn order[/b]  (heroes in any order, then enemies 1 -> %d)" % state.living("enemy").size()]
	for h in _heroes():
		var status := "done" if h.is_done() else ("moved" if h.moved else ("acted" if h.acted else "ready"))
		var col: String = GameData.hero(h.type_id)["color"]
		o.append("[color=%s]●[/color] %s  %d/%d  [color=#889]%s[/color]%s" % [col, h.name, h.hp, h.max_hp, status, "  [color=#ff7a2b]burning[/color]" if h.burning > 0 else ""])
	var enemies: Array = state.living("enemy")
	enemies.sort_custom(func(a, b): return a.order < b.order)
	for e in enemies:
		var it: Dictionary = e.intent
		var desc := "advances"
		if it.get("has_target", false):
			var ok: bool = EnemyAI.resolve_intent(state, e)["attack_ok"]
			desc = "%s -> %s's tile" % [GameData.ability(e.abilities[0])["name"], it["target_name"]] + ("" if ok else "  [color=#999](blocked)[/color]")
		o.append("[color=#ff6b6b]%d.[/color] %s %d/%d: %s" % [e.order, e.name, e.hp, e.max_hp, desc])
	order_text.text = "\n".join(o)

	var u = _selected()
	for i in 3:
		var b: Button = ability_buttons[i]
		if u == null:
			b.text = "%s  -" % SLOT_KEYS[i]
			b.disabled = true
			continue
		var id: String = u.abilities[i]
		var ab := GameData.ability(id)
		var cd := int(u.cooldowns.get(id, 0))
		var extra := ""
		if cd > 0:
			extra = "  (ready in %d)" % cd
		elif int(ab["cooldown"]) > 0:
			extra = "  (cooldown %d)" % int(ab["cooldown"])
		var mark := "> " if mode == "target" and ability_id == id else ""
		b.text = "%s%s  %s  [%s, %d dmg, range %d]%s" % [mark, SLOT_KEYS[i], ab["name"], ab["element"], int(ab["damage"]), int(ab["range"]), extra]
		b.disabled = not u.can_use(id) or busy
		b.tooltip_text = ab["desc"]
	if u == null:
		hero_text.text = "[b]No hero selected[/b]\nAll heroes done? Press End Turn."
	else:
		var st := []
		st.append("move used" if u.moved else "can move %d" % u.move)
		st.append("action used" if u.acted else "can act")
		hero_text.text = "[b][color=%s]%s[/color][/b]  %d/%d hp%s\n%s" % [
			GameData.hero(u.type_id)["color"], u.name, u.hp, u.max_hp, "  [color=#ff7a2b]burning[/color]" if u.burning > 0 else "", ", ".join(st)]
	wait_btn.disabled = u == null or busy
	undo_btn.disabled = undo_stack.is_empty() or busy
	end_btn.disabled = busy or state.phase != "player"


func _on_button_hover(slot: int) -> void:
	var u = _selected()
	if u != null and slot < u.abilities.size():
		var ab := GameData.ability(u.abilities[slot])
		info_text.text = "[b]%s[/b]: %s" % [ab["name"], ab["desc"]]
