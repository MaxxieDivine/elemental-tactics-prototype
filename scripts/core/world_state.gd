## World state: which NPCs and objects are on a map right now, where they
## stand and how they look, decided in data by story flags and the time of
## day. Plain data, no Nodes.
##
## Any NPC or object in data/maps/<id>.json may list "states". Each state has
## optional "requires" / "unless" flag lists (same meaning as in dialogue.json),
## an optional "time_of_day" ("night", or a list such as ["day", "night"]),
## and an optional "priority" (default 0). Of the states whose flags match,
## the one with the highest priority wins; on a tie, the one listed first.
## Only that one state applies: its keys (cell, facing, hidden, interaction,
## sprite, shape, pace, mood, stand...) replace the thing's base keys. No
## matching state means the base definition as written. "hidden": true takes
## the thing off the map (no sprite, no blocking, nothing to tap).
extends RefCounted

const StoryFlags = preload("res://scripts/core/story_flags.gd")

## Keys that describe a state's rule rather than the thing itself.
const RULE_KEYS := ["requires", "unless", "time_of_day", "priority", "_comment"]
## The lists in a map definition that can carry states.
const LISTS := ["npcs", "objects"]


## The state that applies to a thing for these flags (and their time of day) ({} when none matches).
static func pick_state(thing: Dictionary, flags) -> Dictionary:
	var best := {}
	var best_p := 0.0
	for s in thing.get("states", []):
		if not flags.meets_rule(s):
			continue
		var p := float(s.get("priority", 0))
		if best.is_empty() or p > best_p:
			best = s
			best_p = p
	return best


## The thing as it is for these flags: its base definition with the winning
## state's keys laid over it. Returns {} when the thing is hidden.
static func resolve_thing(thing: Dictionary, flags) -> Dictionary:
	var out := thing.duplicate(true)
	out.erase("states")
	var s := pick_state(thing, flags)
	for k in s:
		if not RULE_KEYS.has(k):
			out[k] = s[k]
	if bool(out.get("hidden", false)):
		return {}
	out.erase("hidden")
	return out


## A map definition with every NPC/object resolved for these flags (hidden
## ones removed). `flags` may be null: no flags are set.
static func apply(map_def: Dictionary, flags = null) -> Dictionary:
	if flags == null:
		flags = StoryFlags.new()
	var out := map_def.duplicate()
	for list in LISTS:
		var things: Array = []
		for t in map_def.get(list, []):
			var r := resolve_thing(t, flags)
			if not r.is_empty():
				things.append(r)
		out[list] = things
	return out


## Every rule on a map: NPC/object states and trigger zones.
static func rules_of(map_def: Dictionary) -> Array:
	var out: Array = []
	for list in LISTS:
		for t in map_def.get(list, []):
			out.append_array(t.get("states", []))
	out.append_array(map_def.get("triggers", []))
	return out


## Every flag that any state or trigger on this map looks at (sorted), so
## tests can try each combination.
static func flags_used(map_def: Dictionary) -> Array:
	var seen := {}
	for s in rules_of(map_def):
		for f in s.get("requires", []) + s.get("unless", []):
			seen[f] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## True when any state or trigger on this map looks at the time of day.
static func uses_time(map_def: Dictionary) -> bool:
	return rules_of(map_def).any(func(s): return s.has("time_of_day"))
