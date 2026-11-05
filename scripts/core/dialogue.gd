## Plays one interaction's dialogue from data/dialogue.json. Picks the first
## entry whose flag requirements are met, steps through its lines, and on the
## last line applies its effects: set_flags, and an optional fight request.
## Each line's action-button label comes from data too: the line's own
## "button", else the "_buttons" defaults ("next" / "close").
## Plain data, no Nodes: the dialogue box only shows what this says.
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

## Used only if data/dialogue.json has no "_buttons" block.
const DEFAULT_BUTTONS := {"next": "Next", "close": "Close", "skip": "Skip"}

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
	return not id.begins_with("_") and GameData.get_json("dialogue").has(id)


## A default button label from data ("next", "close" or "skip").
static func default_button(kind: String) -> String:
	var b: Dictionary = GameData.get_json("dialogue").get("_buttons", {})
	return str(b.get(kind, DEFAULT_BUTTONS.get(kind, kind.capitalize())))


## The entry that would play for this interaction now ({} if none).
static func select_entry(id: String, story_flags) -> Dictionary:
	if id.begins_with("_"):
		return {}
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


func is_last_line() -> bool:
	return not finished and index >= entry["lines"].size() - 1


## The current line: {"speaker", "name", "initials", "text", "portrait",
## "color", "button"}. "button" is the label for the action that ends this
## line; "initials" is what a placeholder portrait shows (see initials_of).
func line() -> Dictionary:
	if finished:
		return {}
	var l: Dictionary = entry["lines"][index]
	var speaker: String = l.get("speaker", "")
	var c: Dictionary = GameData.get_json("characters").get(speaker, {})
	var display: String = str(l.get("name", c.get("name", speaker.capitalize())))
	return {
		"speaker": speaker,
		"name": display,
		"initials": initials_of(display),
		"text": str(l.get("text", "")),
		"portrait": str(l.get("portrait", c.get("portrait", ""))),
		"color": str(c.get("color", "#888888")),
		"button": str(l.get("button", default_button("close" if is_last_line() else "next"))),
	}


## What a placeholder portrait shows for a display name: a short name (up
## to 3 characters, like "???") in full, else its first letter.
static func initials_of(display_name: String) -> String:
	if display_name.length() <= 3:
		return display_name
	return display_name.left(1).to_upper()


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
