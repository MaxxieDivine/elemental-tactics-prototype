## Loads the editable JSON data in res://data/ and caches it.
## All tuning numbers, terrain interactions and the encounter live there.
extends RefCounted

const DEFAULT_ENCOUNTER := "first_fight"

static var _cache: Dictionary = {}


static func get_json(file_name: String) -> Variant:
	if not _cache.has(file_name):
		var path := "res://data/%s.json" % file_name
		var f := FileAccess.open(path, FileAccess.READ)
		assert(f != null, "Missing data file: " + path)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		assert(parsed != null, "Invalid JSON in " + path)
		_cache[file_name] = parsed
	return _cache[file_name]


## A value from data/settings.json (developer switches), or `fallback`.
static func setting(key: String, fallback: Variant = null) -> Variant:
	return get_json("settings").get(key, fallback)


static func ability(id: String) -> Dictionary:
	return get_json("abilities")[id]


## A hero's data. A hero with "character" (a data/characters.json id) takes
## its name, colour and sprite key from that character unless it sets its own,
## so a town character fights under the same name and look.
static func hero(id: String) -> Dictionary:
	var d: Dictionary = get_json("heroes")[id]
	if not d.has("character"):
		return d
	var out := d.duplicate()
	var c: Dictionary = get_json("characters").get(str(d["character"]), {})
	for k in ["name", "color", "sprite"]:
		if not out.has(k) and c.has(k):
			out[k] = c[k]
	return out


static func enemy(id: String) -> Dictionary:
	return get_json("enemies")[id]


static func rule(key: String) -> int:
	return int(get_json("rules")[key])


static func encounter(id: String = DEFAULT_ENCOUNTER) -> Dictionary:
	return get_json("encounters")[id]


static func tile(name: String) -> Dictionary:
	return get_json("terrain")["tiles"][name]


static func surface(name: String) -> Dictionary:
	return get_json("terrain")["surfaces"][name]


## What happens when an element touches a surface ({} if nothing).
## Two dictionaries merged: `over`'s keys replace `base`'s, and nested
## dictionaries merge the same way (an encounter's terrain overrides).
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k] if not (over[k] is Dictionary or over[k] is Array) else over[k].duplicate(true)
	return out


static func reaction(element: String, surface_name: String) -> Dictionary:
	return get_json("terrain")["reactions"].get(element, {}).get(surface_name, {})
