## Town screen controller for every walkable map (the town outside, the inn's
## rooms). Builds the TileMapLayer and the depth-sorted actors for the current
## map from data/maps/<id>.json, turns taps into "walk here" or "walk next to
## that and use it", plays interactions through the dialogue box, and goes
## through exits with a short fade. Nothing here is specific to one map:
## exits, arrival cells and facing all come from data.
## Rules live in core: TownMap (paths, exits, flag-based world state, pacing
## routes), Dialogue (data + flags), GameSession (flags and where the player
## is, across maps and fights). When a conversation changes a flag that moves,
## shows or hides something on this map, the map is rebuilt behind a short fade.
## Lighting comes from the map's data preset for the story's time of day
## (Lighting): tinted tiles and actors plus drawn light pools (TownLighting).
## Walking onto a trigger zone starts its interaction. A dialogue line's
## "then" step plays here: a fade with a text card (and a new time of day,
## and where the player stands), or a world object fading out or in.
## Asks the app for a fight with `fight_requested`; never runs one itself.
extends Node2D

signal fight_requested(request: Dictionary)
signal menu_requested
signal map_changed(map_id: String)

const GameData = preload("res://scripts/core/game_data.gd")
const TownMap = preload("res://scripts/core/town_map.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const Lighting = preload("res://scripts/core/lighting.gd")
const TownLighting = preload("res://scripts/view/town_lighting.gd")
const ScreenMetrics = preload("res://scripts/view/screen_metrics.gd")
const TownTiles = preload("res://scripts/view/town_tiles.gd")
const TownActor = preload("res://scripts/view/town_actor.gd")
const DialogueScene = preload("res://scenes/dialogue_box.tscn")

const NO_CELL := Vector2i(-1, -1)
const TAP_SLOP := 14.0

var world: Dictionary  # data/town.json: legend, tuning, start
var def: Dictionary  # the current map's data
var map_id: String = ""
var map  # TownMap
var session  # GameSession
var dialogue  # Dialogue runner
var ts: int = 16
var zoom: float = 2.5  # world pixels -> UI units (snapped to whole device pixels)
var step_time: float = 0.16
var fade_time: float = 0.35
var pace_step_time: float = 0.45  # seconds per pacing step
var pace_wait: float = 1.2  # pause at each pace point
var card_time: float = 1.8  # seconds a transition card stays up
var object_fade_time: float = 1.4  # seconds a world object takes to fade out/in

var world_root: Node2D  # everything belonging to the current map
var ground: TileMapLayer  # every tile without its own night tint
var ground_layers: Array = []  # ground, then one layer per preset tile tint
var lighting  # TownLighting: light pools and window panes
var light: Dictionary = {}  # the lighting preset in use (Lighting.preset_for)
var time_of_day: String = ""  # the time the map was built for
var sorted: Node2D  # y-sorted actors
var marker: Node2D
var camera: Camera2D
var ui: CanvasLayer
var dialogue_box
var menu_btn: Button
var fade: ColorRect
var card: Label  # transition card text, over the fade
var card_catch: Control  # takes the tap that skips a card
var _card_skip := false
var transitioning := false
var player
var actors: Dictionary = {}  # id -> TownActor
## Pacing NPCs being animated: id -> {"from": Vector2, "t": float, "dur": float, "wait": float}
var pacing: Dictionary = {}

var player_cell: Vector2i
var path: Array = []  # cells still to walk
var target_id: String = ""  # use this (interaction or exit) on arrival
var _step_from: Vector2
var _step_t: float = 0.0  # time left in the current step
var _step_dur: float = 1.0
var _down := false
var _down_pos := Vector2.ZERO
var _metrics: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world = TownMap.world()
	ts = int(world.get("tile_size", 16))
	step_time = float(world.get("step_time", 0.16))
	fade_time = float(world.get("fade_time", 0.35))
	pace_step_time = float(world.get("pace_step_time", pace_step_time))
	pace_wait = float(world.get("pace_wait", pace_wait))
	card_time = float(world.get("card_time", card_time))
	object_fade_time = float(world.get("object_fade_time", object_fade_time))
	session = GameSession.get_current()
	dialogue = Dialogue.new(session.flags)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_build_ui()
	var spot: Dictionary = session.spot()
	if not load_map(spot["map"], spot["cell"], spot["facing"]):
		var start: Dictionary = GameSession.start_spot()
		load_map(start["map"], start["cell"], start["facing"])
	get_tree().root.size_changed.connect(relayout)
	relayout()
	_snap_camera()


## Shows map `id` with the player on `cell` facing `facing`. Returns false
## (and changes nothing) if the map does not exist.
func load_map(id: String, cell: Vector2i, facing: String) -> bool:
	var m = TownMap.load_map(id, session.flags)
	if m == null:
		return false
	map = m
	map_id = id
	def = map.def  # world state already applied for the current flags
	path = []
	target_id = ""
	_step_t = 0.0
	if world_root != null:
		remove_child(world_root)
		world_root.queue_free()
	actors.clear()
	pacing.clear()
	world_root = Node2D.new()
	add_child(world_root)
	move_child(world_root, 0)
	player_cell = cell
	if not map.is_walkable(cell):
		push_warning("Map '%s': arrival cell %s is not walkable." % [id, str(cell)])
	_build_world(facing)
	session.set_spot(map_id, player_cell, facing)
	if camera != null and ui != null:
		if not _metrics.is_empty():
			relayout()  # a map may set its own zoom
		_snap_camera()
	map_changed.emit(map_id)
	return true


## Where the player is right now: {"map", "cell", "facing"}.
func current_spot() -> Dictionary:
	return {"map": map_id, "cell": player_cell, "facing": player.facing}


func _build_world(facing: String) -> void:
	time_of_day = session.flags.time_of_day()
	light = Lighting.preset_for(def, time_of_day)
	_build_ground()
	lighting = TownLighting.new()
	lighting.setup(Lighting.glows(map, light, ts))
	world_root.add_child(lighting)

	marker = Node2D.new()
	marker.draw.connect(_draw_marker)
	world_root.add_child(marker)

	sorted = Node2D.new()
	sorted.y_sort_enabled = true
	world_root.add_child(sorted)
	var chars: Dictionary = GameData.get_json("characters")
	for n in def.get("npcs", []):
		var c: Dictionary = chars.get(n["character"], {})
		var a = _add_actor(n["id"], "character", map.cell_of_thing(n["id"]), c.get("sprite", ""), c.get("color", "#888888"), "", n.get("facing", "down"), str(n.get("mood", "")))
		a.modulate = Lighting.tint(light, Lighting.tint_key("npc", n))
		if map.pacers.has(n["id"]):
			pacing[n["id"]] = {"from": a.position, "t": 0.0, "dur": float(n.get("pace_step_time", pace_step_time)), "wait": float(n.get("pace_wait", pace_wait))}
	for o in def.get("objects", []):
		var a = _add_actor(o["id"], "object", TownMap.cell_of(o["cell"]), o.get("sprite", ""), o.get("color", "#888888"), o.get("shape", ""))
		a.modulate = Lighting.tint(light, Lighting.tint_key("object", o))
	for i in def.get("props", []).size():
		var p: Dictionary = def["props"][i]
		var a = _add_actor("prop_%d" % i, "prop", TownMap.cell_of(p["cell"]), p.get("sprite", ""), p.get("color", "#888888"), p.get("shape", ""))
		a.modulate = Lighting.tint(light, Lighting.tint_key("prop", p))

	var pc: Dictionary = chars.get(world["player"]["character"], {})
	player = _add_actor("player", "character", player_cell, pc.get("sprite", ""), pc.get("color", "#ffffff"), "", facing)
	player.modulate = Lighting.tint(light, "actor_tint")


## The tiles, tinted for the lighting preset: one layer for the shared
## "tint", plus one per legend char with its own "tile_tints" colour.
func _build_ground() -> void:
	var tile_set: TileSet = TownTiles.build(world)
	var by_tint := {}  # legend char with its own tint -> layer
	ground_layers = []
	ground = TileMapLayer.new()
	ground.tile_set = tile_set
	ground.modulate = Lighting.tint(light, "tint")
	world_root.add_child(ground)
	ground_layers.append(ground)
	var own: Dictionary = light.get("tile_tints", {})
	for y in map.size.y:
		for x in map.size.x:
			var c := Vector2i(x, y)
			var ch: String = map.tile_char(c)
			var layer: TileMapLayer = ground
			if own.has(ch):
				if not by_tint.has(ch):
					layer = TileMapLayer.new()
					layer.tile_set = tile_set
					layer.modulate = Lighting.tile_tint(light, ch)
					world_root.add_child(layer)
					ground_layers.append(layer)
					by_tint[ch] = layer
				layer = by_tint[ch]
			layer.set_cell(c, TownTiles.SOURCE_ID, TownTiles.atlas_of(map.tile_def(c)))


func _add_actor(id: String, kind: String, cell: Vector2i, sprite: String, color: String, shape: String, facing: String = "down", mood: String = ""):
	var a = TownActor.new()
	a.id = id
	a.kind = kind
	a.shape = shape
	a.mood = mood
	a.color = Color(color)
	a.facing = facing
	a.position = feet(cell)
	a.setup(sprite)
	sorted.add_child(a)
	actors[id] = a
	return a


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 16
	root.theme = th
	ui.add_child(root)
	menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(_on_menu)
	root.add_child(menu_btn)
	dialogue_box = DialogueScene.instantiate()
	root.add_child(dialogue_box)
	dialogue_box.closed.connect(_on_dialogue_closed)
	dialogue_box.step_requested.connect(_on_dialogue_step)
	# Map-change fade: drawn over everything, never takes input itself.
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.02, 0.04, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	# Transition card ("Later that night"): text over the fade. While it is
	# up, a tap or click anywhere skips it.
	card_catch = Control.new()
	card_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_catch.mouse_filter = Control.MOUSE_FILTER_STOP
	card_catch.visible = false
	card_catch.gui_input.connect(_on_card_input)
	root.add_child(card_catch)
	card = Label.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_theme_font_size_override("font_size", 26)
	card.add_theme_color_override("font_color", Color("#f4efe1"))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	card.visible = false
	root.add_child(card)


func _on_menu() -> void:
	if transitioning:
		return
	session.set_spot(map_id, player_cell, player.facing)
	menu_requested.emit()


func relayout() -> void:
	_metrics = ScreenMetrics.apply(get_tree().root)
	var size: Vector2 = _metrics["size"]
	var ins: Array = _metrics["insets"]
	menu_btn.position = Vector2(ins[3] + 8, ins[0] + 8)
	menu_btn.size = Vector2(76, 48)
	card.offset_left = ins[3] + 24
	card.offset_right = -ins[1] - 24
	dialogue_box.layout(size, ins)
	# Each art pixel covers a whole number of device pixels, so pixel art
	# stays crisp at any screen density.
	var dev: float = _metrics["css_per_unit"] * _metrics["dpr"]
	zoom = maxf(1.0, roundf(float(def.get("zoom", world.get("zoom", 2.5))) * dev)) / dev
	camera.zoom = Vector2(zoom, zoom)


# =========================================================================
# Geometry
# =========================================================================

## Pixel position of the feet of whoever stands on a cell.
func feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * ts + ts * 0.5, c.y * ts + ts - 1)


func cell_at_world(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / ts), floori(p.y / ts))


## What a tap on a cell means (an exit or interactive NPC/object id, or "").
func target_at(c: Vector2i) -> String:
	return map.target_at(c)


func _interaction_of(id: String) -> String:
	return str(map.targets.get(id, {}).get("interaction", ""))


# =========================================================================
# Input: tap or click (touch arrives as emulated mouse). No hover needed.
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_down = true
		_down_pos = event.position
	elif _down:
		_down = false
		if event.position.distance_to(_down_pos) <= TAP_SLOP:
			var world: Vector2 = make_input_local(event).position
			tap_cell(cell_at_world(world))
			get_viewport().set_input_as_handled()


## One tap on a cell: walk there, or walk next to a target and interact.
func tap_cell(c: Vector2i) -> void:
	if dialogue_box.is_open() or transitioning:
		return
	var id := target_at(c)
	if id != "":
		var a: Dictionary = map.approach_target(player_cell, id)
		if a.is_empty():
			return
		target_id = id
		_set_path(a["path"], a["cell"])
		if is_idle():
			_arrive()
		return
	if map.is_walkable(c):
		target_id = ""
		_set_path(map.find_path(player_cell, c), c)


func _set_path(p: Array, goal: Vector2i) -> void:
	path = p
	marker.set_meta("goal", goal if not p.is_empty() else NO_CELL)
	marker.queue_redraw()


func is_idle() -> bool:
	return path.is_empty() and _step_t <= 0.0 and not transitioning


func _process(delta: float) -> void:
	_walk(delta)
	_pace(delta)
	_follow(delta)


## True while NPC `id` should hold still: a conversation is open, the map is
## changing, or the player is walking over to talk to it.
func pacing_paused(id: String) -> bool:
	return dialogue_box.is_open() or transitioning or target_id == id


## Steps pacing NPCs along their data routes. A step never goes onto the
## player's tile or the rest of the player's path, so it never blocks them.
func _pace(delta: float) -> void:
	for id in pacing:
		var p: Dictionary = pacing[id]
		var a = actors[id]
		var pacer = map.pacers[id]
		if p["t"] > 0.0:
			p["t"] = maxf(0.0, p["t"] - delta)
			a.position = p["from"].lerp(feet(pacer.cell), 1.0 - p["t"] / p["dur"])
			if p["t"] <= 0.0 and pacer.at_stop():
				p["hold"] = p["wait"]
				a.facing = str(map.targets[id]["def"].get("facing", a.facing))  # look at whoever they are upset with
			continue
		if pacing_paused(id):
			continue
		if p.get("hold", 0.0) > 0.0:
			p["hold"] -= delta
			continue
		var from: Vector2i = pacer.cell
		if map.step_pacer(id, func(c): return c == player_cell or path.has(c)):
			a.facing = TownMap.facing_toward(from, pacer.cell)
			p["from"] = a.position
			p["dur"] = maxf(0.0001, p["dur"])
			p["t"] = p["dur"]


func _walk(delta: float) -> void:
	if _step_t <= 0.0:
		if path.is_empty():
			return
		var next: Vector2i = path.pop_front()
		if not map.is_walkable(next):
			path.clear()
			return
		player.facing = TownMap.facing_toward(player_cell, next)
		_step_from = player.position
		player_cell = next
		_step_t = step_time if step_time > 0.0 else 0.0001
		_step_dur = _step_t
	_step_t -= delta
	var k := clampf(1.0 - _step_t / _step_dur, 0.0, 1.0)
	player.position = _step_from.lerp(feet(player_cell), k)
	if _step_t <= 0.0:
		_step_t = 0.0
		player.position = feet(player_cell)
		var trig: Dictionary = map.trigger_at(player_cell, session.flags)
		if not trig.is_empty():
			path.clear()
			target_id = ""
			_set_path([], NO_CELL)
			run_trigger(trig)
			return
		if path.is_empty():
			_set_path([], NO_CELL)
			_arrive()


func _arrive() -> void:
	if target_id == "":
		return
	var id := target_id
	target_id = ""
	if not map.can_use_from(id, player_cell):
		return
	player.facing = map.facing_to_target(player_cell, id)
	if map.targets[id]["kind"] == "exit":
		go_through(id)
		return
	var tc: Vector2i = map.cell_of_thing(id)
	if actors.has(id) and actors[id].kind == "character":
		actors[id].facing = TownMap.facing_toward(tc, player_cell)
	interact(id)


## Leaves through an exit: fade out, show its target map with the player at
## its arrival cell and facing (all from data), fade in. Flags are untouched.
func go_through(exit_id: String) -> void:
	var exit: Dictionary = map.exit_def(exit_id)
	if exit.is_empty() or transitioning:
		return
	var to := TownMap.arrival(exit)
	if TownMap.map_def(to["map"]).is_empty():
		push_warning("Exit '%s' leads to missing map '%s'." % [exit_id, to["map"]])
		return
	transitioning = true
	if fade_time > 0.0:
		var out := create_tween()
		out.tween_property(fade, "color:a", 1.0, fade_time * 0.5)
		await out.finished
	session.go_through(exit)
	load_map(to["map"], to["cell"], to["facing"])
	if fade_time > 0.0:
		var back := create_tween()
		back.tween_property(fade, "color:a", 0.0, fade_time * 0.5)
		await back.finished
	fade.color.a = 0.0
	transitioning = false


## Starts an interaction by its data id (from the NPC/object definition).
func interact(id: String) -> void:
	play_interaction(_interaction_of(id))


## Plays an interaction from dialogue.json by its id.
func play_interaction(interaction: String) -> bool:
	if interaction == "" or not dialogue.start(interaction):
		return false
	dialogue_box.open(dialogue, float(world.get("text_speed", 45)))
	return true


## The player walked onto a trigger zone (its data from the map's
## "triggers"): stop, turn its way, and start its interaction. A "once"
## trigger is remembered in the story so it never runs again.
func run_trigger(trig: Dictionary) -> void:
	if bool(trig.get("once", false)):
		session.flags.mark_ran(str(trig["id"]))
	if trig.has("facing"):
		player.facing = str(trig["facing"])
	session.set_spot(map_id, player_cell, player.facing)
	play_interaction(str(trig.get("interaction", "")))


# =========================================================================
# Dialogue steps: a line's "then" (see Dialogue). Story effects are already
# applied by the runner; this only shows them.
# =========================================================================

func _on_dialogue_step(step: Dictionary) -> void:
	await play_step(step)
	dialogue_box.resume()


## True when a step needs the screen to fade (a card, a new time, a move).
static func step_fades_screen(step: Dictionary) -> bool:
	return step.has("card") or step.has("set_time") or step.has("place")


func play_step(step: Dictionary) -> void:
	transitioning = true
	var t := float(step.get("fade_time", object_fade_time))
	await _fade_things(step.get("fade_out", []), 1.0, 0.0, t)
	if step_fades_screen(step):
		await _screen_step(step)
	else:
		# Only things fading out/in changed: rebuild in place without a fade.
		var fading_in: Array = step.get("fade_in", [])
		load_map(map_id, player_cell, player.facing)
		for id in fading_in:
			_set_thing_alpha(id, 0.0)
		await _fade_things(fading_in, 0.0, 1.0, t)
	transitioning = false


## Fade out, card up, rebuild for the new time and flags with the player
## at "place" (else where they stand), card down, fade in.
func _screen_step(step: Dictionary) -> void:
	var half := maxf(fade_time, float(world.get("card_fade_time", fade_time)))
	await _tween_fade(1.0, half)
	var text := str(step.get("card", ""))
	var cell: Vector2i = TownMap.cell_of(step["place"]) if step.has("place") else player_cell
	load_map(map_id, cell, str(step.get("facing", player.facing)))
	if text != "":
		await show_card(text, float(step.get("card_time", card_time)))
	await _tween_fade(0.0, half)


func _tween_fade(to: float, dur: float) -> void:
	if dur > 0.0:
		var tw := create_tween()
		tw.tween_property(fade, "color:a", to, dur)
		await tw.finished
	fade.color.a = to


## Shows a transition card for `secs` seconds (a tap skips it).
func show_card(text: String, secs: float) -> void:
	card.text = text
	card.visible = true
	card_catch.visible = true
	_card_skip = false
	var t := 0.0
	var fade_in := 0.25
	while t < secs and not _card_skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		card.modulate.a = clampf(t / fade_in, 0.0, 1.0) if secs > 0.0 else 1.0
	card.visible = false
	card.modulate.a = 0.0
	card_catch.visible = false


## True while a transition card is up.
func card_showing() -> bool:
	return card.visible


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_card_skip = true
		card_catch.accept_event()


## Fades world things (and their glows) from one alpha to another.
func _fade_things(ids: Array, from: float, to: float, dur: float) -> void:
	var live: Array = ids.filter(func(id): return actors.has(id))
	if live.is_empty():
		return
	var t := 0.0
	while dur > 0.0 and t < dur:
		for id in live:
			_set_thing_alpha(id, lerpf(from, to, t / dur))
		await get_tree().process_frame
		t += get_process_delta_time()
	for id in live:
		_set_thing_alpha(id, to)


func _set_thing_alpha(id: String, a: float) -> void:
	if actors.has(id):
		actors[id].modulate.a = a
	lighting.set_alpha(id, a)


func _on_dialogue_closed() -> void:
	if not dialogue.fight_request.is_empty():
		var req: Dictionary = dialogue.fight_request
		dialogue.fight_request = {}
		fight_requested.emit(req)
		return
	refresh_world()


## Re-applies the flag-based world state after flags may have changed. If an
## NPC/object on this map appears, disappears, moves or changes, the map is
## rebuilt behind a short fade with the player where they stand. Returns true
## if anything changed.
func refresh_world() -> bool:
	var now = TownMap.load_map(map_id, session.flags)
	if now == null or (now.def.get("npcs", []) == def.get("npcs", []) and now.def.get("objects", []) == def.get("objects", []) and session.flags.time_of_day() == time_of_day):
		return false
	transitioning = true
	var facing: String = player.facing
	if fade_time > 0.0:
		var out := create_tween()
		out.tween_property(fade, "color:a", 1.0, fade_time * 0.5)
		await out.finished
	load_map(map_id, player_cell, facing)
	if fade_time > 0.0:
		var back := create_tween()
		back.tween_property(fade, "color:a", 0.0, fade_time * 0.5)
		await back.finished
	fade.color.a = 0.0
	transitioning = false
	return true


# =========================================================================
# Camera: follow the player, stay inside the map, keep clear of the dialogue.
# =========================================================================

func _camera_target() -> Vector2:
	var view: Vector2 = get_viewport_rect().size / zoom
	var mp := Vector2(map.size * ts)
	var want: Vector2 = player.position + Vector2(0, -ts * 0.5)
	var extra_bottom := 0.0
	if dialogue_box.is_open():
		# Centre the player in the space above the box.
		var hidden: float = (get_viewport_rect().size.y - dialogue_box.top()) / zoom
		want.y += hidden * 0.5
		extra_bottom = hidden
	var out := Vector2.ZERO
	for i in 2:
		var lo: float = view[i] * 0.5
		var hi: float = mp[i] - view[i] * 0.5 + (extra_bottom if i == 1 else 0.0)
		out[i] = mp[i] * 0.5 if hi < lo else clampf(want[i], lo, hi)
	return out


func _follow(delta: float) -> void:
	camera.position = camera.position.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))


func _snap_camera() -> void:
	camera.position = _camera_target()


func _draw_marker() -> void:
	var g: Vector2i = marker.get_meta("goal", NO_CELL)
	if g == NO_CELL:
		return
	var r := Rect2(Vector2(g * ts) + Vector2(1, 1), Vector2(ts - 2, ts - 2))
	var col := Color(1, 1, 1, 0.75)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var dx := 4.0 if corner.x == r.position.x else -4.0
		var dy := 4.0 if corner.y == r.position.y else -4.0
		marker.draw_line(corner, corner + Vector2(dx, 0), col, 1.0)
		marker.draw_line(corner, corner + Vector2(0, dy), col, 1.0)
