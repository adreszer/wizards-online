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

Controls: WASD move · Shift run · Space jump · move the mouse to look (cursor captured) · scroll wheel zoom · left click / F cast · E interact · Tab satchel (inventory; click the torch to hold it, the broom to ride it) · M castle map (drag, wheel zoom, PgUp/PgDn floors) · B mount / land the broom (flying: the broom follows the mouse, W forward, Space up, C or Ctrl down, Shift faster, hold C on the ground to land) · Enter or T chat · Esc pause · ` (or F1; Fn+F1 on a Mac) free the cursor, e.g. for screenshots, and back to mouse look · F3 debug overlay.

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

The script calls the `admin_set_profile` RPC with `http_key=defaulthttpkey`; the same RPC is available to logged-in admins (the lesson tools do not expose it yet). To make an account an admin permanently, put its user id (console → Accounts) in `ADMIN_USER_IDS` in `nakama/local.yml` (comma-separated) and recreate the container. Only professors and admins can open the lesson tools (`L`). Teaching goes: stand in a subject's classroom, **Open lesson**, then teach students standing in the same room; only the room's subject's spells are listed and accepted. The same panel sends lecture lines to the room (typed, or **Next line** from a saved lesson plan) and awards or deducts house points with a reason; limits are in `nakama/content/school_rules.json`. To audit house points, call the `house_points_ledger` RPC (`curl -sS "http://127.0.0.1:7350/v2/rpc/house_points_ledger?http_key=defaulthttpkey&unwrap" -d '{}'`). Casts of spells a character does not know are dropped by the server, so promote yourself before expecting to demonstrate anything you have not learned from a tome.

Coins (the placeholder currency) are changed only on the server too:

```bash
tools/grant_coins.sh Elara 50 "helped at the open day"     # online player by display name
tools/grant_coins.sh 1c9a…-uuid -20 "lost library book"    # by user id (offline players too); never below zero
tools/grant_coins.sh --ledger 1c9a…-uuid                    # the purse and its history, newest first
```

Students earn coins by staying to the end of a lesson that ran at least `lesson_coin_minutes` and by a first solve of each mystery, up to `max_daily_coins` a school day (all in `nakama/content/school_rules.json`).

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

`tools/check.sh` runs the whole offline set in one go: it regenerates the castle and the server's generated content, fails if either differs from what is committed, then runs the script check and the gameplay tests (logs in `.godot/check/`). To run it before every push: `git config core.hooksPath tools/hooks`.

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

# the feature modules (detention, riddles, heads of house, clubs, games…): two clients again,
# A becomes an admin, B a student; they wait for each other through direct messages
godot --headless --path . tests/run_features_test.tscn -- --instance=1 --name=ClientA &
sleep 4
godot --headless --path . tests/run_features_test.tscn -- --instance=2 --name=ClientB --role=b

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
# the village and the station (street, square, shop and inn interiors, platform, portal, aerial) by day and night
godot --path . tools/capture_village.tscn -- --out=/absolute/output/dir [--hours=12,0]
```

Placed gameplay objects (practice tomes, plaques, fragments, checkpoints, guardians, the sorting stone, puzzle pieces) live in `content/placements.json`, keyed by area id; the header of the placement section in `tools/castle/build.py` documents the position modes (`slot: centre`, `at`, `wall`/`along`, `corner`/`inset`, `door`/`along`/`inset`, `beside_lectern`; every position must land inside its room) and `KINDS` lists the scenes. Each entry becomes a node with the stable object id `"<area>/<id>"` (`object_id` on the instance, `world_objects` group); secret walls are `"<hidden room>/secret_wall"`, house gates `"<area>/house_door"`, torches `"<room>/torch_<n>"` (counted per room, so don't build mysteries on them). The generator refuses duplicate ids, unknown areas, kinds or spells. After regenerating, re-run the exporter: `generated/world_objects.lua` (id → kind, areas, position, accepted effect types) is read from the built castle.

Server content: lists the Nakama runtime needs from the client (spell ids and numbers, the item catalogue and starting kit, the sorting questionnaire, character ids, protocol op codes and RPC names) are generated into `nakama/modules/generated/` by `godot --headless --path . tools/export_server_content.tscn`. Never edit those files; change the client source and re-export. Lua requires them as `require("generated.<name>")`. Restarting Nakama picks them up; when the dev container was started from another worktree, recreate it from this one: `docker compose -p init up -d --force-recreate nakama postgres`.

Performance: `godot --path . tools/perf_castle.tscn -- [--copies=5] [--no-batch] [--out=/abs/report.json]` (windowed) prints instancing time, node and body counts and per-view frame time, draw calls and primitives; five copies is the target-scale stress fixture.

Layout seeds: the castle's wings are generated from `layout` in `content/castle/program.json`; `python3 tools/generate_castle.py --search 24 --seed 1` lists seeds that pass every rule, `--seed N` builds another one without editing the program. Generated room names land in `localization/castle_generated.csv` (registered in project.godot; never edit it by hand).

The generator needs Python 3 with numpy (`pip3 install numpy`) for the grounds. Regenerating the castle after editing its program (`content/castle/program.json`; `python3 tools/generate_castle.py` from the project root, `--check` to validate only, `--preview` for SVG plans in `.godot/castle_preview/`) rewrites `levels/castle/castle.tscn` and `nakama/modules/world_areas.lua` (restart Nakama to pick the latter up); hand edits belong in the program, the generator, `objects/`, or `levels/castle/castle.gd`. `tools/check.sh` also runs the generator's Python tests (`python3 -m unittest discover -s tools -p 'test_*.py'`) and the forbidden-name scan (`cd tools && python3 -m castle.denylist`; add a word with `--add WORD`, only its hash is stored). New rooms need an `AREA_<ID>` row in `localization/translations.csv` (the castle test fails on a missing name).

Adding a new environment module: drop the GLB under `assets/models/…` (never edit it in-repo), run `inspect_model.gd`, create a wrapper `.tscn` under `objects/environment/…` with the fitting transform + simple collision, and place instances in the validation scene before using them in a level. Conventions are in `docs/plan.md` → "Production environment asset pipeline". A new window type: drop the GLB, make `objects/environment/windows/<id>.tscn` with a `WindowFrame` root (origin at the frame's bottom centre, mid-depth on z = 0, the room-side face on +Z) and fill in its outline (`half_width`, `spring`, `apex` per arch, `arches` + `arch_pitch` for several side by side, measured from the mesh); `WallWindow.window_scene` then cuts the matching opening into the wall by itself. Prefer models with open lights and set `glass = true`: Meshy's remesh tears near-zero-thickness glass sheets into shards, and the generated pane can't tear. Map room kinds (`WINDOW_TYPES`) or single rooms (`WINDOW_ROOMS`) to window types in the generator. To measure an outline, slice the triangles at several heights (vertex sampling misses the long flat sides of a remeshed frame). Check it in section F of the validation scene. A raw Meshy prop (hundreds of thousands of triangles) goes through `blender -b --factory-startup --python tools/prep_meshy_prop.py -- --src raw.glb --out assets/models/…/<id>.glb --tris 10000 [--scale x,y,z]` first: it welds the mesh before decimating, which keeps Meshy's UVs intact (decimating the unwelded glTF import leaves bright stretched slivers all over the texture). Dressing props (`props` roles in `content/castle/kit.json`) put their origin at the back-bottom-centre with the front on +Z. A role may list several scenes (the portraits); the generator hangs them in turn.

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

### Cheats (playtesting)

Open the chat (Enter or T; works offline too) and type a command:

- `/broom` or `/miotla`: a flying broom (B to fly)
- `/give <item id>` (`/daj`): any item from `ItemRegistry.ITEM_IDS`
- `/plan` (`/lekcje`, `/timetable`): opens the timetable (online only; offline there is none)
- `/coins [±n]` (`/korony`): shows your purse, or adds (minus: takes) coins; online through the server (cheats_enabled or admins), offline a practice purse
- `/goto <place>` (`/idz`, `/tp`): jumps to `station` (`stacja`), `village` (`wioska`), `castle` (`zamek`) or any area id (`sweet_shop`, `great_hall`…); offline always, online professors and admins only
- `/time` (`/czas`): the school time; `/time 14:30`, `/time dawn|day|dusk|night` (`swit|dzien|zmierzch|noc`) moves the clock (online: for everyone, and it stays moved across restarts)
- `/help` (`/pomoc`): the list

Offline they change the local inventory. Online the server decides: admins always, everyone while `"cheats_enabled": true` in `nakama/content/school_rules.json` (the dev default; set it to false for a public server, then restart Nakama). Without a cheat, take a broom from the stand beside the spawn on the grounds or in the flying classroom. Brooms fly only outdoors (grounds, courtyards, open sky overhead); flying into a building lands you.

## Editing the timetable

The school week lives in `nakama/content/timetable.json` (server only; it never ships in the client). Each slot is weekly, in school time (Warsaw: `utc_offset_minutes` 60 plus `"dst": "eu"`):

```json
{ "id": "mon_charms", "day": "mon", "start": "18:00", "minutes": 45, "subject": "sigilcraft", "professor": "Vexley" }
{ "id": "sun_study", "day": "sun", "start": "17:00", "minutes": 90, "kind": "study", "room": "library" }
```

`subject` is a subject id (`resources/school/subjects/`); the room defaults to the subject's first classroom (`room` overrides it with any area id); `professor` is optional text for the boards. After editing, either restart Nakama or reload it live:

```bash
curl -s "http://127.0.0.1:7350/v2/rpc/admin_reload_timetable?http_key=defaulthttpkey&unwrap" -d '{}'
```

Slots that name an unknown subject, room, day or time are left out and logged (`docker logs wizards-nakama | grep timetable`). `run_tests.tscn` also checks the shipped file.

## Adding an item

1. Create `resources/items/<id>.tres` (an `ItemDefinition`; `id` must equal the file name, lowercase `[a-z0-9_]`). Holdable items point `held_scene` at a scene under `objects/items/` whose root is a `Node3D`; a light source is just an `OmniLight3D` inside that scene (see `held_torch.tscn`). Rideable items (brooms) set `mount_scene` instead (origin at the seat, facing -Z; see `broom.tscn`). To hand an item out in the world, place an `item_rack` with `"set": {"item_id": "<id>"}` in `content/placements.json`.
2. Add the id to `ItemRegistry.ITEM_IDS` (and to `ItemRegistry.STARTING_ITEMS` if every character should start with it).
3. Add `ITEM_<ID>_NAME` / `ITEM_<ID>_DESC` rows to `localization/translations.csv`.
4. `godot --headless --path . tools/export_server_content.tscn` (the server's catalogue is generated from the registry), then `tools/check.sh`.

### Adding a spell

1. Copy `resources/spells/glowmote.tres` to `resources/spells/<id>.tres`; set `id`, `effect_type`, numbers and colour. Optional: a `burst_scene` (spawned where the projectile ends) or a custom `projectile_scene`.
2. Append the id to `SpellRegistry.SPELL_IDS` (`gameplay/spells/spell_registry.gd`) — the list is explicit so exported builds and the network id check agree.
3. Add `SPELL_<ID>_NAME` / `SPELL_<ID>_DESC` rows to `localization/translations.csv`.
4. Give it a way to be learned: a `spell_tome` entry in `content/placements.json` (then regenerate the castle) until lessons grant spells.
5. Make objects react by listing the effect type in their `SpellReceiver.accepted_effect_types` and branching on `effect.effect_type`.
6. `godot --headless --path . tools/export_server_content.tscn` so the server knows the spell (restart Nakama), then `tools/check.sh` (checks the registry, the export, translations and that every spell has a tome).

Playtesting: `godot --path . -- --all-spells` spawns with every spell on the hotbar. Keys 1–0 select, Q/R cycle, LMB casts.

## Rigging a portrait sitter

Living portraits use Mixamo-named skeletons, like the players, so `SocialPose` gestures drive them. Scale the sitter to 1.8 m with feet on the ground and decimate it to ~30k triangles (Mixamo's upload limit is 10 MB). If its hands stand clear of the body, the Mixamo auto-rigger works: upload, place the markers, download FBX with **Original Pose**, then import it in Blender, apply rotation and scale on the armature (the FBX arrives in centimetres, rotated) and export GLB to `assets/models/portraits/`. Mixamo rejects figures whose hands hang against a robe; rig those with `blender -b --factory-startup --python tools/rig_sitter.py -- --src sitter.fbx --out assets/models/portraits/<id>.glb --joints '{...}'`, reading the landmarks off a front orthographic render (see the script's docstring). Check a raised arm before committing: cloth that is one surface with the arm stretches, and then the sitter needs regenerating in a T-pose (put "T-pose character model, arms extended horizontally" first in the Meshy prompt; Meshy ignores a pose asked for at the end). For a T-posed sitter pass a wide `arm_radius` (`[0.3, 0.4]`) so sleeves and thumbs stay on the arm. Paint its portrait from the rig with `blender -b --factory-startup --python tools/render_portrait.py -- --src assets/models/portraits/<id>.glb --out assets/textures/portraits/portrait_<id>.jpg --pose relaxed` (the portrait studio and oil varnish; `--pose relaxed` folds a T-pose's hands in front). Add the id to the sitter loop in the Portraits test.

## Adding a character

1. In Meshy: generate (Standard, 2K) → Remesh **Fixed 15K, Triangle** → Rig (**Mixamo** template, height 1.8 m, markers on the real joints) → add the seven motions (idle, walk, run, jump, fall, land, cast, in place) → Download: glb, Mixamo, **Rigged Character on**, Animation **All Added**, **Single file on**.
2. Save as `assets/models/characters/<id>/<id>.glb` and import once: `godot --headless --path . --import`.
3. Build the visual scene: `godot --headless --path . -s tools/build_character.gd -- <id>` then import again (loop modes live in the `.import`).
4. Register the id in `characters/character_registry.gd` (re-run `tools/export_server_content.tscn` so the server accepts it), add a `CHAR_<ID>` row to `localization/translations.csv`. The build tool emits the `Wand` (right hand) and `OffHand` (left hand, held items) sockets.
5. `godot --headless --path . tests/run_tests.tscn` — the Characters section validates every registered body.

`--character=<id>` selects a body for one run (handy for two-client tests).

## Adding a mystery

1. Make sure every object it uses exists with a stable id: place new statues, levers, plaques… in `content/placements.json` (kinds in `KINDS`, `tools/castle/build.py`), regenerate the castle and re-export (`tools/export_server_content.tscn`).
2. Add the mystery to `nakama/content/mysteries.json` (format documented at the top of `nakama/modules/mysteries.lua`) and its text to `nakama/content/strings.json`, both languages. Never put mystery text in `localization/translations.csv`: it ships with the game.
3. `tools/check.sh`: the "Mysteries" test section checks objects, areas, effect types, items and texts, and that no server text is in the CSV.
4. Restart Nakama; the log says `mysteries: N loaded` (and names any mystery it refused). `tools/reset_world.sh` re-arms shared mysteries and objects while playtesting.

Offline mode has no server, so the real mysteries do not run there. Instead `content/offline_mysteries.json` (public, ships with the game, text via `OFFLINE_MYST_*` keys in the CSV) gives the secret walls their own simpler practice solutions, run by `OfflineMysteryEngine`. Never reuse an online solution offline: the offline file can be read by anyone.

## Release builds

`export_presets.cfg` holds the client presets (Windows Desktop, macOS) with the filters that keep server content out: `nakama/`, `tools/`, `tests/`, `docs/`, the dev/test levels and the placement source are excluded; `content/offline_mysteries.json` is included explicitly. Signing settings are added locally and never committed. Before shipping a build run `tools/check_build.sh` (needs the export templates): it exports a pack, lists its files (`tools/list_pck.py`) and fails if any server or dev file is inside or if any server-only text or mystery id appears in its bytes.

## Adding an enemy

1. Rig and animate in Meshy as for a character (Mixamo rig; at least idle, walk or run, an alert and an attack clip). Save as `assets/models/characters/<id>/<id>.glb`, import once.
2. Copy `characters/enemies/crystal_guardian.tscn`, point `Model` at the new GLB and set the `clips` map on the root (`Enemy`) to the clip names in the file (`godot --headless --path . -s tools/inspect_model.gd -- res://assets/models/characters/<id>/<id>.glb` lists them). Tune `attack_hit_time` to the frame where the blow lands.
3. Add an `ENEMY_<ID>_NAME` row to `localization/translations.csv` and set `name_key`.
4. Place it: add `crystal_guardian`-style entries to `content/placements.json` (`"at": [dx, dz]` from the room centre, `"yaw"`), with a new kind in `KINDS` in `tools/castle/build.py` if it is a new scene, and regenerate the castle.
5. `godot --headless --path . tests/run_tests.tscn` — the Enemy section drives the guardian through detection, a blow, spell damage, death and respawn; the castle test counts the placed guardians.

Enemies are local per client for now (see docs/architecture.md → Enemies).

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
