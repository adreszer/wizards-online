# Development guide

## Prerequisites

- Godot **4.7** (standard build; the project uses Jolt physics, built in since 4.4)
- Docker Desktop (or any Docker with Compose v2)
- Git

## Clone and run (offline)

```bash
git clone git@github.com:adreszer/wizards-online.git
cd wizards-online
godot --headless --path . --import   # one-time: builds the import cache + class list
godot --path .                       # or open project.godot in the editor and press F5
```

`tools/run.sh` does both steps (import only when needed) and finds the macOS app bundle automatically:

```bash
tools/run.sh                                  # play
tools/run.sh -- --name=Rowan --instance=2     # a second client
```

The one-time import matters: without it, class names such as `Player` are unknown to a headless run and scripts fail to parse. Opening the project in the editor performs the same import.

On macOS there is no `godot` on the PATH by default; the binary is inside the app bundle. Either use the full path or alias it once:

```bash
alias godot=/Applications/Godot.app/Contents/MacOS/Godot   # add to ~/.zshrc
```

All commands below assume `godot` resolves.

Choose **Play OFFLINE**. The whole castle is explorable without any backend.

Controls: WASD move · Shift run · Space jump · hold right mouse button and drag to orbit the camera · scroll wheel zoom · left click / F cast · E interact · Tab satchel (inventory; click the torch to hold it) · Enter or T chat · Esc pause · F1 lock the cursor for always-on mouse look · F3 debug overlay.

## Backend (Nakama + PostgreSQL)

```bash
docker compose up -d          # first run pulls images and runs migrations
docker compose logs -f nakama # optional: watch the server
docker compose down           # stop (add -v to wipe the database)
```

- Game API: `http://127.0.0.1:7350` (server key `defaultkey`)
- Console: `http://127.0.0.1:7351` (admin / password) — local development only
- Lua modules in `nakama/modules/` are mounted into the container; restart Nakama after editing them (`docker compose restart nakama`).
- The bind mount points at the directory `docker compose up` was first run from. When working in another git worktree, recreate the container from there under the original project name so it mounts your copy of the modules: `docker compose -p <project> up -d --force-recreate nakama` (`docker compose ls` shows the project name; the database volume is kept). Container names are fixed, so a plain `up` from a second directory fails with a name conflict.
- Player inventories live in the storage collection `inventory`, key `items` (one object per user: `{v, items: [{id, count}], held}`); the console at :7351 → Storage shows them. Deleting an object gives that player the starting kit again on the next join.
- Character records live in `character` / `profile`: `{v, house, role, spells: {known, slots, equipped}}`. Deleting one resets that player to a fresh student with no spells.

### Roles (students, professors, admins)

Everyone starts as a student. Roles are changed only on the server:

```bash
# promote an online player by display name (uses the runtime HTTP key from nakama/local.yml)
tools/set_role.sh Elara professor
tools/set_role.sh Elara student
tools/set_role.sh Elara professor 2      # role + house (0 = unsorted, 1–4)
# or by Nakama user id (works for offline players too)
tools/set_role.sh 1c9a…-uuid admin
```

Houses: students are sorted once at the Choosing Stone in the Great Hall (four questions; the server tallies and balances ties). `tools/set_role.sh <name> student 0` un-sorts a player for another ceremony; `tools/set_role.sh <name> student 2` assigns a house directly. Houses are 1 Drakoryn (dragon), 2 Grypheon (griffin), 3 Phoenara (phoenix), 4 Hipporys (hippocampus): names in the CSV (`HOUSE_<n>_NAME`, `HOUSE_<n>_ANIMAL`), colours in `CharacterProfile.HOUSE_COLORS`. House doors admit members only; offline you can still be sorted at the stone (locally) to test them.

The script calls the `admin_set_profile` RPC with `http_key=defaulthttpkey`; the same RPC is available to logged-in admins (the lesson tools do not expose it yet). To make an account an admin permanently, put its user id (console → Accounts) in `ADMIN_USER_IDS` in `nakama/local.yml` (comma-separated) and recreate the container. Only professors and admins can open the lesson tools (`L`) and teach; a grant is accepted only when both stand in the same classroom (`kind = "classroom"` in the generated `nakama/modules/world_areas.lua`). Casts of spells a character does not know are dropped by the server, so promote yourself before expecting to demonstrate anything you have not learned from a tome.

Then launch the game and choose **Play ONLINE**. If the backend is not running you get an error message on the menu and can still play offline.

## Two clients on one machine

```bash
docker compose up -d
godot --path . -- --name=Elara --instance=1 &
godot --path . -- --name=Rowan --instance=2 &
```

Click **Play ONLINE** in both windows. Notes:

- `--instance=N` suffixes the persisted device id so each window authenticates as a different Nakama account. Without it both windows still work (same account, two sessions) because players are keyed by session id.
- `--name=` overrides the display name for that run only. `--host=` / `--port=` point at a different server.
- `--mode=online` or `--mode=offline` skips the menu (handy for scripted testing).

Everything after the standalone `--` is a user argument and is ignored by Godot itself.

## Automated tests

```bash
# load every script/scene (catches parse errors)
godot --headless --path . tests/check_scripts.tscn

# gameplay tests: movement, camera, health/checkpoints, collectibles, spells (registry, spellbook,
# effects), school (profile, area tracker, nameplates, lesson tools), inventory, interaction,
# moving platform, level wiring, castle
godot --headless --path . tests/run_tests.tscn

# two headless clients against a running Nakama (docker compose up -d first)
godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=1 --name=ClientA &
sleep 4
godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=2 --name=ClientB --role=b

# reconnect: start it, then `docker compose restart nakama` while it runs
godot --headless --path . tests/run_reconnect_test.tscn -- --instance=3

# graceful failure: run with the backend STOPPED (docker compose stop)
godot --headless --path . tests/run_offline_fallback_test.tscn
```

Exit code is non-zero on failure; the summary is printed at the end.

## Asset validation scene and tools

```bash
# dev scene: one wall, 3x tiled walls, a 90° corner, the player (Esc toggles mouse, F3 overlay)
godot --path . levels/dev/asset_validation.tscn

# wrapper dimensions, pivot, collision, player-blocked check (headless)
godot --headless --path . tests/validate_wall_plain.tscn

# print what Godot imported from a model: tree, AABB, triangles, materials, textures
godot --headless --path . -s tools/inspect_model.gd -- res://assets/models/environment/modular/wall_plain.glb

# render the validation scene from fixed viewpoints to PNGs (opens a window)
godot --path . tools/capture_validation.tscn -- --out=/absolute/output/dir
# close-ups of a held item (torch by default) on the current body; --character= picks the body
godot --path . tools/capture_held_item.tscn -- --out=/absolute/output/dir --character=apprentice_f [--item=torch]
# a model or wrapper on a floor tile from five angles with an X (red) / Z (blue) gizmo, to check orientation and scale
godot --path . tools/capture_model.tscn -- --scene=res://assets/models/environment/modular/student_desk.glb --out=/absolute/output/dir
# one view of a whole scene (e.g. look into a castle room)
godot --path . tools/capture_model.tscn -- --scene=res://levels/castle/castle.tscn --eye=-22,4.5,-3 --target=-36,0.8,0 --out=/absolute/output/dir
```

Regenerating the castle after editing its plan (`python3 tools/generate_castle.py` from the project root) rewrites `levels/castle/castle.tscn` and `nakama/modules/world_areas.lua` (restart Nakama to pick the latter up); hand edits belong in the generator, in `objects/`, or in `levels/castle/castle.gd`. New rooms need an `AREA_<ID>` row in `localization/translations.csv` (the castle test fails on a missing name).

Adding a new environment module: drop the GLB under `assets/models/…` (never edit it in-repo), run `inspect_model.gd`, create a wrapper `.tscn` under `objects/environment/…` with the fitting transform + simple collision, and place instances in the validation scene before using them in a level. Conventions are in `docs/plan.md` → "Production environment asset pipeline".

## Localization

The game ships in **Polish (primary)** and **English**. All player-facing text lives in one file:

```
localization/translations.csv      keys,en,pl  — the single source of truth
localization/translations.*.translation   generated by the Godot import (git-ignored)
```

- Scenes and scripts use **keys only** (`MENU_PLAY_OFFLINE`, `PLAQUE_ENTRANCE`, …). Controls in `.tscn` files translate their `text` automatically; code uses `tr("KEY")`, formatted strings keep their `%s` / `%d` placeholders inside the CSV cell (`tr("HUD_FRAGMENTS") % [a, b]`). Never concatenate translated fragments.
- Data resources carry keys too: `SpellDefinition.display_name`, `CollectibleDefinition.display_name`, `Interactable.prompt_text`, `Plaque.text`.
- Language choice: the main-menu picker offers *System default*, *Polski* and *English*, persisted in `user://settings.cfg` (`player/language`). *System default* resolves in `core/localization.gd`: Steam client language (once Steamworks is integrated; `SteamLanguage=polish` in the environment simulates it) → OS language → Polish. `--lang=pl|en` after the `--` forces a language for one run. Unknown locales fall back to Polish (`internationalization/locale/fallback`).
- Display names accept accented Latin letters (Polish included) on the client (`GameSession.sanitize_display_name`) and on the server (`sanitize_name` in `nakama/modules/world_match.lua`); keep the two in sync.
- Adding a string: add a row to the CSV with both columns filled, reference the key, re-run `godot --headless --path . --import` (the editor does it on focus). `tests/run_tests.tscn` fails on any key missing a translation, any empty cell or a stale import.
- Adding a language for the Steam release: add a column to the CSV, the locale to `Localization.SUPPORTED` + `NATIVE_NAMES`, its Steam API name to `Localization.STEAM_LANGUAGES`, and the `.translation` path to `internationalization/locale/translations` in `project.godot`. Then list it under *Languages* on the Steam store page (interface + subtitles).

## Adding an item

1. Create `resources/items/<id>.tres` (an `ItemDefinition`; `id` must equal the file name, lowercase `[a-z0-9_]`). Holdable items point `held_scene` at a scene under `objects/items/` whose root is a `Node3D`; a light source is just an `OmniLight3D` inside that scene (see `held_torch.tscn`).
2. Add the id to `ITEMS` in `nakama/modules/world_match.lua` (and to `STARTING_ITEMS` / `ItemRegistry.STARTING_ITEMS` if every character should start with it).
3. Add `ITEM_<ID>_NAME` / `ITEM_<ID>_DESC` rows to `localization/translations.csv`.
4. `godot --headless --path . tests/run_tests.tscn`.

### Adding a spell

1. Copy `resources/spells/glowmote.tres` to `resources/spells/<id>.tres`; set `id`, `effect_type`, numbers and colour. Optional: a `burst_scene` (spawned where the projectile ends) or a custom `projectile_scene`.
2. Append the id to `SpellRegistry.SPELL_IDS` (`gameplay/spells/spell_registry.gd`) — the list is explicit so exported builds and the network id check agree.
3. Add `SPELL_<ID>_NAME` / `SPELL_<ID>_DESC` rows to `localization/translations.csv`.
4. Give it a way to be learned: a row in `PRACTICE_TOMES` in `tools/generate_castle.py` (then regenerate the castle) until lessons grant spells. Add the id to `M.SPELLS` in `nakama/modules/character_profile.lua` too, or the server will refuse to grant or relay it.
5. Make objects react by listing the effect type in their `SpellReceiver.accepted_effect_types` and branching on `effect.effect_type`.
6. `godot --headless --path . tests/run_tests.tscn` (checks the registry, translations and that every spell has a tome).

Playtesting: `godot --path . -- --all-spells` spawns with every spell on the hotbar. Keys 1–0 select, Q/R cycle, LMB casts.

## Adding a character

1. In Meshy: generate (Standard, 2K) → Remesh **Fixed 15K, Triangle** → Rig (**Mixamo** template, height 1.8 m, markers on the real joints) → add the seven motions (idle, walk, run, jump, fall, land, cast, in place) → Download: glb, Mixamo, **Rigged Character on**, Animation **All Added**, **Single file on**.
2. Save as `assets/models/characters/<id>/<id>.glb` and import once: `godot --headless --path . --import`.
3. Build the visual scene: `godot --headless --path . -s tools/build_character.gd -- <id>` then import again (loop modes live in the `.import`).
4. Register the id in `characters/character_registry.gd` (and in `nakama/modules/world_match.lua` `CHARACTERS`), add a `CHAR_<ID>` row to `localization/translations.csv`. The build tool emits the `Wand` (right hand) and `OffHand` (left hand, held items) sockets.
5. `godot --headless --path . tests/run_tests.tscn` — the Characters section validates every registered body.

`--character=<id>` selects a body for one run (handy for two-client tests).

## Project settings of note

`project.godot` → `[game]`:

| Setting | Default | Meaning |
|---------|---------|---------|
| `game/network/host`, `port`, `scheme`, `server_key` | 127.0.0.1 / 7350 / http / defaultkey | Nakama endpoint (host/port editable on the menu; persisted in `user://settings.cfg`) |
| `game/network/state_send_rate` | 12 | Hz at which the local player broadcasts its state |
| `game/debug/enable_debug_overlay` | true | F3 overlay (also requires a debug build) |

## Conventions

- Typed GDScript, small scripts, signals over references.
- Gameplay reads InputMap actions only.
- Components register on their parent via `set_meta` (`spell_receiver`, `interactable`, `health`, `respawn_handler`).
- Nakama calls live under `multiplayer/` only.
- Placeholder assets: primitives + generated `.wav` tones; keep references in scenes/resources, not code.
- `docs/plan.md` is the tracker; update it with every meaningful change.
