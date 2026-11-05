## How the maps connect, for tests: exits, dialogue steps that move the
## player to another map ("then": {"go_to", "place"}), and the spots fights
## send the player back to (an encounter's "return"). Static helpers only.
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")
const TownMap = preload("res://scripts/core/town_map.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")


static func map_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/maps/"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## Every interaction a map can play: its NPCs'/objects' (in any state) and
## its trigger zones'.
static func interactions_on(map_id: String) -> Array:
	var d: Dictionary = TownMap.map_def(map_id)
	var out: Array = []
	for list in ["npcs", "objects"]:
		for t in d.get(list, []):
			for i in [t.get("interaction", "")] + t.get("states", []).map(func(s): return s.get("interaction", "")):
				if str(i) != "" and not out.has(str(i)):
					out.append(str(i))
	for t in d.get("triggers", []):
		if not out.has(str(t["interaction"])):
			out.append(str(t["interaction"]))
	return out


## An interaction's dialogue entries: all of them, or (with flags) only the
## one that plays now.
static func entries(interaction: String, flags = null) -> Array:
	if flags == null:
		return GameData.get_json("dialogue").get(interaction, [])
	var e := Dialogue.select_entry(interaction, flags)
	return [] if e.is_empty() else [e]


## The "go_to" steps in an interaction's dialogue: [{"map", "cell", "facing"}].
static func go_tos(interaction: String, flags = null) -> Array:
	var out: Array = []
	for e in entries(interaction, flags):
		for l in e.get("lines", []):
			var st: Dictionary = l.get("then", {})
			if st.has("go_to"):
				out.append({"map": str(st["go_to"]), "cell": TownMap.cell_of(st["place"]), "facing": str(st.get("facing", "down"))})
	return out


## Where the player can go from a map: [{"map", "cell", "facing", "via"}].
## With story flags, only what those flags allow right now (exits always).
static func links_from(map_id: String, flags = null) -> Array:
	var out: Array = []
	for e in TownMap.map_def(map_id).get("exits", []):
		var a := TownMap.arrival(e)
		a["via"] = "exit " + str(e["id"])
		out.append(a)
	for i in interactions_on(map_id):
		for g in go_tos(i, flags):
			g["via"] = "dialogue " + i
			out.append(g)
		for e in entries(i, flags):
			if e.has("start_fight"):
				for won in [true, false]:
					var r := GameSession.return_spot(str(e["start_fight"]), won)
					if not r.is_empty():
						r["via"] = "fight %s (%s)" % [e["start_fight"], "won" if won else "lost"]
						out.append(r)
	return out


## Every cell the player can arrive at on a map: the story start, and every
## link (exit, dialogue step, fight return) into it.
static func arrivals(map_id: String) -> Array:
	var out: Array = []
	var start: Dictionary = GameSession.start_spot()
	if start["map"] == map_id:
		out.append(start["cell"])
	for other in map_ids():
		for l in links_from(other):
			if l["map"] == map_id and not out.has(l["cell"]):
				out.append(l["cell"])
	for sc in GameData.setting("shortcuts", []):
		if str(sc["map"]) == map_id and not out.has(TownMap.cell_of(sc["cell"])):
			out.append(TownMap.cell_of(sc["cell"]))
	return out


## Maps reachable from the story start through any link (with flags: the
## links those flags allow).
static func reachable_maps(flags = null) -> Dictionary:
	var seen := {GameSession.start_spot()["map"]: true}
	var queue: Array = seen.keys()
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for l in links_from(id, flags):
			if not seen.has(l["map"]):
				seen[l["map"]] = true
				queue.append(l["map"])
	return seen
