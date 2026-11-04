# CLAUDE.md

## Goal
A Godot 4 (GDScript) prototype of one turn-based tactics fight. Its only purpose is to answer: **"Is setting up and executing a plan in one fight fun?"**

**Check every feature against that goal. Does it help answer whether this fight is fun?** If not, don't build it. Out of scope: story, final art, music, leveling, loot, inventory, world map, multiple levels, bosses, saves, balance simulators, browser smoke tests, pinch zoom, and complex layout systems.

## Foundation rules
- **Combat state is plain data.** `BattleState`/`Unit` are RefCounted data with no Nodes, separate from scene objects. They're cloneable, and previews run on clones.
- **The rules run headless on that data.** The view sends commands (`Commands.move`, `use_ability`, `wait`, `end_turn`) through `Rules.apply_command(state, cmd)`, which validates them, mutates the state, and returns an ordered event list. The view only animates those events and never decides outcomes.
- **One seeded RNG** lives in `BattleState` (`rng_seed`/`rng_state`, seeded from the encounter). All gameplay randomness must use `state.rand_int()`, never `randf()`/`randi()`. Cosmetic-only randomness in the view (screen shake) is fine.
- **Content is JSON** in `data/`: heroes, enemies, abilities, encounters, terrain and its interactions (`terrain.json` reactions), and rule numbers. Prefer changing data over code.
- **Art is referenced by sprite key.** A `sprite` key in the data maps to `res://art/<key>.png`. When the file is missing, the game draws a code placeholder.
- **One command runs all headless tests** and exits non-zero on failure (see below).
- **CI:** `.github/workflows/ci.yml` runs the tests on every push to `main`, builds a no-threads web export (`tools/build_web.sh`), and publishes it to GitHub Pages. The page has a robots noindex tag.
- **Compatibility renderer**, for reliable mobile browser support.

## Input and layout rules (PC + phone browser)
- Design for a portrait phone first. Larger screens use the extra space (landscape: board left, panel right) without shrinking text.
- **One input model for mouse and touch:** tap or click to select, then tap or click the same thing again to confirm. Nothing may depend on hover or right-click. Long-press or the Info button shows details.
- Touch targets are at least 48 CSS px (`ScreenMetrics` keeps 1 UI unit close to 1 CSS px). The full 10x10 grid stays readable without zooming. Respect safe areas (notch, gesture bar).
- Input stays separate from combat logic. `board_input.gd` turns pointer input into tap/long-press gestures, and `main.gd` turns gestures into Commands.

## Structure
- `data/*.json`: content and tuning
- `scripts/core/`: rules (`battle_state`, `rules`, `commands`, `enemy_ai`, `level_loader`, `game_data`, `unit`). No Nodes.
- `scripts/view/`: `main.gd` (controller), `hud.gd` (widgets + portrait/landscape layout), `board_view.gd` (drawing + event playback), `board_input.gd` (gestures), `screen_metrics.gd` (scale + safe areas)
- `tests/`: `run_tests.gd` (runner), rule suites, `ui_smoke.gd` (drives the real scene in phone and desktop layouts)
- `tools/build_web.sh`, `export_presets.cfg`: web export

## Conventions
- New mechanics go in `rules.gd` (with a new event type if needed) and are animated in `BoardView._play_event`.
- Core scripts use `preload` constants, not `class_name`, so the tests run without an editor import.
- Tabs for indentation, typed GDScript where inference works. Small, focused commits. This is a public repo: never commit secrets, keys or personal info.

## Running tests
```sh
godot --headless --path . --script res://tests/run_tests.gd   # all tests; non-zero exit on failure
```
Add `test_*` methods to a suite in `tests/` (register new suites in `SUITES`). Build small boards with `make(map, heroes, enemies)` from `test_base.gd`, and assert against values read from `data/`.
