## Town screen controller. Builds the TileMapLayer and the depth-sorted
## actors from data/town.json, turns taps into "walk here" or "walk next to
## that and interact", and plays interactions through the dialogue box.
## Rules live in core: TownMap (paths), Dialogue (data + flags), GameSession.
## Asks the app for a fight with `fight_requested`; never runs one itself.
extends Node2D

signal fight_requested(request: Dictionary)
signal menu_requested

const GameData = preload("res://scripts/core/game_data.gd")
const TownMap = preload("res://scripts/core/town_map.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const ScreenMetrics = preload("res://scripts/view/screen_metrics.gd")
const TownTiles = preload("res://scripts/view/town_tiles.gd")
const TownActor = preload("res://scripts/view/town_actor.gd")
const DialogueScene = preload("res://scenes/dialogue_box.tscn")

const NO_CELL := Vector2i(-1, -1)
const TAP_SLOP := 14.0

var def: Dictionary
var map  # TownMap
var session  # GameSession
var dialogue  # Dialogue runner
var ts: int = 16
var zoom: float = 2.5  # world pixels -> UI units (snapped to whole device pixels)
var step_time: float = 0.16

var ground: TileMapLayer
var sorted: Node2D  # y-sorted actors
var marker: Node2D
var camera: Camera2D
var ui: CanvasLayer
var dialogue_box
var menu_btn: Button
var player
var actors: Dictionary = {}  # id -> TownActor

var player_cell: Vector2i
var path: Array = []  # cells still to walk
var target_id: String = ""  # interact with this on arrival
var _step_from: Vector2
var _step_t: float = 0.0  # time left in the current step
var _step_dur: float = 1.0
var _down := false
var _down_pos := Vector2.ZERO
var _metrics: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	def = GameData.get_json("town")
	ts = int(def.get("tile_size", 16))
	step_time = float(def.get("step_time", 0.16))
	session = GameSession.get_current()
	map = TownMap.from_data(def)
	dialogue = Dialogue.new(session.flags)
	_build_world()
	_build_ui()
	get_tree().root.size_changed.connect(relayout)
	relayout()
	_snap_camera()


func _build_world() -> void:
	ground = TileMapLayer.new()
	ground.tile_set = TownTiles.build(def)
	for y in map.size.y:
		for x in map.size.x:
			var c := Vector2i(x, y)
			ground.set_cell(c, TownTiles.SOURCE_ID, TownTiles.atlas_of(map.tile_def(c)))
	add_child(ground)

	marker = Node2D.new()
	marker.draw.connect(_draw_marker)
	add_child(marker)

	sorted = Node2D.new()
	sorted.y_sort_enabled = true
	add_child(sorted)
	var chars: Dictionary = GameData.get_json("characters")
	for n in def.get("npcs", []):
		var c: Dictionary = chars.get(n["character"], {})
		_add_actor(n["id"], "character", TownMap.cell_of(n["cell"]), c.get("sprite", ""), c.get("color", "#888888"), "", n.get("facing", "down"))
	for o in def.get("objects", []):
		_add_actor(o["id"], "object", TownMap.cell_of(o["cell"]), o.get("sprite", ""), o.get("color", "#888888"), o.get("shape", ""))
	for i in def.get("props", []).size():
		var p: Dictionary = def["props"][i]
		_add_actor("prop_%d" % i, "prop", TownMap.cell_of(p["cell"]), p.get("sprite", ""), p.get("color", "#888888"), p.get("shape", ""))

	var pd: Dictionary = def["player"]
	var pc: Dictionary = chars.get(pd["character"], {})
	player_cell = TownMap.cell_of(pd["cell"])
	var facing: String = pd.get("facing", "down")
	if not session.town_spot.is_empty():
		player_cell = session.town_spot["cell"]
		facing = session.town_spot["facing"]
	player = _add_actor("player", "character", player_cell, pc.get("sprite", ""), pc.get("color", "#ffffff"), "", facing)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()


func _add_actor(id: String, kind: String, cell: Vector2i, sprite: String, color: String, shape: String, facing: String = "down"):
	var a = TownActor.new()
	a.id = id
	a.kind = kind
	a.shape = shape
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
	menu_btn.pressed.connect(func(): menu_requested.emit())
	root.add_child(menu_btn)
	dialogue_box = DialogueScene.instantiate()
	root.add_child(dialogue_box)
	dialogue_box.closed.connect(_on_dialogue_closed)


func relayout() -> void:
	_metrics = ScreenMetrics.apply(get_tree().root)
	var size: Vector2 = _metrics["size"]
	var ins: Array = _metrics["insets"]
	menu_btn.position = Vector2(ins[3] + 8, ins[0] + 8)
	menu_btn.size = Vector2(76, 48)
	dialogue_box.layout(size, ins)
	# Each art pixel covers a whole number of device pixels, so pixel art
	# stays crisp at any screen density.
	var dev: float = _metrics["css_per_unit"] * _metrics["dpr"]
	zoom = maxf(1.0, roundf(float(def.get("zoom", 2.5)) * dev)) / dev
	camera.zoom = Vector2(zoom, zoom)


# =========================================================================
# Geometry
# =========================================================================

## Pixel position of the feet of whoever stands on a cell.
func feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * ts + ts * 0.5, c.y * ts + ts - 1)


func cell_at_world(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / ts), floori(p.y / ts))


## Interactive NPC/object shown at a tapped cell. Sprites stand up to about
## one tile above their own, so a tap on the blocked tile just above one
## (a wall behind the innkeeper, say) also counts.
func target_at(c: Vector2i) -> String:
	var id: String = map.thing_at(c)
	if id != "" and _interaction_of(id) != "":
		return id
	var below: String = map.thing_at(c + Vector2i(0, 1))
	if below != "" and _interaction_of(below) != "" and not map.is_walkable(c):
		return below
	return ""


func _interaction_of(id: String) -> String:
	for t in def.get("npcs", []) + def.get("objects", []):
		if t["id"] == id:
			return str(t.get("interaction", ""))
	return ""


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
	if dialogue_box.is_open():
		return
	var id := target_at(c)
	if id != "":
		var tc: Vector2i = map.cell_of_thing(id)
		var a: Dictionary = map.approach(player_cell, tc)
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
	return path.is_empty() and _step_t <= 0.0


func _process(delta: float) -> void:
	_walk(delta)
	_follow(delta)


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
		if path.is_empty():
			_set_path([], NO_CELL)
			_arrive()


func _arrive() -> void:
	if target_id == "":
		return
	var id := target_id
	target_id = ""
	var tc: Vector2i = map.cell_of_thing(id)
	if (tc - player_cell).length_squared() != 1:
		return
	player.facing = TownMap.facing_toward(player_cell, tc)
	if actors.has(id) and actors[id].kind == "character":
		actors[id].facing = TownMap.facing_toward(tc, player_cell)
	interact(id)


## Starts an interaction by its data id (from the NPC/object definition).
func interact(id: String) -> void:
	var interaction := _interaction_of(id)
	if interaction == "" or not dialogue.start(interaction):
		return
	dialogue_box.open(dialogue, float(def.get("text_speed", 45)))


func _on_dialogue_closed() -> void:
	if not dialogue.fight_request.is_empty():
		var req: Dictionary = dialogue.fight_request
		dialogue.fight_request = {}
		fight_requested.emit(req)


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
