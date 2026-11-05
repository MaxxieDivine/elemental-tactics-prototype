## Plays one interaction's dialogue from data/dialogue.json. Picks the first
## entry whose flag requirements are met, steps through its lines, and on the
## last line applies its effects: set_flags, and an optional fight request.
## Plain data, no Nodes: the dialogue box only shows what this says.
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

var flags  # StoryFlags
var interaction_id: String = ""
var entry: Dictionary = {}
var index: int = -1
var finished: bool = true
## Set when a finished entry asks for a fight: {"encounter": id, "win_flags": [...]}.
var fight_request: Dictionary = {}


func _init(story_flags) -> void:
	flags = story_flags


static func has_interaction(id: String) -> bool:
	return GameData.get_json("dialogue").has(id)


## The entry that would play for this interaction now ({} if none).
static func select_entry(id: String, story_flags) -> Dictionary:
	for e in GameData.get_json("dialogue").get(id, []):
		if story_flags.meets(e.get("requires", []), e.get("unless", [])):
			return e
	return {}


## Starts an interaction. Returns false (and does nothing) if no entry plays.
func start(id: String) -> bool:
	interaction_id = id
	fight_request = {}
	entry = select_entry(id, flags)
	if entry.is_empty() or entry.get("lines", []).is_empty():
		if not entry.is_empty():
			_finish()  # effects-only entry
		entry = {}
		finished = true
		push_warning("Interaction '%s' has no dialogue to play." % id)
		return false
	index = 0
	finished = false
	return true


## The current line: {"speaker", "name", "text", "portrait", "color"}.
func line() -> Dictionary:
	if finished:
		return {}
	var l: Dictionary = entry["lines"][index]
	var speaker: String = l.get("speaker", "")
	var c: Dictionary = GameData.get_json("characters").get(speaker, {})
	return {
		"speaker": speaker,
		"name": str(l.get("name", c.get("name", speaker.capitalize()))),
		"text": str(l.get("text", "")),
		"portrait": str(l.get("portrait", c.get("portrait", ""))),
		"color": str(c.get("color", "#888888")),
	}


## Moves to the next line. Returns true while there is a line to show;
## returns false once the entry is over (its effects have been applied).
func advance() -> bool:
	if finished:
		return false
	index += 1
	if index < entry["lines"].size():
		return true
	_finish()
	return false


func _finish() -> void:
	finished = true
	for f in entry.get("set_flags", []):
		flags.set_flag(f)
	if entry.has("start_fight"):
		fight_request = {"encounter": str(entry["start_fight"]), "win_flags": entry.get("win_flags", []).duplicate()}
