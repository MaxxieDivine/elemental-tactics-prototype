# Art

All art is looked up **by key**, never by path. `data/assets.json` maps each
key to a file; keys not listed there fall back to `art/<key>.png` (the fight's
sprite keys such as `hero_tide` or `tile_barrel` use this).

A missing file is fine: the game logs one warning and draws a placeholder.

To add or replace art: put the PNG anywhere under `art/` and point its key at
it in `data/assets.json`. No code changes.

| Key | What | Format |
|---|---|---|
| `town.tiles` | Town and inn tileset (one sheet) | 16x16 tiles, no spacing (e.g. Kenney Tiny Town `tilemap_packed.png` plus interior tiles). Set each tile's `atlas` cell in `data/town.json`. Inn tiles: wood floor, rug, wall top, wallpaper, window, room door, stairs up/down, side doorway, front door. |
| `agador.sprite`, `innkeeper.sprite`, `new_guest.sprite` | Town characters | One row of 4 equal frames: down, left, right, up. Feet at the bottom centre. |
| `agador.portrait.neutral`, `innkeeper.portrait.neutral`, `new_guest.portrait.upset` | Dialogue portraits | Any square-ish image (shown at 76x76, nearest filtering). Which key a character uses is set in `data/characters.json`. Without art, the placeholder is the character's colour with their initial (or a short name like `???` in full). |
| `mood.upset` | Mark above an upset NPC | Small image, drawn centred above the head. |
| `town.welcome_banner`, `town.letter`, `town.cellar_hatch`, `town.tree`, `town.lamp`, `town.crate` | Town objects/props | One image, drawn standing on its tile (bottom centre). |
| `town.ferry`, `town.night_letter` | First-night objects | One image, bottom centre on its tile. The ferry sits on a water tile offshore (about 32 px wide); without art it is a dark silhouette with one dim lantern. |
| `light.pool` | Night light pools | A white, soft radial blob (any size; it is scaled to each pool's radius and tinted from `lighting_presets` in `data/town.json`). Without it, pools are stepped pixel rings. |
| `inn.arcade`, `inn.fireplace`, `inn.guest_book`, `inn.desk`, `inn.key_board`, `inn.lantern`, `inn.flowers`, `inn.armchair`, `inn.side_table`, `inn.bed`, `inn.table_key`, `inn.door_reserved`, `inn.door_name`, `inn.door_light` | Inn objects/props | One image, bottom centre on its tile. Wall pieces (fireplace, key board, lanterns, door cards) stand on the wall tile's bottom edge. The bed is two tiles tall (32 px). A loaded image is static; only the placeholders animate. |
| `hero_*`, `enemy_*`, `tile_*`, `surface_*` | Fight (optional) | Drawn inside a fight tile. |

Night lighting is not art: it tints tiles and sprites and draws light pools
from the presets in `data/town.json` (`lighting_presets`). Art drawn for the
day works at night unchanged.
