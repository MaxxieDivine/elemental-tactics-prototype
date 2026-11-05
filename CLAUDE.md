# CLAUDE.md

## Goal
A Godot 4 (GDScript) prototype of a small, story-driven party RPG: a walkable town slice connected to one turn-based tactics fight.

- **Fight question:** "Is setting up and executing a plan in one fight fun?"
- **Milestone 2 question:** "Can we place art in a slightly angled 2D world and connect exploration, story, and the existing fight through reusable systems, with most content changes made in data instead of code?"
- **Milestone 3 question:** "Can the Milestone 2 systems support multiple connected spaces, with new rooms, objects, and dialogue added mostly through data? Does launching the test fight from an in-world arcade cabinet make it feel like part of the game?"
- **Milestone 4 question:** "Does a second character make players care and want to know what happens next? Can characters and places react to story progress mostly through data?" (The second guest, `new_guest`, shown as `???`.)

**Check every feature against those questions.** If it doesn't help answer them, don't build it. Out of scope: the cellar interior, interiors for Rooms 2-4, inventory, full opening scene, party following, a second playable character, naming ??? or the sister, explaining the letters or Room 4, day and night, new fights, fight changes, reskinning the fight, saves, branching choices, quest log, clue journal, cutscene movement beyond simple pacing (no general cutscene system), music, final art, leveling, loot, world map, multiple levels, bosses, balance simulators, pinch zoom, and complex layout systems.

## Setup (every session)
Run `tools/setup_godot.sh` before tests (`tools/setup_godot.sh --web` before a web export). It installs the exact Godot version CI uses (read from `.github/workflows/ci.yml`) into `~/.local/bin` only when it is missing, so it is safe to run every time. Add `~/.local/bin` to `PATH` if `godot` is not found.

## Foundation rules
- **Combat state is plain data.** `BattleState`/`Unit` are RefCounted data with no Nodes, separate from scene objects. They're cloneable, and previews run on clones.
- **The rules run headless on that data.** The view sends commands (`Commands.move`, `use_ability`, `wait`, `end_turn`) through `Rules.apply_command(state, cmd)`, which validates them, mutates the state, and returns an ordered event list. The view only animates those events and never decides outcomes.
- **One seeded RNG** lives in `BattleState` (`rng_seed`/`rng_state`, seeded from the encounter). All gameplay randomness must use `state.rand_int()`, never `randf()`/`randi()`. Cosmetic-only randomness in the view (screen shake) is fine.
- **Content is JSON** in `data/`: heroes (incl. display names), enemies, abilities, encounters, terrain and its interactions (`terrain.json` reactions), rule numbers, `settings.json` (developer switches such as `debug_tile_text`), and for the world: `town.json` (shared tile legend, start spot, tuning), `maps/<id>.json` (one per map: rows, npcs, objects, props, exits), `characters.json` (names, colours, sprite/portrait keys), `dialogue.json` (interactions by id; `_buttons` default labels). Prefer changing data over code.
- **Art is referenced by key** through `AssetCatalog` (`scripts/core/asset_catalog.gd`). `data/assets.json` maps keys (`agador.portrait.neutral`, `town.tiles`) to paths; unlisted keys fall back to `res://art/<key>.png`. Never put a file path in code or content. A missing asset logs one warning and shows a placeholder; it never crashes.
- **Story state is plain data too.** `StoryFlags` (named flags), `Dialogue` (picks the first entry whose `requires`/`unless` flags match, steps lines, applies `set_flags`/`start_fight` at the end), `GameSession` (flags, current map/cell/facing, fight in progress; `GameSession.current`), `TownMap` (one map built for a set of flags: walkability, paths, targets, `stand` cells, exits and arrivals, pacers). All headless. No map-specific or story-specific logic in code: exits carry target map, arrival cell and facing; who is where comes from world-state rules.
- **World state is data.** An NPC or object in `data/maps/<id>.json` may list `states`: `{ "requires": [...], "unless": [...], "priority": n, ...keys }`. Of the matching states the highest `priority` wins (default 0; ties go to the one listed first), and only that one state applies: its keys (`cell`, `facing`, `hidden`, `interaction`, `sprite`, `shape`, `stand`, `pace`, `mood`) replace the base keys. `"hidden": true` removes the thing (no sprite, no blocking, nothing to tap). `WorldState` (`scripts/core/world_state.gd`) resolves it; `TownMap.load_map(id, flags)` applies it on every map load, and `town.gd` re-applies it after each conversation (rebuilding the map behind a short fade only if something on it changed). A character in two places (the second guest in the lobby and the lounge) is listed on both maps with states that show it in one.
- **Pacing, not cutscenes.** An NPC state with `"pace": [[x, y], ...]` walks that route back and forth (`Pacer`, `scripts/core/pacer.gd`; `TownMap.step_pacer`), pausing `pace_wait` seconds at each point facing its `facing`. Timing is `pace_step_time`/`pace_wait` in `town.json` (overridable per NPC). It pauses during dialogue and while the player walks over to it, never steps onto the player or the player's path (it turns around instead), and tests check that no route cell is a stand cell or arrival and that every target stays reachable with the pacer on any route cell. `"mood": "upset"` draws a mark above the head (art key `mood.<name>`, placeholder otherwise).
- **Screens report, the app decides.** `app.gd` swaps start menu / town / fight. The town screen shows any map and changes maps itself (fade) through exits; it emits `fight_requested(request)`; the fight takes `encounter_id` + `from_town` and emits `fight_finished(won)`, and the player returns to the spot they launched it from. Fight rules are unchanged.
- **One command runs all headless tests** and exits non-zero on failure (see below).
- **CI:** `.github/workflows/ci.yml` runs the tests on every push to `main`, builds a no-threads web export (`tools/build_web.sh`), and publishes it to GitHub Pages. The page has a robots noindex tag.
- **Compatibility renderer**, for reliable mobile browser support.

## Input and layout rules (PC + phone browser)
- Design for a portrait phone first. Larger screens use the extra space (landscape: board left, panel right) without shrinking text.
- **One input model for mouse and touch:** tap or click to select, then tap or click the same thing again to confirm. Nothing may depend on hover or right-click. Long-press or the Info button shows details.
- Touch targets are at least 48 CSS px (`ScreenMetrics` keeps 1 UI unit close to 1 CSS px). The full 10x10 grid stays readable without zooming. Respect safe areas (notch, gesture bar).
- Town: one tap walks to a tile; tapping an NPC/object walks next to it and starts its interaction; tapping an exit walks next to it and fades to its map. In dialogue, one tap finishes the typing, the next advances. Town zoom snaps so each art pixel is whole device pixels (crisp, nearest filtering).
- Input stays separate from combat logic. `board_input.gd` turns pointer input into tap/long-press gestures, and `main.gd` turns gestures into Commands.

## Structure
- `data/*.json`: content and tuning
- `scripts/core/`: fight rules (`battle_state`, `rules`, `commands`, `enemy_ai`, `level_loader`, `game_data`, `unit`) and town/story (`asset_catalog`, `story_flags`, `dialogue`, `game_session`, `town_map`, `world_state`, `pacer`). No Nodes.
- `scripts/view/`: `app.gd` (screen switcher, main scene `scenes/app.tscn`), `start_menu.gd`, fight: `main.gd` (controller, `scenes/main.tscn`), `hud.gd`, `board_view.gd`, `board_input.gd`; town: `town.gd` (controller, `scenes/town.tscn`), `town_tiles.gd` (TileSet from `town.tiles` or generated), `town_actor.gd` (depth-sorted sprite/placeholder), `dialogue_box.gd` (`scenes/dialogue_box.tscn`); shared `screen_metrics.gd` (scale, safe areas, DPR)
- `tests/`: `run_tests.gd` (runner), rule/story/town/world-state/asset/ui-text suites, `ui_smoke.gd` (fight in phone and desktop layouts), `flow_smoke.gd` (real app on a phone: town -> inn rooms -> arcade fight -> back beside the arcade -> Room 1 key -> the second guest's scene -> the inn afterwards)
- `tools/setup_godot.sh` (install Godot), `tools/build_web.sh`, `export_presets.cfg`: web export

## Conventions
- New interactions: add an object/NPC with an `interaction` id to a map in `data/maps/` and entries under that id in `dialogue.json`. No code.
- New rooms: add `data/maps/<id>.json` and an exit pointing at it (plus one back). Tests check every exit's arrival is walkable and every target is reachable from every arrival, for every combination of the flags the map's states use.
- Story reactions: set a flag in a dialogue entry's `set_flags`, then add a `requires` entry at the top of an interaction in `dialogue.json` and/or a `states` rule on an NPC/object. No code.
- New characters: add them to `characters.json` (name, colour, sprite and portrait keys) and list the keys in `assets.json`. Placeholder portraits show a short name (up to 3 characters, like `???`) in full, else its first letter.
- New placeholder art shapes go in `town_actor.gd` (`ANIMATED` for looping ones); new tile patterns in `town_tiles.gd`.
- New mechanics go in `rules.gd` (with a new event type if needed) and are animated in `BoardView._play_event`.
- Core scripts use `preload` constants, not `class_name`, so the tests run without an editor import.
- Tabs for indentation, typed GDScript where inference works. Small, focused commits. This is a public repo: never commit secrets, keys or personal info.

## Running tests
```sh
tools/setup_godot.sh                                           # once per session: installs Godot if missing
godot --headless --path . --script res://tests/run_tests.gd   # all tests; non-zero exit on failure
```
With a display (`xvfb-run -a godot --path . --script res://tests/run_tests.gd -- --shots=<dir>`) the smoke tests also save screenshots.
Add `test_*` methods to a suite in `tests/` (register new suites in `SUITES`). Build small boards with `make(map, heroes, enemies)` from `test_base.gd`, and assert against values read from `data/`.
