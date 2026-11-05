## Story memory: simple named flags such as "read_letter", story values such
## as the time of day, and which run-once triggers have already run.
## Plain data, no Nodes.
##
## Rules in data (dialogue entries, NPC/object states, trigger zones) are
## checked with meets_rule(): "requires" / "unless" flag lists, plus an
## optional "time_of_day" (one value, or a list of allowed values).
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

## Story values a rule can test, by the key a rule uses for them.
const VALUE_KEYS := ["time_of_day"]
## Used only if data/town.json has no "time_of_day" block.
const DEFAULT_TIMES := ["day", "night"]

var flags: Dictionary = {}  # name -> true
var values: Dictionary = {}  # story value name -> String (unset: its data start)
var ran: Dictionary = {}  # run-once trigger id -> true


func set_flag(name: String) -> void:
	flags[name] = true


func clear_flag(name: String) -> void:
	flags.erase(name)


func has(name: String) -> bool:
	return flags.has(name)


## True when every flag in `requires` is set and none in `unless` is.
func meets(requires: Array, unless: Array = []) -> bool:
	return requires.all(func(f): return has(f)) and not unless.any(func(f): return has(f))


## True when a data rule matches: its "requires" / "unless" flags and, if
## it names one, its "time_of_day" (a value or a list of values).
func meets_rule(rule: Dictionary) -> bool:
	if not meets(rule.get("requires", []), rule.get("unless", [])):
		return false
	for key in VALUE_KEYS:
		if rule.has(key):
			var want = rule[key]
			var allowed: Array = want if want is Array else [want]
			if not allowed.has(get_value(key)):
				return false
	return true


func names() -> Array:
	var out: Array = flags.keys()
	out.sort()
	return out


# --- Time of day -------------------------------------------------------------------

## The times of day the story knows, from data/town.json "time_of_day".
static func times() -> Array:
	return GameData.get_json("town").get("time_of_day", {}).get("values", DEFAULT_TIMES)


## The time of day a new story starts at (data/town.json "time_of_day").
static func start_time() -> String:
	return str(GameData.get_json("town").get("time_of_day", {}).get("start", times()[0]))


## A story value ("time_of_day"); unset values give their data start.
func get_value(name: String) -> String:
	if values.has(name):
		return values[name]
	return start_time() if name == "time_of_day" else ""


func time_of_day() -> String:
	return get_value("time_of_day")


## Changes the time of day (only story events call this). Unknown values
## are refused with a warning. Returns true if the time changed.
func set_time_of_day(t: String) -> bool:
	if not times().has(t):
		push_warning("Unknown time of day '%s' (known: %s)." % [t, str(times())])
		return false
	var changed := t != time_of_day()
	values["time_of_day"] = t
	return changed


# --- Run-once triggers -----------------------------------------------------------

func mark_ran(trigger_id: String) -> void:
	ran[trigger_id] = true


func has_run(trigger_id: String) -> bool:
	return ran.has(trigger_id)
