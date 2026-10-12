# Content pipeline: data-driven school content and server-only secrets

Goal: make new spells, subjects, lessons, placed objects and **mysteries** mostly data, with one source for every list the client and the Nakama server both need. Secrets and rewards must not ship in the Steam build. The ideas come from RimWorld's Def system (data says *what* exists; a small set of code "workers" says *how* each kind behaves), adapted to this project's split between a Godot client and a Lua server.

Proposed milestones 18–23 continue `docs/plan.md`.

**Implementation decisions** (taken while planning the build; `docs/plan.md` tracks progress):
- `world_objects.lua` is written by the Godot exporter from the built `castle.tscn`, not by the Python generator, so the accepted effect types stay on each scene's `SpellReceiver`.
- Server-only strings are `strings.json` (`{key: {pl, en}}`), not CSV; the same validator rules apply.
- Server content stays in `nakama/content/` as planned: `nk.file_read` resolves paths relative to the module directory, so the match reads `../content/<file>` (verified).
- Generated modules are required as `require("generated.<name>")` (Nakama names modules in subfolders with dots; verified).

## What is already data-driven

A lot. Keep these patterns:

- **Spells** are `SpellDefinition` resources (`resources/spells/*.tres`). Objects react to an `effect_type` vocabulary, never to a spell name, so adding a spell is a `.tres` + a registry row + translation keys.
- **Items** are `ItemDefinition` resources. **Enemies** are a scene + clip map, with no per-enemy code.
- **The castle** is generated from a declarative plan (`tools/generate_castle.py`), which also writes the server's area map (`nakama/modules/world_areas.lua`). `AreaZone` kinds and houses drive server rules.
- Components find each other by meta (`SpellReceiver.find_on`, `Interactable.find_on`), and all text goes through `localization/translations.csv`.

## Gaps

| Gap | Where | Cost |
|---|---|---|
| **Lists mirrored by hand** between GDScript and Lua | `SpellRegistry.SPELL_IDS` ↔ `M.SPELLS` (`nakama/modules/character_profile.lua:5–19`); `HouseSorting.QUESTIONS` ↔ `M.SORTING` (`character_profile.lua:23`); op codes in `multiplayer/network_protocol.gd` ↔ `world_match.lua:34–36` | Forgetting one side gives silent bugs: the server rejects a valid spell, sorting results differ online and offline, a message goes to the wrong handler. |
| **Gameplay placement is written in generator code** | `PRACTICE_TOMES`, `ENEMIES` (`generate_castle.py:890`, `:905`), the `secret(...)` calls (`:349–355`), plaques and fragments | Placing a tome or enemy means editing Python. Placed objects have no stable id, so the server can't refer to "that lever". |
| **Puzzles and secrets are local and hand-wired** | Puzzle state is "local only" (architecture.md, Authority table); `levels/castle/castle.gd` wires every `SecretWall` to one notification | Each multi-step mystery needs code. Any client can open any secret locally. Players don't see the same castle. |
| **No content model for school life** | plan.md M16 open items: lesson sessions, house points, timetables | Each will be built as one-off code unless a shape is set now. |
| **Everything ships to players** | `castle.tscn`, `translations.csv` | Once mysteries have clues and solutions, data-mining the build spoils them. |

## Principles

1. **Godot owns presentation; data owns rules.** Scenes, meshes, colours, sounds and projectile feel stay in `.tres`/`.tscn`, where the editor is best. Anything the **server** must know (ids, which subject teaches what, rewards, mystery steps) has exactly one source.
2. **One source, generated mirrors.** The server never gets a hand-written copy of a client list. A headless Godot exporter writes the Lua side, just as `generate_castle.py` already writes `world_areas.lua`. CI fails if generated files are stale.
3. **Shared vs. server-only.** Content the client needs ships. Solutions, rewards and clue text live only under `nakama/` and are sent to players when earned.
4. **Stable ids for everything placed in the world**, so server rules can name objects.
5. **Server decides, client renders.** This extends the pattern already used for spell grants and sorting to world objects.

## Design

### A. One source for shared lists (exporter)

`tools/export_server_content.gd` runs headless (`godot --headless tools/export_server_content.tscn`). It loads the client-side sources and writes `nakama/modules/generated/*.lua`:

| Source (client, editable in Godot) | Generated for the server |
|---|---|
| `resources/spells/*.tres` (via `SpellRegistry.all()`) | `spells.lua`: id → `{effect_type, subject, cooldown, range, strength}`. Cooldown and strength matter once duels are server-checked. |
| `resources/items/*.tres` | `items.lua`: id → `{holdable, max_stack, burn_seconds}` |
| Sorting questions: move `HouseSorting.QUESTIONS` into `resources/school/sorting.tres` | `sorting.lua` |
| `resources/school/subjects/*.tres` (new, see D) | `subjects.lua` |
| `NetworkProtocol` constants (read with `get_script_constant_map()`) | `protocol.lua`: no more hand-numbered `OP_*` locals in `world_match.lua` |

- `character_profile.lua` and `world_match.lua` `require` the generated modules instead of keeping their own tables.
- The registries stay explicit lists, as the comment in `spell_registry.gd` intends, but the exporter is now the check that every id in a list has its `.tres` and the reverse.
- **CI / pre-push:** run the exporter and the castle generator, then `git diff --exit-code nakama/modules/generated levels/castle nakama/modules/world_areas.lua`.

### B. Placement data and stable object ids

- **Move gameplay placement out of `generate_castle.py` into `content/placements.json`**, keyed by area id. That covers practice tomes, enemies, plaques, collectibles, levers, statues and mystery objects. The room plan itself (rooms, doors, stairs, towers) stays in Python: it's already a declarative DSL with helpers like `tower()`, and moving it to JSON would only lose those helpers.
- Every placed interactable gets an **`object_id`** (`"<area>/<name>"`, e.g. `class_glyphs/lever_east`), set as an exported property on the instance. `SecretWall`, `MagicDoor`, `Lever`, `PressurePlate`, `RotatingStatue`, `SpellTome` and `PushableBlock` gain `@export var object_id: String`.
- The generator writes **`nakama/modules/world_objects.lua`**: object id → `{kind, area, position, accepts = {effect types}}`. The server can then validate that a player is in the object's area and, later, within range.

```json
{
  "class_glyphs": [
    {"id": "tome_unbolt", "scene": "spell_tome", "spell": "unbolt", "at": [0, 0]},
    {"id": "lever_east", "scene": "lever", "wall": "e", "along": 0.3}
  ],
  "cellars": [
    {"id": "guardian_a", "scene": "crystal_guardian", "at": [4, -4], "yaw": 90}
  ]
}
```

### C. Server-authoritative world objects

This replaces the "puzzle / door state: local only" limitation and is what mysteries depend on.

- **New op codes:**
  - client → server `OP_WORLD_EVENT {object_id, event, effect_type?}`, where `event` is `interact | spell | enter | press`
  - server → clients `OP_OBJECT_STATE {object_id, state}`
  - a full `{object_id: state}` snapshot in the join payload, so late joiners see open doors
- **The server validates every event:** the object exists, the sender's reported area is the object's area, the effect type is one the object accepts, the sender knows the spell, and the event passes a rate limit. Only then does it change state and broadcast.
- **Clients apply state through the existing handlers.** The receivers are already signal-driven, as plan.md intended, so a door opens the same way whether a local switch or the server triggered it. When a world match is active, local triggers only *request*; offline they act directly, as now.
- **Physics objects stay local for now.** `PushableBlock` and enemies keep their local simulation; only discrete states (open/closed, lit/unlit, revealed, solved) are authoritative. Server-driven enemies stay a separate later item (M17 open items).

### D. School content model

- **`SubjectDefinition` (`resources/school/subjects/*.tres`, shared):** id, name/description keys, classroom area ids (`class_sigilcraft`…), colour/crest, and spells it teaches by year. The `ProfessorPanel` lists only the spells of the subject whose classroom the professor is in.
- **Lesson sessions (server rules, `nakama/content/school_rules.json`):**
  - A professor opens a session in a classroom; spell grants are only valid during an open session in that subject's classroom. This replaces "any staff in any classroom" (plan.md M16).
  - Attendance is recorded from area reports.
  - Each session has a cap on points awarded and a cooldown.
- **House points ledger:** Nakama storage of `{house, delta, reason, by, at}` records plus a per-house total object. The total can always be explained, and deductions use the same path.
- **Lesson plans written by professors** (lecture text, questions) live in **Nakama storage per professor**, written in game. They're never in the build, which also keeps them out of `translations.csv`.
- **Later:** timetables and terms as data (`nakama/content/calendar.json`), on the same pattern.

### E. Mysteries as data (server-only)

`nakama/content/mysteries.json` is read by the server at module load (`nk.file_read` + `nk.json_decode`, or generated into a Lua table like `world_areas.lua`). A small Lua engine in `nakama/modules/mysteries.lua` subscribes to validated world events.

```json
{
  "id": "chronicles_hidden_study",
  "scope": "world",
  "steps": [
    {"object": "class_chronicles/statue_a", "event": "spell", "effect_type": "force", "until": "rotated_3"},
    {"object": "class_chronicles/plaque_dates", "event": "interact", "reveal_text": "MYST_CHRON_CLUE_1"},
    {"area": "class_chronicles", "event": "enter", "holding": "torch", "within_seconds": 60}
  ],
  "on_solved": {
    "set_state": {"class_chronicles/secret_wall": "revealed"},
    "discovery": "hidden_study",
    "house_points": 5,
    "notify": "MYST_CHRON_SOLVED"
  },
  "reset_after_minutes": 30
}
```

- **Step types:**
  - spell of an effect type on an object
  - interact
  - enter an area (optionally while holding an item)
  - an ordered sequence across objects
  - "N players at once": cooperation, which `CLAUDE.md` asks for
- **`scope`** is `world` (one shared state, resets after a while), `player` (each player solves it for themselves; progress stored per user) or `house`.
- **Rewards:** a discovery record on the character, house points through the ledger, and object state changes.
- **The three existing secret passages** (`generate_castle.py:349–355`) become the first mysteries. Their walls stay in the scene; what opens them moves to data.

### F. Server-only text, offline mode and the Steam build

- **Server-only strings:** `nakama/content/strings.csv` (`keys,en,pl`) holds clues, mystery messages and reward text. The server sends **resolved text** in the player's language (add `locale` to the session vars), so these keys never appear in `translations.csv`. Validator rule: a key used by server content must not exist in the shared file.
- **Offline mode** has no server, so it gets no server-only mysteries. Ship a small *public* practice set (`content/offline_mysteries.json`, run by a GDScript port of the same step engine) so offline mode still has puzzles, and keep real mysteries online-only. Offline mode is already a reduced experience, so this is acceptable.
- **Export presets (none yet):** Godot exports imported resources only, plus `include_filter`. `.lua` and `.json` under `nakama/` are left out by default, but don't rely on that. Set `exclude_filter="nakama/*, tools/*, tests/*"` on the client preset, and add `content/*.json` to `include_filter` explicitly for the shared JSON.
- **Leak check in CI:** export the client `.pck` headless, list its files, and fail if anything under `nakama/` or any server-string key is inside.
- **What can't be hidden:** the geometry of hidden rooms is in `castle.tscn`, and anything the server sends is visible on the network. That's accepted. Design mysteries so that knowing *where* isn't enough: they need the right spell, an order of steps, an item, or several players, all checked by the server.

## Milestones (continue plan.md)

Estimates assume part-time solo work. Each milestone keeps `tests/run_tests.tscn` and the multiplayer tests passing.

### Milestone 18 — One source for shared lists (≈1 week) — done
- [x] `tools/export_server_content.gd`: spells, items, sorting, characters, protocol → `nakama/modules/generated/*.lua`
- [x] Sorting questions into a resource; `character_profile.lua` / `world_match.lua` / `world.lua` require the generated modules
- [x] Freshness check (exporter + castle generator + `git diff --exit-code`) in `tools/check.sh`, plus a stale-export test in `run_tests.tscn`
- **Done when:** no "mirrors X" comments remain. Adding a spell is one `.tres` + translation keys, and the server accepts it without editing Lua.

### Milestone 19 — Placement data and object ids (≈1–2 weeks) — done
- [x] `content/placements.json`; generator reads it instead of `PRACTICE_TOMES` / `ENEMIES` / plaques / fragments
- [x] `object_id` on every interactable; the exporter writes `world_objects.lua` from the built scene
- [x] Generator refuses duplicate ids, unknown areas and unknown scenes
- **Done when:** a tome or enemy can be moved by editing JSON and regenerating, and every interactable in `castle.tscn` has a unique id.

### Milestone 20 — Server-authoritative world objects (≈2 weeks) — done
- [x] `OP_WORLD_EVENT` / `OP_OBJECT_STATE` + join snapshot; server validation (area, effect type, known spell, rate limit)
- [x] Doors, secret walls, levers, torches, statues apply server state; offline path unchanged
- [x] Multiplayer test: client B flips a switch and client A sees it; the rejoining client sees it
- **Done when:** "Puzzle / door / collectible state: local only" is removed from the Authority table.

### Milestone 21 — Mysteries as data (≈2–3 weeks) — done
- [x] `nakama/modules/mysteries.lua` step engine (spell, interact, enter, holding, sequence, N players); scopes world/player/house
- [x] `nakama/content/strings.json`, locale in the join metadata, server sends resolved text
- [x] The three existing secret passages rebuilt as mysteries (the loft is the two-player one), plus a player-scoped plaque tale
- [x] Discovery records on the character profile
- **Done when:** a new mystery that uses existing object kinds needs no code, and none of its text or solution is in the client project's shipped files.

### Milestone 22 — Subjects, lesson sessions, house points (≈2–3 weeks) — done
- [x] `SubjectDefinition` resources for the existing classrooms; exported to `subjects.lua`
- [x] Lesson sessions (open/close, grants only inside an open session in the subject's classroom, attendance)
- [x] House points ledger + award/deduct in `ProfessorPanel` + a visible tally
- [x] Professor lesson plans stored in Nakama
- **Done when:** the M16 open item "tie grants to a lesson session" is closed, and house points can be explained record by record.

### Milestone 23 — Release hygiene (≈1 week, before the first Steam build)
- [ ] Client export preset with include/exclude filters; server content never in the `.pck`
- [ ] `.pck` leak check in CI
- [ ] Offline practice mysteries
- **Done when:** the leak check passes on an exported build.

**Total: about 9–12 weeks part-time.** M18 pays off immediately and is low-risk. M20 is the foundation for everything secret-related, so it's worth doing before adding more puzzles.

## Deliberately not planned

- **Converting the room plan to JSON.** The Python DSL is already declarative and has useful helpers.
- **Replacing `.tres` with JSON for presentation.** The editor workflow is worth keeping.
- **A general mod/patch system** (RimWorld-style XPath patches). Not needed until there is a modding audience.
- **Server-simulated physics.** Discrete object states cover puzzles. Server-driven enemies are a separate item.
