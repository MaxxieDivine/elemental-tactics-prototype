# Elemental Tactics Prototype

A small Godot 4 prototype of one turn-based tactics fight. It exists to answer a single question:

> **Is setting up and executing a plan in one fight fun?**

You have three heroes, one each for water, lightning and fire, on a 10x10 grid. You fight five enemies that show their plans before they act. You set up combos: soak tiles and then electrify them, ignite oil next to an explosive barrel, or boil water into steam to block a sniper's sight. Then you watch the chain play out one step at a time.

Everything is drawn with simple shapes. There's no story, art, audio or progression.

## Opening it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, GDScript only, no .NET needed).
2. In the Godot Project Manager, choose **Import** and select this folder's `project.godot`.
3. Press **F5** (or the Play button) to run the fight.

From a terminal: `godot --path .` runs the game.

## Controls

| Input | Action |
|---|---|
| Left-click a hero, `1` `2` `3`, or `Tab` | Select a hero (Tab picks the next one that hasn't acted) |
| Left-click a blue tile | Move there (hover to see the path) |
| `Q` / `W` / `E` (or the buttons) | Pick the basic attack / ability 1 / ability 2 |
| Hover a yellow tile | Preview exactly who and what gets hit, including chain reactions |
| Left-click a yellow tile | Use the ability |
| Right-click / `Esc` | Cancel targeting, or deselect |
| Hover an enemy | Highlight its plan and preview what it will hit |
| `X` | Wait (end this hero's turn) |
| `Z` | Undo the last hero action (this turn only) |
| `Space` / `Enter` | End turn (enemies act) |
| `F` | Toggle fast playback |
| `R` | Restart the fight instantly |

Each hero can **move once and act once per turn, in either order**.

## How the fight works

- **Turn order:** in each round, your heroes act in any order, then the enemies act in the numbered order shown. The panel on the right lists it.
- **Enemy intents:** each enemy shows a path to the tile it will move to and a red X on the tile it will attack, with its order number. The attack hits **that tile**: if you move away, it misses, and if you push another enemy onto it, that enemy gets hit. A target drawn in grey with the word "blocked" means the attack won't connect from where the enemy will end up (out of range, or steam blocks its sight).
- **Heroes**
  - **Tide** (water): *Splash* soaks a + shaped area. *Wave* is a straight jet that soaks its path and pushes the first unit 2 tiles. Units that slam into something take collision damage. A barrel hit by Wave slides and explodes when it hits something.
  - **Volt** (lightning): *Zap* hits one tile. *Thunderclap* hits a 3x3 area. Both spread through **all connected water**, including water under your own heroes.
  - **Ember** (fire): *Firebolt* hits one tile. *Inferno* hits a + shaped area. Fire burns units (damage each turn), ignites the **whole oil patch**, explodes barrels, and turns water into **steam that blocks line of sight** for 2 rounds.
- **Terrain:** walls block movement and sight. Oil burns all at once. An **explosive barrel** blows up when it's hit, burned, shocked, or touched by burning oil, and its blast is fire on the 8 tiles around it, so it can set off more reactions.
- **Enemies:** *Brutes* (squares) walk up and Smash an adjacent tile. *Spitters* (diamonds) lob fire from range 4 and need line of sight when they fire.
- You win when all enemies are down and lose when all heroes are down. Press `R` to go again.

## Tuning

All numbers and the map live in `data/`:

- `heroes.json`, `enemies.json`: HP, move, and which abilities each unit has
- `abilities.json`: damage, range, shape, line of sight, push, and cooldown
- `rules.json`: burn damage and duration, steam duration, oil and barrel damage, collision damage
- `level.json`: the map (`.` floor, `#` wall, `o` oil, `w` water, `B` barrel) and spawn points

## Tests

```sh
godot --headless --path . --script res://tests/run_tests.gd   # rules tests
godot --headless --path . --script res://tests/smoke_ui.gd    # drives the real UI for one round
```

## Status

First playable prototype. It covers one fight on one map. Planned scope is intentionally tiny: no levels, progression, loot, art or audio.
