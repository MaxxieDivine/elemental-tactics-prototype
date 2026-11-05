## UI text that comes from data: dialogue button labels, glyph coverage of
## the default font, and the fight's tile debug text switch.
extends "res://tests/test_base.gd"

const StoryFlags = preload("res://scripts/core/story_flags.gd")
const Dialogue = preload("res://scripts/core/dialogue.gd")
const FightMain = preload("res://scripts/view/main.gd")


func _all_lines() -> Array:
	var out: Array = []
	var dlg: Dictionary = GameData.get_json("dialogue")
	for id in dlg:
		if id.begins_with("_"):
			continue
		for e in dlg[id]:
			out.append_array(e.get("lines", []))
	return out


func test_default_button_labels_come_from_data() -> void:
	var b: Dictionary = GameData.get_json("dialogue")["_buttons"]
	eq(Dialogue.default_button("next"), b["next"], "Next label from data")
	eq(Dialogue.default_button("close"), b["close"], "Close label from data")
	eq(Dialogue.default_button("skip"), b["skip"], "Skip label from data")
	eq(b["next"], "Next", "default Next label")
	eq(b["close"], "Close", "default Close label")


func test_lines_use_default_labels_next_then_close() -> void:
	var d = Dialogue.new(StoryFlags.new())
	d.start("innkeeper")
	var n: int = d.entry["lines"].size()
	check(n >= 2, "innkeeper has several lines")
	for i in n:
		var want := Dialogue.default_button("close") if i == n - 1 else Dialogue.default_button("next")
		eq(d.line()["button"], want, "line %d label" % i)
		d.advance()


func test_line_can_set_its_own_button_label() -> void:
	# A line's "button" overrides the default, read straight from data.
	var dlg: Dictionary = GameData.get_json("dialogue")
	dlg["test_custom"] = [{"lines": [
		{"speaker": "agador", "text": "One", "button": "Pull lever"},
		{"speaker": "agador", "text": "Two"},
	]}]
	var d = Dialogue.new(StoryFlags.new())
	d.start("test_custom")
	eq(d.line()["button"], "Pull lever", "custom label on a middle line")
	d.advance()
	eq(d.line()["button"], Dialogue.default_button("close"), "default label on the last line")
	dlg.erase("test_custom")


func test_underscore_keys_are_not_interactions() -> void:
	check(not Dialogue.has_interaction("_buttons"), "_buttons is settings, not an interaction")
	check(not Dialogue.new(StoryFlags.new()).start("_buttons"), "cannot start _buttons")


func test_font_has_every_glyph_in_ui_text() -> void:
	# A missing glyph shows as a box (the old broken symbol after "Next").
	var font: Font = ThemeDB.fallback_font
	var texts: Array = []
	for k in ["next", "close", "skip"]:
		texts.append(Dialogue.default_button(k))
	for l in _all_lines():
		texts.append(str(l.get("text", "")))
		texts.append(str(l.get("button", "")))
	for c in GameData.get_json("characters").values():
		texts.append(str(c["name"]))
	for a in GameData.get_json("abilities").values():
		texts.append("%s %s · r" % [a["name"], a["element"]])
	for t in texts:
		for i in t.length():
			check(font.has_char(t.unicode_at(i)), "font has '%s' (U+%04X) used in '%s'" % [t[i], t.unicode_at(i), t])


func test_tile_debug_text_hidden_by_default() -> void:
	eq(GameData.setting("debug_tile_text", true), false, "debug_tile_text is off in data")
	var st = make(["....", "....", "....", "...."], [["tide", 0, 0]], [])
	eq(FightMain.describe_tile(st, Vector2i(2, 2), false), "", "plain floor shows nothing for players")
	var w = make(["....", ".w..", "....", "...."], [], [])
	var s: String = FightMain.describe_tile(w, Vector2i(1, 1), false)
	check(s.contains("Water") and not s.contains("Tile"), "useful tile info stays, without the raw 'Tile x,y'")
	var u: String = FightMain.describe_tile(st, Vector2i(0, 0), false)
	check(u.contains(GameData.hero("tide")["name"]) and not u.contains("Tile"), "unit details stay")


func test_tile_debug_text_shown_when_enabled() -> void:
	var st = make(["....", "....", "....", "...."], [], [])
	var s: String = FightMain.describe_tile(st, Vector2i(2, 1), true)
	check(s.contains("Tile 2,1: floor"), "debug shows 'Tile 2,1: floor' (got '%s')" % s)
	# The switch is read from data, so flipping it in data turns it on.
	var settings: Dictionary = GameData.get_json("settings")
	settings["debug_tile_text"] = true
	check(bool(GameData.setting("debug_tile_text", false)), "setting read from data")
	settings["debug_tile_text"] = false


func test_start_screen_build_label() -> void:
	const StartMenu = preload("res://scripts/view/start_menu.gd")
	# Tests run from the repo, where the web build's stamp is absent.
	if not FileAccess.file_exists("res://data/build.json"):
		eq(StartMenu.build_text(), "Dev build", "no stamp: Dev build")
	else:
		check(StartMenu.build_text().begins_with("Build "), "stamped build shows its id")
