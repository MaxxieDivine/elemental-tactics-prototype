## Draws the board from its own display copy of the BattleState and replays
## rule events one by one (tweens, flashes, floating numbers, pauses).
## It never decides outcomes: everything comes from the event list.
extends Node2D

const BattleState = preload("res://scripts/core/battle_state.gd")
const GameData = preload("res://scripts/core/game_data.gd")

const CELL := 60.0
const ELEMENT_COLORS := {
	"fire": Color("#ff7a2b"),
	"water": Color("#4a9bff"),
	"lightning": Color("#f7e04a"),
	"steam": Color("#e6eaee"),
	"physical": Color("#ffffff"),
}
const C_FLOOR_A := Color("#2a2e35")
const C_FLOOR_B := Color("#30353d")
const C_WALL := Color("#5d626c")
const C_WATER := Color(0.2, 0.47, 0.95, 0.6)
const C_OIL := Color("#4a3418")
const C_STEAM := Color(0.92, 0.94, 0.96, 0.82)
const C_BARREL := Color("#d8432f")

var disp  # BattleState currently shown
var unit_px: Dictionary = {}  # unit id -> pixel centre
var speed: float = 1.0
var font: Font

# Overlays set by the controller.
var selected_id: int = -1
var move_cells: Array = []
var target_cells: Array = []
var area_cells: Array = []
var area_element: String = "physical"
var path: Array = []
var preview: Dictionary = {}
var intents: Array = []
var highlight_intent_id: int = -1
var show_intents: bool = true

# Playback state.
var hidden_intents: Dictionary = {}
var acting_id: int = -1
var flashes: Array = []
var floaters: Array = []
var shake: float = 0.0
var banner: String = ""
var banner_t: float = 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font


func set_state(s) -> void:
	disp = s.clone()
	unit_px.clear()
	for u in disp.units:
		unit_px[u.id] = center(u.cell)
	hidden_intents.clear()
	acting_id = -1
	queue_redraw()


func center(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5


func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


func _process(delta: float) -> void:
	for f in flashes:
		f["t"] += delta * speed
	flashes = flashes.filter(func(f): return f["t"] < f["dur"])
	for f in floaters:
		f["t"] += delta * speed
	floaters = floaters.filter(func(f): return f["t"] < f["dur"])
	shake = maxf(0.0, shake - delta * 30.0)
	banner_t = maxf(0.0, banner_t - delta * speed)
	queue_redraw()


# =========================================================================
# Event playback
# =========================================================================

func wait(t: float) -> void:
	await get_tree().create_timer(t / speed).timeout


func play(events: Array) -> void:
	for ev in events:
		await _play_event(ev)
	acting_id = -1


func _play_event(ev: Dictionary) -> void:
	match ev["type"]:
		"move":
			var u = disp.unit_by_id(ev["unit"])
			var p: Array = ev["path"]
			for i in range(1, p.size()):
				await _tween_unit(u.id, center(p[i]), 0.09)
			u.cell = p[-1]
		"push":
			var u = disp.unit_by_id(ev["unit"])
			await _tween_unit(u.id, center(ev["to"]), 0.16)
			u.cell = ev["to"]
			shake = 4.0
		"cast":
			var u = disp.unit_by_id(ev["unit"])
			_float(unit_px[u.id] + Vector2(0, -34), ev["name"], Color.WHITE, 16, 0.9)
			_flash([ev["target"]], ev["element"], 0.4)
			await wait(0.3)
		"flash":
			_flash(ev["cells"], ev["element"], 0.45)
			await wait(0.18)
		"damage":
			var u = disp.unit_by_id(ev["unit"])
			u.hp = ev["hp"]
			var col: Color = ELEMENT_COLORS.get(ev["element"], Color.WHITE)
			_float(unit_px[u.id] + Vector2(randf_range(-8, 8), -16), "-%d" % ev["amount"], col, 26, 1.0)
			_flash([u.cell], "damage", 0.25)
			await wait(0.2)
		"death":
			var u = disp.unit_by_id(ev["unit"])
			u.alive = false
			_float(unit_px[u.id], "KO", Color("#ff4444"), 22, 1.0)
			await wait(0.25)
		"status":
			disp.unit_by_id(ev["unit"]).burning = ev["burning"]
		"surface":
			disp.set_surface(ev["cell"], ev["surface"])
			await wait(0.035)
		"terrain":
			disp.set_terrain(ev["cell"], ev["terrain"])
		"barrel_push":
			disp.set_terrain(ev["from"], BattleState.Terrain.FLOOR)
			disp.set_terrain(ev["to"], BattleState.Terrain.BARREL)
			await wait(0.18)
		"explosion":
			var cells: Array = []
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					cells.append(ev["cell"] + Vector2i(dx, dy))
			_flash(cells, "fire", 0.6)
			shake = 10.0
			await wait(0.3)
		"text":
			var col: Color = ELEMENT_COLORS.get(ev["element"], Color.WHITE)
			_float(center(ev["cell"]) + Vector2(0, -26), ev["text"], col, 20, 1.1)
			await wait(0.1)
		"pause":
			await wait(ev["time"])
		"phase":
			banner = "ENEMY PHASE" if ev["phase"] == "enemy" else "ROUND %d - YOUR TURN" % ev["round"]
			banner_t = 1.0
			await wait(0.75)
		"enemy_turn":
			acting_id = ev["unit"]
			hidden_intents[ev["unit"]] = true
			await wait(0.25)


func _tween_unit(id: int, to: Vector2, t: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: Vector2): unit_px[id] = v, unit_px[id], to, t / speed)
	await tw.finished


func _flash(cells: Array, element: String, dur: float) -> void:
	var col: Color = Color("#ff3b3b") if element == "damage" else ELEMENT_COLORS.get(element, Color.WHITE)
	flashes.append({"cells": cells, "color": col, "t": 0.0, "dur": dur})


func _float(pos: Vector2, text: String, col: Color, size: int, dur: float) -> void:
	floaters.append({"pos": pos, "text": text, "color": col, "size": size, "t": 0.0, "dur": dur})


# =========================================================================
# Drawing
# =========================================================================

func _draw() -> void:
	if disp == null:
		return
	if shake > 0.0:
		draw_set_transform(Vector2(randf_range(-shake, shake), randf_range(-shake, shake)))
	_draw_tiles()
	_draw_overlays()
	if show_intents:
		_draw_intents()
	_draw_units()
	_draw_preview()
	_draw_effects()
	draw_set_transform(Vector2.ZERO)
	_draw_banner()


func _rect(c: Vector2i, inset: float = 0.0) -> Rect2:
	return Rect2(Vector2(c) * CELL + Vector2(inset, inset), Vector2(CELL - inset * 2, CELL - inset * 2))


func _text(pos: Vector2, text: String, size: int, col: Color, outline: int = 4) -> void:
	var w := 400.0
	var p := pos + Vector2(-w * 0.5, size * 0.35)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, outline, Color(0, 0, 0, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _draw_tiles() -> void:
	for y in disp.height:
		for x in disp.width:
			var c := Vector2i(x, y)
			var r := _rect(c)
			draw_rect(r, C_FLOOR_A if (x + y) % 2 == 0 else C_FLOOR_B)
			match disp.get_surface(c):
				BattleState.Surface.WATER:
					draw_rect(_rect(c, 2), C_WATER)
					draw_line(r.position + Vector2(14, 36), r.position + Vector2(26, 32), Color(1, 1, 1, 0.35), 2)
					draw_line(r.position + Vector2(32, 26), r.position + Vector2(44, 22), Color(1, 1, 1, 0.35), 2)
				BattleState.Surface.OIL:
					draw_rect(_rect(c, 2), C_OIL)
					draw_circle(r.position + Vector2(20, 22), 6, Color("#6b4a22"))
					draw_circle(r.position + Vector2(40, 40), 4, Color("#6b4a22"))
				BattleState.Surface.STEAM:
					draw_rect(_rect(c, 1), C_STEAM)
					draw_circle(r.position + Vector2(20, 24), 10, Color(1, 1, 1, 0.6))
					draw_circle(r.position + Vector2(38, 34), 12, Color(1, 1, 1, 0.6))
			match disp.get_terrain(c):
				BattleState.Terrain.WALL:
					draw_rect(r, C_WALL)
					draw_rect(_rect(c, 6), C_WALL.darkened(0.25))
				BattleState.Terrain.BARREL:
					draw_circle(center(c), 19, C_BARREL)
					draw_arc(center(c), 19, 0, TAU, 24, Color("#ffd166"), 3)
					_text(center(c), "TNT", 13, Color("#ffd166"), 3)
			draw_rect(r, Color(0, 0, 0, 0.25), false, 1.0)


func _draw_overlays() -> void:
	for c in move_cells:
		draw_rect(_rect(c, 3), Color(0.3, 0.65, 1.0, 0.22))
		draw_rect(_rect(c, 3), Color(0.4, 0.75, 1.0, 0.6), false, 1.5)
	for c in target_cells:
		draw_rect(_rect(c, 4), Color(1.0, 0.85, 0.3, 0.12))
		draw_rect(_rect(c, 4), Color(1.0, 0.85, 0.3, 0.7), false, 1.5)
	var acol: Color = ELEMENT_COLORS.get(area_element, Color.WHITE)
	for c in area_cells:
		draw_rect(_rect(c, 2), Color(acol, 0.35))
		draw_rect(_rect(c, 2), acol, false, 2.5)
	if path.size() > 1:
		var pts := PackedVector2Array()
		for c in path:
			pts.append(center(c))
		draw_polyline(pts, Color(0.6, 0.85, 1.0, 0.9), 4.0)
		draw_circle(pts[-1], 7, Color(0.6, 0.85, 1.0))


func _draw_intents() -> void:
	var per_target: Dictionary = {}  # stack badges when several enemies aim at one tile
	for it in intents:
		if hidden_intents.has(it["id"]):
			continue
		var u = disp.unit_by_id(it["id"])
		if u == null or not u.alive:
			continue
		var hl: bool = it["id"] == highlight_intent_id
		var col: Color = Color(GameData.enemy(u.type_id)["color"]).lightened(0.25)
		var p: Array = it["path"]
		if p.size() > 1:
			var pts := PackedVector2Array()
			for c in p:
				pts.append(center(c))
			draw_polyline(pts, Color(col, 0.85 if hl else 0.5), 5.0 if hl else 3.0)
			draw_arc(pts[-1], 12, 0, TAU, 20, Color(col, 0.9), 2.0)
		if it["has_target"]:
			var t: Vector2i = it["target"]
			var tc := center(t)
			var ok: bool = it["attack_ok"]
			var red := Color("#ff3b3b") if ok else Color(0.6, 0.6, 0.6)
			var from := center(it["dest"])
			_dashed(from, tc, Color(red, 0.8 if hl else 0.5), 2.5 if hl else 1.5)
			draw_rect(_rect(t, 6), Color(red, 0.18 if ok else 0.08))
			draw_rect(_rect(t, 6), red, false, 3.0 if hl else 2.0)
			draw_line(tc + Vector2(-10, -10), tc + Vector2(10, 10), red, 2.5)
			draw_line(tc + Vector2(-10, 10), tc + Vector2(10, -10), red, 2.5)
			# Order badge in the target tile's corner.
			var k: int = per_target.get(t, 0)
			per_target[t] = k + 1
			var bp := _rect(t).position + Vector2(13 + 17 * k, 13)
			draw_circle(bp, 9, red)
			_text(bp, str(it["order"]), 13, Color.BLACK, 0)
			if not ok:
				_text(tc + Vector2(0, 18), "blocked", 11, Color(0.8, 0.8, 0.8), 3)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var d := 0.0
	while d < len:
		draw_line(a + dir * d, a + dir * minf(d + 7.0, len), col, w)
		d += 13.0


func _draw_units() -> void:
	for u in disp.units:
		if not u.alive:
			continue
		var p: Vector2 = unit_px[u.id]
		if u.team == "hero":
			var col := Color(GameData.hero(u.type_id)["color"])
			var done: bool = u.is_done() and disp.phase == "player"
			if done:
				col = col.darkened(0.45)
			if u.id == selected_id:
				draw_arc(p, 25, 0, TAU, 32, Color.WHITE, 3.0)
			draw_circle(p, 20, col)
			draw_arc(p, 20, 0, TAU, 32, Color(0, 0, 0, 0.6), 2.0)
			_text(p, u.name.substr(0, 1), 20, Color.BLACK if not done else Color(0.15, 0.15, 0.15), 0)
		else:
			var d := GameData.enemy(u.type_id)
			var col := Color(d["color"])
			if u.id == acting_id:
				draw_arc(p, 27, 0, TAU, 32, Color("#ffdd55"), 3.0)
			if d["shape"] == "diamond":
				var pts := PackedVector2Array([p + Vector2(0, -22), p + Vector2(22, 0), p + Vector2(0, 22), p + Vector2(-22, 0)])
				draw_colored_polygon(pts, col)
				pts.append(pts[0])
				draw_polyline(pts, Color(0, 0, 0, 0.7), 2.0)
			else:
				draw_rect(Rect2(p - Vector2(18, 18), Vector2(36, 36)), col)
				draw_rect(Rect2(p - Vector2(18, 18), Vector2(36, 36)), Color(0, 0, 0, 0.7), false, 2.0)
			_text(p, u.name.substr(0, 1), 18, Color.WHITE, 3)
			draw_circle(p + Vector2(-21, -21), 8, Color(0.1, 0.1, 0.1))
			_text(p + Vector2(-21, -21), str(u.order), 11, Color.WHITE, 0)
		# HP pips.
		var w := 44.0
		var pip: float = w / u.max_hp
		var base := p + Vector2(-w * 0.5, 22)
		draw_rect(Rect2(base - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.8))
		for i in u.max_hp:
			var filled: bool = i < u.hp
			var c := Color("#5ee35e") if u.team == "hero" else Color("#ff5a5a")
			draw_rect(Rect2(base + Vector2(i * pip + 0.5, 0), Vector2(pip - 1.0, 5)), c if filled else Color(0.25, 0.25, 0.25))
		if u.burning > 0:
			var fp := p + Vector2(20, -20)
			draw_colored_polygon(PackedVector2Array([fp + Vector2(-6, 6), fp + Vector2(0, -9), fp + Vector2(6, 6)]), ELEMENT_COLORS["fire"])
			draw_circle(fp + Vector2(0, 3), 4, Color("#ffd166"))


func _draw_preview() -> void:
	if preview.is_empty():
		return
	for c in preview.get("cells", []):
		draw_rect(_rect(c, 8), Color(1, 0.6, 0.2, 0.9), false, 2.0)
	var dmg: Dictionary = preview.get("damage", {})
	for id in dmg:
		var u = disp.unit_by_id(id)
		if u == null or not u.alive:
			continue
		var p: Vector2 = unit_px[id]
		var dead: bool = preview.get("deaths", {}).has(id)
		var label := "-%d" % dmg[id] + (" KO" if dead else "")
		var ally: bool = u.team == "hero"
		var col := Color("#ff4d4d") if dead else (Color("#ff9f43") if ally else Color("#ffe066"))
		draw_rect(Rect2(p - Vector2(28, 28), Vector2(56, 56)), col, false, 2.5)
		_text(p + Vector2(0, -36), label, 18, col)
	for id in preview.get("burn", {}):
		var u = disp.unit_by_id(id)
		if u != null and u.alive and not preview.get("deaths", {}).has(id):
			_text(unit_px[id] + Vector2(0, 40), "burn", 12, ELEMENT_COLORS["fire"], 3)
	for id in preview.get("moves", {}):
		var u = disp.unit_by_id(id)
		if u != null:
			var to: Vector2 = center(preview["moves"][id])
			draw_line(unit_px[id], to, Color(1, 1, 1, 0.8), 3.0)
			draw_arc(to, 16, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)


func _draw_effects() -> void:
	for f in flashes:
		var a: float = 1.0 - f["t"] / f["dur"]
		for c in f["cells"]:
			if disp.in_bounds(c):
				draw_rect(_rect(c, 1), Color(f["color"], 0.55 * a))
	for f in floaters:
		var k: float = f["t"] / f["dur"]
		var pos: Vector2 = f["pos"] + Vector2(0, -28.0 * k)
		var col: Color = f["color"]
		col.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
		_text(pos, f["text"], f["size"], col)


func _draw_banner() -> void:
	if banner_t <= 0.0:
		return
	var a := minf(1.0, banner_t * 3.0)
	var r := Rect2(Vector2(0, disp.height * CELL * 0.5 - 32), Vector2(disp.width * CELL, 64))
	draw_rect(r, Color(0, 0, 0, 0.7 * a))
	_text(r.get_center(), banner, 30, Color(1, 1, 1, a))
