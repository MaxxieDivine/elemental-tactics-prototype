## Asset catalog: key lookup and placeholder fallback.
extends "res://tests/test_base.gd"

const AssetCatalog = preload("res://scripts/core/asset_catalog.gd")


func test_listed_keys_resolve_to_their_data_path() -> void:
	var paths: Dictionary = GameData.get_json("assets")["paths"]
	for key in paths:
		eq(AssetCatalog.path(key), paths[key], "path for " + key)


func test_unlisted_keys_use_the_fallback_folder() -> void:
	var dir: String = GameData.get_json("assets")["fallback_dir"]
	eq(AssetCatalog.path("hero_tide"), dir + "hero_tide.png", "fight sprite keys keep the art/<key>.png convention")
	eq(AssetCatalog.path(""), "", "empty key has no path")


func test_missing_asset_gives_placeholder_and_one_warning() -> void:
	AssetCatalog.clear_cache()
	var key := "test.definitely_missing"
	check(AssetCatalog.try_texture(key) == null, "try_texture returns null for a missing file")
	var tex := AssetCatalog.texture(key)
	check(tex != null, "texture() never returns null")
	check(AssetCatalog.is_placeholder(tex), "missing asset uses the placeholder")
	eq(tex.get_size(), Vector2(16, 16), "placeholder is one 16x16 tile")
	eq(AssetCatalog.warned.count(key), 1, "missing asset warns exactly once")
	AssetCatalog.texture(key)
	eq(AssetCatalog.warned.count(key), 1, "no repeat warning for the same key")
	check(not AssetCatalog.exists(key), "exists() is false for a missing file")


func test_quiet_lookup_does_not_warn() -> void:
	AssetCatalog.clear_cache()
	check(AssetCatalog.try_texture("test.quiet_missing", false) == null, "quiet lookup returns null")
	check(not AssetCatalog.warned.has("test.quiet_missing"), "quiet lookup does not warn")


func test_existing_file_loads_by_key() -> void:
	# Write a real PNG to user:// and point a temporary key at it.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var p := "user://test_asset.png"
	img.save_png(p)
	AssetCatalog.clear_cache()
	GameData.get_json("assets")["paths"]["test.real"] = p
	var tex := AssetCatalog.texture("test.real")
	check(tex != null and not AssetCatalog.is_placeholder(tex), "existing file loads")
	eq(tex.get_size(), Vector2(4, 4), "loaded the real image")
	check(AssetCatalog.warned.is_empty(), "no warning for an existing file")
	GameData.get_json("assets")["paths"].erase("test.real")
	AssetCatalog.clear_cache()
