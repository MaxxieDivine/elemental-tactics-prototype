# Elemental Tactics Prototype

A small Godot 4 prototype of one turn-based tactics fight. It exists to answer a single question:

> **Is setting up and executing a plan in one fight fun?**

You have three heroes, one each for water, lightning and fire, on a 10x10 grid. You fight five enemies that show their plans before they act. You set up combos: soak tiles and then electrify them, ignite oil next to an explosive barrel, or boil water into steam to block a sniper's sight. Then you watch the chain play out one step at a time.

In front of that fight is a small **walkable world**. You play Agador: start on the dock, read a banner and your letter, find a locked cellar hatch humming against the inn wall, then go inside the inn. The lobby has the innkeeper, a guest book and a key board; the lounge has a fireplace and an arcade cabinet that has no business being there; upstairs, Room 1 is open and Rooms 2 to 4 are locked. Your letter changes what the innkeeper and the guest book say. The arcade's **Insert coin** starts the fight, and you come back beside the cabinet afterwards (win or lose). After a win the arcade shows a high score you never entered, and you can play again. Once you pick up the Room 1 key and come back downstairs, a distressed stranger, **???**, is pacing in front of the desk arguing with the innkeeper. Talk to them: a missing sister, a letter that should not be that old. Afterwards ??? waits by the arcade in the lounge, and the innkeeper, the guest book and the Room 2 door all have something new to say.

Everything is drawn with simple placeholder shapes and generated tiles. There's no final art, audio, saves or progression.

## Play it

**In a browser (desktop or phone):** https://maxxiedivine.github.io/elemental-tactics-prototype/

**From a terminal:** `tools/setup_godot.sh` installs the Godot version CI uses when it is missing, then `godot --headless --path . --script res://tests/run_tests.gd` runs every test.

**In Godot:** install [Godot 4.3+](https://godotengine.org/download) (standard build, no .NET needed). In the Project Manager, choose **Import**, select `project.godot`, and press **F5**.

The start screen has two buttons: **Town** (the walkable slice) and **Fight** (the fight on its own, for testing).

## Town controls

| Do this | To |
|---|---|
| Tap (or click) a tile | Walk there |
| Tap a person or object | Walk next to it, face it, and talk / look |
| Tap a door, doorway or stairs | Walk next to it, then fade to the next room |
| Tap anywhere during dialogue | First tap shows the whole line, next tap goes on (or use the **Next** button) |
| **Menu** | Back to the start screen (story flags are kept until you reload) |

Try: read the banner, tap the hatch beside the inn, go in and talk to the innkeeper, check the guest book and key board, then go left into the lounge and tap the arcade. Win or lose, you come back next to the arcade. Go upstairs and try the doors. Then go back out, read the letter on the dock, and talk to the innkeeper and the guest book again. Take the key in Room 1, go back down to the lobby and tap ???. Then visit the lounge, the innkeeper, the guest book and the Room 2 door.

Menu remembers where you were: tapping Town again puts you back there. Story flags last until you reload the page.

## Fight controls

The same controls work for mouse and touch: **tap (or click) to select, then tap the same thing again to confirm.**

| Do this | To |
|---|---|
| Tap a hero, or its tab under the board | Select it. The panel under the tabs shows that hero's abilities |
| Tap a blue tile, then tap it again | Move there (the first tap shows the path) |
| Tap an ability button | Aim it (yellow tiles are valid targets) |
| Tap a yellow tile, then tap it again | Use the ability (the first tap previews who and what gets hit, including chain reactions) |
| Tap an enemy, or long-press any tile | See details, including that enemy's plan and what it will hit |
| **Info** | Toggle info mode: taps only show details |
| **Cancel** | Step back (clear the pending tap, stop aiming, deselect) |
| **Wait** / **Undo** | End this hero's turn / undo the last hero action (this turn only) |
| **End Turn** | Enemies act. If a hero can still act, it asks for a second tap first |
| **Restart** / **x1** | Restart the fight instantly / toggle fast playback |

Each hero can **move once and act once per turn, in either order**. On desktop there are optional shortcuts: `1`-`3` select a hero, `Q` `W` `E` pick an ability, `Enter` confirms, `Esc` cancels, `X` waits, `Z` undoes, `Space` ends the turn, `I` toggles info, `R` restarts, and `F` toggles speed.

## How the fight works

- **Turn order:** in each round, your heroes act in any order, then the enemies act in the numbered order shown. The info panel lists it.
- **Enemy intents:** each enemy shows a path to the tile it will move to and a red X on the tile it will attack, with its order number. The attack hits **that tile**: if you move away, it misses, and if you push another enemy onto it, that enemy gets hit. A target drawn in grey with the word "blocked" means the attack won't connect from where the enemy will end up (out of range, or steam blocks its sight).
- **Heroes**
  - **Tide** (water): *Splash* soaks a + shaped area. *Wave* is a straight jet that soaks its path and pushes the first unit 2 tiles. Units that slam into something take collision damage. A barrel hit by Wave slides and explodes when it hits something.
  - **Volt** (lightning): *Zap* hits one tile. *Thunderclap* hits a 3x3 area. Both spread through **all connected water**, including water under your own heroes.
  - **Ember** (fire): *Firebolt* hits one tile. *Inferno* hits a + shaped area. Fire burns units (damage each turn), ignites the **whole oil patch**, explodes barrels, and turns water into **steam that blocks line of sight** for 2 rounds.
- **Terrain:** walls block movement and sight. Oil burns all at once. An **explosive barrel** blows up when it's hit, burned, shocked, or touched by burning oil, and its blast is fire on the 8 tiles around it, so it can set off more reactions.
- **Enemies:** *Brutes* (squares) walk up and Smash an adjacent tile. *Spitters* (diamonds) lob fire from range 4 and need line of sight when they fire.
- You win when all enemies are down and lose when all heroes are down. Tap **Play again** to restart.

## Tuning

### World, story and art (no code changes)

- **Dialogue:** `data/dialogue.json`. Each interaction id (`innkeeper`, `guest_book`, `arcade`, `room_4_door`, ...) has a list of entries; the first one whose `requires` flags are all set (and `unless` flags unset) plays. An entry can `set_flags` and `start_fight` (an encounter id) with `win_flags`. A line can set `"button"` to label its action button (the arcade uses `"Insert coin"`); `_buttons` holds the defaults (`Next`, `Close`, `Skip`).
- **Names and colours:** `data/characters.json` for town speakers (Agador's id is `agador`; change `name` to rename him). `data/heroes.json` `name` for Tide, Volt and Ember.
- **Maps:** one file per map in `data/maps/` (`town`, `lobby`, `lounge`, `hallway`, `room_1`). Each has `map` rows using the shared tile legend in `data/town.json`, plus `npcs`, `objects` (with an `interaction` id), `props`, and `exits`. An NPC or object can list `stand` cells to say where the player uses it from (the hatch is used from the side, the innkeeper across the desk). An optional `zoom` overrides the world zoom for one map.
- **Who is where (world state):** any NPC or object in a map file can list `states`, e.g. `{"requires": ["met_new_guest"], "priority": 10, "hidden": true}`. Of the states whose flags match, the highest `priority` wins (ties: the one listed first) and its keys replace the base ones: `cell`, `facing`, `hidden`, `interaction`, `sprite`, `shape`, `stand`, `pace` (a route `[[x, y], ...]` walked back and forth) and `mood` (`"upset"` shows a mark above the head). The second guest is in `lobby.json` (pacing route) and `lounge.json` (spot by the arcade); Room 2's door swaps its card in `hallway.json`. Pacing speed is `pace_step_time` / `pace_wait` in `data/town.json`.
- **Exits:** `{"id", "cell" or "cells", "to": map id, "arrive": [x, y], "facing"}`. Exits sit on a door, doorway or stairs tile. To add a room, make a new `data/maps/<id>.json` and point an exit at it (with one back).
- **World settings:** `data/town.json`: where a new story starts (`player`: character, map, cell, facing), the tile legend (`atlas` cell, placeholder `color` and `pattern`), `zoom`, walking `step_time`, dialogue `text_speed` (characters per second) and the map-change `fade_time`.
- **Art:** `data/assets.json` maps keys (`agador.portrait.neutral`, `town.tiles`, `inn.arcade`, ...) to files. Drop a PNG in `art/` and point its key at it. See `art/README.md` for formats. Missing files show a placeholder and log a warning.
- **Debug:** `data/settings.json` `debug_tile_text: true` shows raw tile text such as `Tile 5,6: floor` in the fight's info panel.

### Fight

All numbers and the map live in `data/`:

- `heroes.json`, `enemies.json`: HP, move, and which abilities each unit has
- `abilities.json`: damage, range, shape, line of sight, push, and cooldown
- `rules.json`: burn damage and duration, steam duration, oil and barrel damage, collision damage
- `terrain.json`: what tiles and surfaces do, and the element reactions (fire + water -> steam, fire + oil -> ignite, ...)
- `encounters.json`: the map (`.` floor, `#` wall, `o` oil, `w` water, `B` barrel), spawn points, and the RNG seed

Optional art: put `art/<sprite key>.png` next to the project (keys are in the data files). Missing art falls back to simple shapes.

## Tests

```sh
godot --headless --path . --script res://tests/run_tests.gd
```
This runs every rules, story, map, asset and UI-text test, a UI smoke test that taps through the fight in a phone layout and a desktop layout, and a flow test that plays the real app on a phone: town, every inn room, every interaction, the arcade fight (loss, win, replay) and back beside the arcade, the letter changing the innkeeper and guest book, and the direct Fight option. It exits non-zero on failure. With a display (for example `xvfb-run`), add `-- --shots=<dir>` to save screenshots.

## Web build and deployment

`tools/build_web.sh` makes a single-threaded web export in `build/web`. That export runs on GitHub Pages without special headers. On every push to `main`, GitHub Actions runs the tests, builds the web export, and publishes it to GitHub Pages. The page carries a `noindex` tag and a `robots.txt` that blocks crawlers.

## Status

Milestone 3: the town and five connected spaces (town, lobby, lounge, upstairs hallway, Room 1) built from data, with the fight launched from an in-world arcade cabinet, on desktop and phone browsers. Scope is intentionally tiny: no cellar interior, other room interiors, saves, inventory, branching choices, quest log, party following, final art or audio.
