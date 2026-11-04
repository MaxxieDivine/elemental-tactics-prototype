## Loads the editable JSON data in res://data/ and caches it.
## All tuning numbers live in those files, not in code.
extends RefCounted

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


static func ability(id: String) -> Dictionary:
	return get_json("abilities")[id]


static func hero(id: String) -> Dictionary:
	return get_json("heroes")[id]


static func enemy(id: String) -> Dictionary:
	return get_json("enemies")[id]


static func rule(key: String) -> int:
	return int(get_json("rules")[key])


static func level() -> Dictionary:
	return get_json("level")
