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
- [x] Offline playthrough verified (headless simulation + manual)

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

## Architectural decisions

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
| Camera | rotation, collision, no wall clipping | [x] headless: yaw/pitch, clamps, spring arm shortens against a wall; manual mouse-look verified |
| Spell | cast works, invalid targets ignored, receivers react, range | [x] headless test pass |
| Interaction | nearest looked-at object selected, prompt | [x] headless test pass |
| Health | damage, death, checkpoint respawn | [x] headless test pass |
| Collectibles | counter, no double collect | [x] headless test pass |
| Level | full offline playthrough | [x] headless level-wiring test (every mechanism, 11 fragments, end trigger) + manual play |
| Multiplayer | two clients connect, see each other, movement/jump/spell replicate | [x] two headless clients vs local Nakama (`tests/run_multiplayer_test.tscn`): 20 + 14 checks pass |
| Multiplayer | disconnect removes player, reconnect works | [x] two-client test + `run_reconnect_test` (Nakama restarted mid-session → auto reconnect) |
| Chat | messages between clients | [x] two-client test + `run_reconnect_test` (Nakama restarted mid-session → auto reconnect) |
| Offline | playable with backend stopped | [x] `run_offline_fallback_test` with backend stopped: readable error, offline world playable |
