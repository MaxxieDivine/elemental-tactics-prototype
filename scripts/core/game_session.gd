## Everything that outlives one screen: story flags, where the player stood in
## town, and the fight in progress. Plain data, no Nodes. The app keeps one
## in GameSession.current.
extends RefCounted

const StoryFlags = preload("res://scripts/core/story_flags.gd")
const GameData = preload("res://scripts/core/game_data.gd")

static var current

var flags = StoryFlags.new()
## Where the player was in town: {"cell": Vector2i, "facing": String}. Empty
## until the player has been in town.
var town_spot: Dictionary = {}
## The fight in progress, if any: {"encounter": id, "win_flags": [...], "from_town": bool}.
var fight: Dictionary = {}
var last_result: String = ""  # "won", "lost" or ""


static func get_current():
	if current == null:
		current = load("res://scripts/core/game_session.gd").new()
	return current


## Remembers where the player stands and records the fight to run.
func begin_fight(request: Dictionary, cell: Vector2i, facing: String) -> void:
	town_spot = {"cell": cell, "facing": facing}
	fight = request.duplicate(true)
	fight["from_town"] = true


## A fight started from the start screen (no town to return to).
func begin_direct_fight(encounter_id: String = GameData.DEFAULT_ENCOUNTER) -> void:
	fight = {"encounter": encounter_id, "win_flags": [], "from_town": false}


func encounter_id() -> String:
	return str(fight.get("encounter", GameData.DEFAULT_ENCOUNTER))


## Ends the fight. A win sets its win flags; a loss sets nothing, so the
## same door can be tried again. Returns true if play should go back to town.
func end_fight(won: bool) -> bool:
	var to_town: bool = fight.get("from_town", false)
	last_result = "won" if won else "lost"
	if won:
		for f in fight.get("win_flags", []):
			flags.set_flag(f)
	fight = {}
	return to_town
