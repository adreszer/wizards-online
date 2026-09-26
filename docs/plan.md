# Implementation Plan — Arcanum Halls MVP

Authoritative implementation tracker. Updated continuously as work progresses.

Legend: `[ ]` not started · `[~]` in progress · `[x]` complete

## Architecture overview

Godot 4.7 project (GDScript, static typing) with an optional Nakama backend (Docker Compose: Nakama + PostgreSQL).
See `docs/architecture.md` for the full breakdown. In short:

- **core/** — game root scene (menu → world swap), global event bus, session state.
- **characters/player/** — composed player: movement, input intent, camera rig, visual + animation controller, spell caster, interaction controller, health, respawn, network synchronizer, nameplate. Local-only nodes live under `LocalPlayer`, removed for remote players.
- **gameplay/** — reusable components: spells (definition/caster/projectile/receiver/effect), interaction (Interactable/InteractionController), collectibles, health, checkpoints/hazards.
- **objects/** — level mechanics built by composition (SpellReceiver/Interactable children): switch, door, pushable block, pressure plate, rotating statue, moving platform, secret wall, lever, plaque, spell tome, greybox blocks.
- **multiplayer/** — `NetworkManager` autoload is the only networking boundary: authentication, world session (Nakama authoritative match), state synchronizer, chat manager. Gameplay never calls Nakama directly.
- **nakama/** — Lua runtime module: one persistent "world" match that relays presence/state/spell events and owns the player roster.
- **ui/** — main menu, HUD, chat panel, pause menu, F3 debug overlay.
- **levels/mvp/** — greybox vertical slice.
- **assets/models/** — imported source models (GLB) exactly as produced by the art pipeline; never edited in-repo.
- **objects/environment/** — wrapper scenes that turn a source model into a placeable module (transform, collision, layers).
- **levels/dev/** — development-only scenes (asset validation); not part of the game flow.
- **tools/** — headless/dev utilities (model inspection, screenshot capture).

## Milestones

### Milestone 1 — Foundation
- [x] Godot project file, feature tags, physics (Jolt), rendering defaults
- [x] Repository directory structure
- [x] Vendor Nakama Godot client addon (`addons/com.heroiclabs.nakama`)
- [x] InputMap actions: move_*, jump, sprint, cast, interact, chat, pause, debug_overlay (keyboard + joypad bindings)
- [x] Physics layer names
- [x] Docs: plan.md, architecture.md, development.md, README.md
- [x] Autoloads: GameEvents, GameSession, NetworkManager (documented in architecture.md)
- [x] Game root scene + test/sandbox scene

### Milestone 2 — Player
- [x] PlayerInput (intent from InputMap, camera-relative)
- [x] PlayerMovement (walk/run/jump/gravity/slopes/stairs/air control/accel/decel/landing)
- [x] Camera rig (yaw/pitch, sensitivity, distance, height, limits, smoothing, SpringArm collision)
- [x] CharacterVisual placeholder + AnimationTree state machine (idle/walk/run/jump/fall/land/cast)
- [x] AnimationController decoupled from movement via state signals
- [x] Local vs remote player split (`LocalPlayer` subtree)

### Milestone 3 — Gameplay components
- [x] Health component (damage/heal/death signals)
- [x] Checkpoint + RespawnHandler + KillZone/DamageZone hazards
- [x] Interactable + InteractionController + prompt
- [x] Collectible + CollectibleDefinition + counter in GameSession + HUD

### Milestone 4 — Magic
- [x] SpellDefinition resource (Arcane Pulse data)
- [x] SpellCaster (center-screen aim, aim assist, range, cooldown, learn spell)
- [x] SpellProjectile + SpellEffect
- [x] SpellReceiver component (composition, signal-driven)
- [x] Cast events routed for network replication

### Milestone 5 — Level mechanics
- [x] Magic switch
- [x] Magic door
- [x] Pushable block + pressure plate
- [x] Rotating statue + statue puzzle
- [x] Moving platform (points, speed, loop, activation, carries player)
- [x] Hazards (kill zone, damage zone)
- [x] Secret wall mechanism
- [x] Lever, plaque, spell tome (non-spell interactables)

### Milestone 6 — Vertical slice
- [x] Greybox level: Entrance → Corridor (secret) → Training → Puzzle → Platforming → Final Puzzle → Reward
- [x] ~10 Arcane Fragments incl. several in secret room
- [x] Checkpoints per chamber
- [x] Offline playthrough verified headlessly (level wiring + spawn/end trigger); user playtest in progress

### Milestone 7 — Backend
- [x] docker-compose.yml (Nakama + PostgreSQL)
- [x] Nakama Lua module: world match handler + `join_world` RPC
- [x] Device authentication + display name
- [x] Graceful failure when backend is down

### Milestone 8 — Multiplayer
- [x] World session join/leave
- [x] PlayerSpawner (local + remote)
- [x] State synchronizer (12 Hz, position/yaw/velocity/movement state)
- [x] Remote interpolation
- [x] Animation replication via movement state
- [x] Spell cast replication
- [x] Join/leave roster from server

### Milestone 9 — Chat
- [x] Nakama room channel join
- [x] Chat UI (open/type/send/receive/close)
- [x] Input capture while typing
- [x] Max length + sanitization
- [x] Join/leave system messages

### Milestone 10 — Debugging & polish
- [x] F3 debug overlay (FPS, position, velocity, grounded, state, spell, target, online status, ping, player count)
- [x] Debug ray visualization toggle
- [x] Pause menu
- [x] Reconnect behavior
- [x] Error handling audit
- [x] Documentation pass
- [x] Final test pass documented below

### Milestone 11 — Production environment asset pipeline (in validation, not finalized)
- [x] First production asset: `assets/models/environment/modular/wall_plain.glb` (Meshy, untouched source)
- [x] Wrapper scene `objects/environment/modular/wall_plain.tscn` (normalised 4 × 4 × 0.35 m, bottom-centre pivot, box collision)
- [x] Dev validation scene `levels/dev/asset_validation.tscn` (single wall, 3× tiled, 90° corner, player scale, labels)
- [x] Headless wrapper test `tests/validate_wall_plain.tscn`; dev tools `tools/inspect_model.gd`, `tools/capture_validation.tscn`
- [x] Wall module used for every wall in the MVP level via `ModularWallRun` (34 runs, 126 modules); level regenerated by `tools/generate_level.py`
- [ ] In-game visual sign-off of the wall (seams, top edge, material) → decide whether this becomes the canonical workflow
- [ ] Decide seam strategy (see findings) before building more modules
- [x] Floor module: `assets/models/environment/modular/floor.glb` → wrapper `floor_tile.tscn` (4 × 4 × 0.46 m, top-centre pivot, box collision) → `ModularFloor` tiler; every level floor now tiled (11 areas, 158 tiles) over a greybox sub-floor
- [x] Second floor variant `floor2.glb` → `floor_tile_2.tscn` (4 × 4 × 0.36 m); used in the training room, secret room and reward room so special areas read differently
- [ ] Floor meshes are 395,742 (floor) and 224,608 (floor2) triangles per tile (wall: 3,031). With 158 instances this is the dominant render cost; re-export at ≤10k triangles (bake detail into the normal map) before more floors are placed
- [ ] Corner / pillar module, doorway module

## Production environment asset pipeline (in validation)

**Pattern.** Every imported model stays a clean source asset under `assets/models/…` with Godot's default import settings (no manual texture resizing, mesh edits or material regeneration). A wrapper `.tscn` under `objects/environment/…` instances the model and owns everything engine/gameplay-specific: the fitting transform, collision, physics layers, and later LODs, occluders and metadata. Levels only ever instance the wrapper. Re-exporting the model from the art tool replaces the GLB and nothing else changes.

**Module convention (`wall_plain.tscn`).**
- Final size 4.0 m wide (X) × 4.0 m high (Y) × 0.35 m deep (Z). The GLB is unrotated; width is already along X.
- Pivot: bottom-centre — origin on the floor, centred on width and depth. Rotating a wall by 90°/180° keeps it on the same grid line, which is why depth is centred rather than pushed to one side.
- Grid placement: a wall's origin sits on the midpoint of a 4 m grid edge, y = 0. Walls along X: `(4i + 2, 0, 4j)` rotation 0. Walls along Z: `(4i, 0, 4j + 2)` rotation 90° about Y. Straight runs need no offsets.
- Corner rule (butt joint): the continuing wall is shifted by half the depth (0.175 m) so its end cap sits flush with the outer face of the terminating wall, e.g. `WallX` at `(18, 0, 0)` and `WallZ` at `(20.175, 0, 1.825)` rotated 90°. Placing both strictly on the grid instead leaves a 0.175 m notch on the outer corner (inherent to centred depth); a corner pillar module would remove the offset rule.
- Collision: a single `BoxShape3D` 4 × 4 × 0.35 on physics layer 1 (`world`), mask 0, same as `GreyboxBlock`. The detailed stone geometry is never used for collision.

**Wrapper transform (derived from the imported AABB with `tools/inspect_model.gd`).**

| | Imported (scene units) | Wrapper scale | Final |
|---|---|---|---|
| Width X | 1.9025 (−0.9526 … 0.9499) | 2.102529 | 4.000 m |
| Height Y | 1.7435 (−0.8735 … 0.8701) | 2.294190 | 4.000 m |
| Depth Z | 0.2940 (−0.1471 … 0.1469) | 1.190581 | 0.350 m |

Offset `(0.002863, 2.003874, 0.000124)` moves the model's bounding box to bottom-centre. Scale is non-uniform (Y is 9 % larger than X, Z 43 % smaller) because the Meshy export's aspect does not match the intended module; the stones therefore read slightly taller and shallower than authored. If that is unwanted the fix belongs in the art tool, not the wrapper.

**Validation scene** `levels/dev/asset_validation.tscn` (run with `godot --path . levels/dev/asset_validation.tscn`): A single wall at x = −6, B three walls at x = 2, 6, 10 (12 m run), C corner at x = 16…20.35, D the regular player spawned at (4, 0, −7) facing the tiled run. Lighting is a warm key light + ambient + three torch-coloured omni fills + SSAO — neutral enough to judge colour, roughness, normal detail and silhouette. Floor is a 4 m checkerboard of greybox tiles as a grid reference.

**Findings (first pass, Godot 4.7.2, default import).**
- Import: one node, one `ArrayMesh` surface, 3031 triangles, 6083 vertices. One `StandardMaterial3D` ("BakedMaterial"): base colour 2048², metallic-roughness 4096² (metallic = blue channel, roughness = green, factors 1.0). No normal map, no AO, no emission. Import generated LODs and a shadow mesh (defaults).
- Material: opaque (no transparency), `cull_mode = Disabled` because the glTF flags the material double-sided. Renders correctly but costs back-face rasterisation on a closed mesh; worth switching to back-face culling in the exporter or via an import material override once the workflow is fixed.
- Normals: unit length, all face windings agree with the vertex normals (0 flipped of 3031). No visible shading breaks; normal detail comes from geometry only (no normal map).
- Textures: both PNGs embedded in the GLB (5.6 MB + 9.3 MB); Godot imported them as VRAM-compressed `.ctex`. The metallic-roughness map is 4× the pixel count of the base colour and mostly flat — an obvious later optimisation, deliberately not applied yet.
- Tiling: three walls at exact 4 m spacing align on the grid. A thin see-through line is visible at each seam: the end caps are bevelled stones, so the end face sits inside the bounding box. Measured front-silhouette gap between neighbours: 8–26 mm (median 14 mm) over the wall height. Options: (a) overscale the visual by ~0.5 % in X in the wrapper so the bevels overlap, (b) ask Meshy/Blender for flat, full-height end caps, (c) accept and hide with pillars. Not changed yet — decision pending visual review.
- Top edge: uneven stone tops, up to 29 mm below 4.0 m (median 3 mm). A ceiling or second row placed at y = 4 would show slivers. Bottom sits within 1–9 mm of the floor: fine.
- Corner: the butt joint is flush on the outer face; the same bevel groove appears where the end cap meets the neighbouring face.
- Scale: 4 m wall ≈ 2.2× the 1.8 m player capsule; reads as a tall academy hall wall.
- Collision: player walks up to the face and stops at 0.35 m (capsule radius), cannot pass through, walks freely past the end.



| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Nakama Godot client vendored as an addon | It is the official client; hand-writing REST/WebSocket for Nakama would be a much larger risk. It is the only third-party dependency. |
| 2 | Jolt physics | Built into Godot 4.4+; better character/platform behavior than GodotPhysics3D. |
| 3 | Shared world = one Nakama **authoritative match** created by a Lua runtime module at server start | Client-relayed matches cannot be discovered by other clients. A server module also gives us the place to tighten authority later (validation, duels). |
| 4 | Presence roster owned by the server module | Display names arrive as match-join metadata; the server broadcasts roster changes so clients never trust another client's identity claims. |
| 5 | State sync at 12 Hz, JSON payloads, remote interpolation with a 120 ms buffer | Bandwidth-conscious, easy to debug. Binary packing is a later optimization. |
| 6 | Puzzle/level state is local-only in the MVP | Documented limitation. Objects already react through `SpellReceiver` signals, so a future server-driven trigger can call the same handlers. |
| 7 | Components discover each other via `parent.set_meta()` registration (`spell_receiver`, `interactable`) rather than hardcoded NodePaths | Any body/area gains behavior by adding a child component; projectiles and the interaction controller do a single meta lookup. |
| 8 | Three game autoloads (`GameEvents`, `GameSession`, `NetworkManager`) plus the addon's `Nakama` | Event bus, session-scoped state (mode, name, collectible counts), and the networking boundary are genuinely global. Nothing else is. |
| 9 | Greybox built from a `@tool` `GreyboxBlock` scene | Keeps the level `.tscn` compact and lets blocks be resized in-editor while auto-updating collision. |
| 10 | Device authentication | Zero-friction, stable per machine (`user://nakama_device_id`). Two clients on one machine get distinct IDs via a `--user-suffix` / env override (see development.md). |
| 11 | Hand-authored `.tscn` files | The whole project is generated headlessly; scenes are plain text and remain fully editable in the Godot editor. |
| 12 | Source models stay untouched under `assets/models/`; engine configuration lives in wrapper `.tscn` scenes under `objects/environment/` | Re-exporting art never touches gameplay data; wrappers carry transform, collision and layers. Pending sign-off (Milestone 11). |

## Manual verification log

- 2026-09-26: offline playthrough by the developer surfaced a bug (HUD crosshair swallowed mouse-look after learning the spell) — fixed, HUD controls now ignore mouse events.
- Bugs found by headless tests and fixed: step-up used the (already zeroed) velocity instead of the intended direction; step probe landed on the ledge edge (steep contact normal); scripted jumps were cut short by low-jump gravity; Nakama config `name` exceeded 16 chars; pressure plate closing a door during level teardown.

## Known limitations

- Puzzle/door/collectible state is local to each client in online mode (players see each other, not each other's puzzle progress).
- No PvP, no damage between players. Spell events carry a caster ID so a future server-validated target field can be added.
- Remote players are client-authoritative for their own transform (see `docs/architecture.md` → Authority).
- Chat has length/whitespace sanitization only; no moderation.
- Placeholder capsule character with procedural placeholder animations.

## Testing status

Automated (all headless, see docs/development.md): `tests/check_scripts.tscn` (load everything), `tests/run_tests.tscn` (66 gameplay checks), `tests/run_multiplayer_test.tscn` (two clients), `tests/run_reconnect_test.tscn`, `tests/run_offline_fallback_test.tscn`. Last full run: 2026-09-26, all green.

| Area | Check | Status |
|------|-------|--------|
| Movement | walking, running, jumping, gravity | [x] headless test pass |
| Movement | slopes, stairs | [x] headless test pass (ramp lip + 3×0.4 m steps via step-up) |
| Movement | moving platform carries player | [x] headless test pass |
| Camera | rotation, collision, no wall clipping | [x] headless: yaw/pitch, clamps, spring arm shortens against a wall; manual mouse-look: user playtest found and confirmed the crosshair bug; re-verification pending |
| Spell | cast works, invalid targets ignored, receivers react, range | [x] headless test pass |
| Interaction | nearest looked-at object selected, prompt | [x] headless test pass |
| Health | damage, death, checkpoint respawn | [x] headless test pass |
| Collectibles | counter, no double collect | [x] headless test pass |
| Level | full offline playthrough | [x] headless level-wiring test (every mechanism, 11 fragments, end trigger); full manual playthrough by the user still pending |
| Multiplayer | two clients connect, see each other, movement/jump/spell replicate | [x] two headless clients vs local Nakama (`tests/run_multiplayer_test.tscn`): 20 + 14 checks pass |
| Multiplayer | disconnect removes player, reconnect works | [x] two-client test + `run_reconnect_test` (Nakama restarted mid-session → auto reconnect) |
| Chat | messages between clients | [x] two-client test + `run_reconnect_test` (Nakama restarted mid-session → auto reconnect) |
| Offline | playable with backend stopped | [x] `run_offline_fallback_test` with backend stopped: readable error, offline world playable |
| Assets | wall_plain wrapper: 4 × 4 × 0.35 m, bottom-centre pivot, box collision, player blocked | [x] headless (`tests/validate_wall_plain.tscn`, 11 checks) |
| Assets | wall_plain visual: seams, corner, top edge, material | [~] captured with `tools/capture_validation.tscn`; in-game sign-off pending |
