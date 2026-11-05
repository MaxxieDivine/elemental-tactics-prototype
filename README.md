# Elemental Tactics Prototype

A small Godot 4 prototype of one turn-based tactics fight. It exists to answer a single question:

> **Is setting up and executing a plan in one fight fun?**

You have three heroes, one each for water, lightning and fire, on a 10x10 grid. You fight five enemies that show their plans before they act. You set up combos: soak tiles and then electrify them, ignite oil next to an explosive barrel, or boil water into steam to block a sniper's sight. Then you watch the chain play out one step at a time.

Milestone 2 adds a **walkable town slice** in front of that fight: a small dock and town square where you tap to walk, talk to the innkeeper, read a banner and your letter, and open a humming cellar door that starts the fight. One clue changes what the innkeeper says, and winning changes the cellar door.

Everything is drawn with simple placeholder shapes and generated tiles. There's no final art, audio, saves or progression.

## Play it

**In a browser (desktop or phone):** https://maxxiedivine.github.io/elemental-tactics-prototype/

**In Godot:** install [Godot 4.3+](https://godotengine.org/download) (standard build, no .NET needed). In the Project Manager, choose **Import**, select `project.godot`, and press **F5**.

The start screen has two buttons: **Town** (the walkable slice) and **Fight** (the fight on its own, for testing).

## Town controls

| Do this | To |
|---|---|
| Tap (or click) a tile | Walk there |
| Tap a person or object | Walk next to it, face it, and talk / look |
| Tap anywhere during dialogue | First tap shows the whole line, next tap goes on (or use the **Next** button) |
| **Menu** | Back to the start screen (story flags are kept until you reload) |

Try: read the banner, talk to the innkeeper, read your letter on the dock, talk to the innkeeper again, then tap the cellar door beside the inn. Win or lose, you come back to the town where you stood. After a win the door says something new.

## Fight controls

The same controls work for mouse and touch: **tap (or click) to select, then tap the same thing again to confirm.**

| Do this | To |
|---|---|
| Tap a hero, or its button under the board | Select it |
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

### Town, story and art (no code changes)

- **Dialogue:** `data/dialogue.json`. Each interaction id (`innkeeper`, `welcome_banner`, `letter`, `cellar_door`) has a list of entries; the first one whose `requires` flags are all set (and `unless` flags unset) plays. An entry can `set_flags` and `start_fight` (an encounter id) with `win_flags`.
- **Names and colours:** `data/characters.json` for town speakers; `data/heroes.json` `name` for Tide, Volt and Ember.
- **Town map:** `data/town.json`: the map rows and tile legend, player start, NPC/object/prop placements, `zoom`, walking `step_time` and dialogue `text_speed` (characters per second).
- **Art:** `data/assets.json` maps keys (`agador.portrait.neutral`, `town.tiles`, ...) to files. Drop a PNG in `art/` and point its key at it. See `art/README.md` for formats. Missing files show a placeholder and log a warning.

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
This runs every rules, story, town and asset test, a UI smoke test that taps through the fight in a phone layout and a desktop layout, and a flow test that plays the real app on a phone: town, dialogue, fight (loss and win), back to town, and the direct Fight option. It exits non-zero on failure.

## Web build and deployment

`tools/build_web.sh` makes a single-threaded web export in `build/web`. That export runs on GitHub Pages without special headers. On every push to `main`, GitHub Actions runs the tests, builds the web export, and publishes it to GitHub Pages. The page carries a `noindex` tag and a `robots.txt` that blocks crawlers.

## Status

Milestone 2: one walkable town slice connected to one fight, on desktop and phone browsers. Scope is intentionally tiny: no saves, branching choices, quest log, party following, final art or audio.
