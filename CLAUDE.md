# CLAUDE.md

## Goal
A Godot 4 (GDScript) prototype of a single turn-based tactics fight. Its only purpose is to answer: "Is setting up and executing a plan in one fight fun?" Keep it to the smallest clean version. Do not add story, final art, music, leveling, loot, inventory, a world map, multiple levels or a boss.

## Structure
- `data/*.json`: all tunable content (heroes, enemies, abilities, rule numbers, the map). Prefer changing data over code.
- `scripts/core/`: pure rules with no Nodes or rendering.
  - `battle_state.gd`: grid, units, and queries (reachability, paths, line of sight, connected surfaces). It's cloneable.
  - `rules.gd`: resolves actions. Each action mutates the state **and returns an ordered event list**.
  - `enemy_ai.gd`: plans visible intents and resolves them against the current board (used for both preview and execution).
  - `level_loader.gd`, `game_data.gd`, `unit.gd`
- `scripts/view/`: presentation only.
  - `board_view.gd`: draws a display copy of the state and replays events (tweens, flashes, floating numbers, pauses).
  - `main.gd`: input, selection, UI text. It previews actions by running them on `state.clone()`.
- `scenes/main.tscn`: the entry scene
- `tests/`: headless test runner, rule suites, UI smoke test

## Conventions
- The rules never touch the view. The view never decides outcomes and only plays events. New mechanics are added in `rules.gd` with a new event type if needed, then handled in `BoardView._play_event`.
- Core scripts reference each other with `preload` constants, not `class_name`, so tests run without an editor import.
- The rules are deterministic (no randomness) so previews are exact.
- Tabs for indentation, typed GDScript where inference works.
- Small, focused commits. Public repo: never commit secrets, keys or personal info.

## Running tests
```sh
godot --headless --path . --script res://tests/run_tests.gd   # exits non-zero on failure
godot --headless --path . --script res://tests/smoke_ui.gd    # UI smoke test
```
To add a test, add a `test_*` method to a suite in `tests/` (or add a new suite to `SUITES` in `run_tests.gd`). Use `make(map, heroes, enemies)` from `test_base.gd` to build small boards. Assert against values from `data/` so tuning doesn't break tests.
