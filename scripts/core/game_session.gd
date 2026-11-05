## Everything that outlives one screen or map: story flags, where the player
## stands in the world (map, cell, facing), and the fight in progress. Plain
## data, no Nodes. The app keeps one in GameSession.current.
extends RefCounted

const StoryFlags = preload("res://scripts/core/story_flags.gd")
const GameData = preload("res://scripts/core/game_data.gd")
const TownMap = preload("res://scripts/core/town_map.gd")

static var current

var flags = StoryFlags.new()
## Where the player is: {"map": String, "cell": Vector2i, "facing": String}.
## Empty until the player has been in town (then the data start is used).
var town_spot: Dictionary = {}
## The fight in progress, if any: {"encounter": id, "win_flags": [...], "from_town": bool}.
var fight: Dictionary = {}
var last_result: String = ""  # "won", "lost" or ""


static func get_current():
	if current == null:
		current = load("res://scripts/core/game_session.gd").new()
	return current


## Where play starts in the world, from data/town.json "player".
static func start_spot() -> Dictionary:
	var p: Dictionary = TownMap.world()["player"]
	return {"map": str(p["map"]), "cell": TownMap.cell_of(p["cell"]), "facing": str(p.get("facing", "down"))}


## Where the player is now (the data start if they have not been anywhere).
func spot() -> Dictionary:
	return town_spot if not town_spot.is_empty() else start_spot()


## Remembers where the player stands (any map).
func set_spot(map_id: String, cell: Vector2i, facing: String) -> void:
	town_spot = {"map": map_id, "cell": cell, "facing": facing}


## Goes through an exit (its data from a map's "exits"): the player now
## stands at its arrival cell on its target map. Story flags are untouched.
## Returns the new spot.
func go_through(exit: Dictionary) -> Dictionary:
	var a := TownMap.arrival(exit)
	set_spot(a["map"], a["cell"], a["facing"])
	return town_spot


## Remembers where the player stands and records the fight to run. After
## the fight the player comes back to exactly this spot.
func begin_fight(request: Dictionary, from_spot: Dictionary) -> void:
	town_spot = from_spot.duplicate()
	fight = request.duplicate(true)
	fight["from_town"] = true


## A fight started from the start screen (no town to return to).
func begin_direct_fight(encounter_id: String = GameData.DEFAULT_ENCOUNTER) -> void:
	fight = {"encounter": encounter_id, "win_flags": [], "from_town": false}


func encounter_id() -> String:
	return str(fight.get("encounter", GameData.DEFAULT_ENCOUNTER))


## Where the encounter sends the player after a win or a loss: its data
## "return": {"won": {"map", "cell", "facing"}, "lost": {...}} ({} when it
## names none: back to where the fight was launched).
static func return_spot(encounter: String, won: bool) -> Dictionary:
	var r: Dictionary = GameData.get_json("encounters").get(encounter, {}).get("return", {})
	var d: Dictionary = r.get("won" if won else "lost", {})
	if d.is_empty():
		return {}
	return {"map": str(d["map"]), "cell": TownMap.cell_of(d["cell"]), "facing": str(d.get("facing", "down"))}


## Ends the fight. A win sets its win flags; a loss sets nothing, so the
## same fight can be tried again. A town fight puts the player at the
## encounter's return spot for that result, else back where it was launched.
## Returns true if play should go back to town.
func end_fight(won: bool) -> bool:
	var to_town: bool = fight.get("from_town", false)
	last_result = "won" if won else "lost"
	if won:
		for f in fight.get("win_flags", []):
			flags.set_flag(f)
	if to_town:
		var back := return_spot(encounter_id(), won)
		if not back.is_empty() and not TownMap.map_def(back["map"]).is_empty():
			town_spot = back
	fight = {}
	return to_town


## The start-screen shortcuts in data/settings.json "shortcuts" that are
## switched on ("enabled": true). Each: {"label", "flags", "time_of_day",
## "map", "cell", "facing"}.
static func shortcuts() -> Array:
	return GameData.setting("shortcuts", []).filter(func(s): return bool(s.get("enabled", false)))


## A fresh story set up by a shortcut: its flags, time of day and spot.
static func from_shortcut(sc: Dictionary):
	var s = load("res://scripts/core/game_session.gd").new()
	for f in sc.get("flags", []):
		s.flags.set_flag(str(f))
	if sc.has("time_of_day"):
		s.flags.set_time_of_day(str(sc["time_of_day"]))
	for t in sc.get("ran", []):
		s.flags.mark_ran(str(t))
	s.set_spot(str(sc["map"]), TownMap.cell_of(sc["cell"]), str(sc.get("facing", "down")))
	return s
