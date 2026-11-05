## Asset catalog: game code and content refer to art by key (for example
## "agador.portrait.neutral" or "town.tiles"), never by file path.
## data/assets.json maps keys to paths. Keys that are not listed fall back to
## the convention res://art/<key>.png, so the fight's sprite keys keep working.
##
## texture(key) never returns null: a missing asset logs one warning and gives
## an obvious magenta/black checker placeholder. try_texture(key) returns null
## instead, for callers that draw their own placeholder (portraits, the fight).
extends RefCounted

const GameData = preload("res://scripts/core/game_data.gd")

static var _textures: Dictionary = {}  # key -> Texture2D or null
static var warned: Array = []  # keys we already warned about (read by tests)
static var _placeholder: Texture2D


## The file path for a key ("" if the key is empty).
static func path(key: String) -> String:
	if key == "":
		return ""
	var data: Dictionary = GameData.get_json("assets")
	var paths: Dictionary = data.get("paths", {})
	if paths.has(key):
		return str(paths[key])
	return "%s%s.png" % [str(data.get("fallback_dir", "res://art/")), key]


## True when the key resolves to a file that exists.
static func exists(key: String) -> bool:
	return try_texture(key, false) != null


## The texture for a key, or null when the file is missing.
## warn: log a warning (once per key) when it is missing.
static func try_texture(key: String, warn: bool = true) -> Texture2D:
	if key == "":
		return null
	if not _textures.has(key):
		_textures[key] = _load(path(key))
	var tex: Texture2D = _textures[key]
	if tex == null and warn and not warned.has(key):
		warned.append(key)
		push_warning("Asset '%s' is missing (expected at %s). Using a placeholder." % [key, path(key)])
	return tex


## The texture for a key, or the checker placeholder (with a warning).
static func texture(key: String) -> Texture2D:
	var tex := try_texture(key, true)
	return tex if tex != null else placeholder()


static func is_placeholder(tex: Texture2D) -> bool:
	return tex != null and tex == _placeholder


## A loud 16x16 magenta/black checker that is easy to spot on screen.
static func placeholder() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color.MAGENTA if ((x >> 2) + (y >> 2)) % 2 == 0 else Color.BLACK)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


## Forget loaded textures (tests, or after swapping files).
static func clear_cache() -> void:
	_textures.clear()
	warned.clear()


static func _load(p: String) -> Texture2D:
	if p == "":
		return null
	if ResourceLoader.exists(p):
		var res: Resource = load(p)
		if res is Texture2D:
			return res
	# A PNG dropped in without being imported yet (desktop runs only).
	if p.get_extension().to_lower() == "png" and FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null
