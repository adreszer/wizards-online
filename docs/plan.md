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
- [~] Docs: plan.md, architecture.md, development.md, README.md
- [~] Autoloads: GameEvents, GameSession, NetworkManager (documented in architecture.md)
- [ ] Game root scene + test/sandbox scene

### Milestone 2 — Player
- [ ] PlayerInput (intent from InputMap, camera-relative)
- [ ] PlayerMovement (walk/run/jump/gravity/slopes/stairs/air control/accel/decel/landing)
- [ ] Camera rig (yaw/pitch, sensitivity, distance, height, limits, smoothing, SpringArm collision)
- [ ] CharacterVisual placeholder + AnimationTree state machine (idle/walk/run/jump/fall/land/cast)
- [ ] AnimationController decoupled from movement via state signals
- [ ] Local vs remote player split (`LocalPlayer` subtree)

### Milestone 3 — Gameplay components
- [ ] Health component (damage/heal/death signals)
- [ ] Checkpoint + RespawnHandler + KillZone/DamageZone hazards
- [ ] Interactable + InteractionController + prompt
- [ ] Collectible + CollectibleDefinition + counter in GameSession + HUD

### Milestone 4 — Magic
- [ ] SpellDefinition resource (Arcane Pulse data)
- [ ] SpellCaster (center-screen aim, aim assist, range, cooldown, learn spell)
- [ ] SpellProjectile + SpellEffect
- [ ] SpellReceiver component (composition, signal-driven)
- [ ] Cast events routed for network replication

### Milestone 5 — Level mechanics
- [ ] Magic switch
- [ ] Magic door
- [ ] Pushable block + pressure plate
- [ ] Rotating statue + statue puzzle
- [ ] Moving platform (points, speed, loop, activation, carries player)
- [ ] Hazards (kill zone, damage zone)
- [ ] Secret wall mechanism
- [ ] Lever, plaque, spell tome (non-spell interactables)

### Milestone 6 — Vertical slice
- [ ] Greybox level: Entrance → Corridor (secret) → Training → Puzzle → Platforming → Final Puzzle → Reward
- [ ] ~10 Arcane Fragments incl. several in secret room
- [ ] Checkpoints per chamber
- [ ] Offline playthrough verified (headless simulation + manual)

### Milestone 7 — Backend
- [ ] docker-compose.yml (Nakama + PostgreSQL)
- [ ] Nakama Lua module: world match handler + `join_world` RPC
- [ ] Device authentication + display name
- [ ] Graceful failure when backend is down

### Milestone 8 — Multiplayer
- [ ] World session join/leave
- [ ] PlayerSpawner (local + remote)
- [ ] State synchronizer (12 Hz, position/yaw/velocity/movement state)
- [ ] Remote interpolation
- [ ] Animation replication via movement state
- [ ] Spell cast replication
- [ ] Join/leave roster from server

### Milestone 9 — Chat
- [ ] Nakama room channel join
- [ ] Chat UI (open/type/send/receive/close)
- [ ] Input capture while typing
- [ ] Max length + sanitization
- [ ] Join/leave system messages

### Milestone 10 — Debugging & polish
- [ ] F3 debug overlay (FPS, position, velocity, grounded, state, spell, target, online status, ping, player count)
- [ ] Debug ray visualization toggle
- [ ] Pause menu
- [ ] Reconnect behavior
- [ ] Error handling audit
- [ ] Documentation pass
- [ ] Final test pass documented below

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

## Known limitations

- Puzzle/door/collectible state is local to each client in online mode (players see each other, not each other's puzzle progress).
- No PvP, no damage between players. Spell events carry a caster ID so a future server-validated target field can be added.
- Remote players are client-authoritative for their own transform (see `docs/architecture.md` → Authority).
- Chat has length/whitespace sanitization only; no moderation.
- Placeholder capsule character with procedural placeholder animations.

## Testing status

Automated: `tests/run_tests.gd` runs headless (`godot --headless --path . -s tests/run_tests.gd`).

| Area | Check | Status |
|------|-------|--------|
| Movement | walking, running, jumping, gravity | [ ] headless test pass |
| Movement | slopes, stairs | [ ] headless test pass (ramp + step) |
| Movement | moving platform carries player | [ ] headless test pass |
| Camera | rotation, collision, no wall clipping | [ ] manual (SpringArm3D) + headless pitch clamp test |
| Spell | cast works, invalid targets ignored, receivers react, range | [ ] headless test pass |
| Interaction | nearest looked-at object selected, prompt | [ ] headless test pass |
| Health | damage, death, checkpoint respawn | [ ] headless test pass |
| Collectibles | counter, no double collect | [ ] headless test pass |
| Level | full offline playthrough | [ ] scripted headless walkthrough + manual |
| Multiplayer | two clients connect, see each other, movement/jump/spell replicate | [ ] two headless clients against local Nakama (`tests/run_multiplayer_test.gd`) |
| Multiplayer | disconnect removes player, reconnect works | [ ] two-client test |
| Chat | messages between clients | [ ] two-client test |
| Offline | playable with backend stopped | [ ] verified (Docker stopped) |
