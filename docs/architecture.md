# Architecture

Godot 4.7 · GDScript (static typing) · Nakama 3 (Lua runtime module) · PostgreSQL · Docker Compose.

## Scene flow

```
core/game.tscn (Game)
 ├── ui/menus/main_menu.tscn      name / host / OFFLINE | ONLINE
 └── core/world.tscn (World)      created after the menu
      ├── Level      levels/mvp/mvp_level.tscn
      ├── Players    local + remote Player instances
      ├── PlayerSpawner
      ├── HUD, ChatPanel, PauseMenu, DebugOverlay (CanvasLayers)
```

`Game` swaps the menu and the world. `World` spawns the local player at the level's `StartPoint` and reacts to `GameEvents.level_completed`.

## Autoloads (and why)

| Autoload | Why it is global |
|----------|------------------|
| `Nakama` (addon) | Required by the official client to host HTTP/WebSocket adapters. |
| `GameEvents` | Signal bus for broadcast-style events (collectible picked up, checkpoint, notification, UI input capture). Keeps HUD, level objects and the spawner decoupled. |
| `GameSession` | Session-scoped state that survives scene swaps: play mode, display name, host/port, collectible counters, "UI owns the keyboard" flag. No gameplay logic. |
| `NetworkManager` | The single networking boundary. Composed of `NakamaAuthentication`, `WorldSession`, `StateSynchronizer`, `ChatManager`. Gameplay never touches Nakama types. |

Nothing else is global.

## Player (composition)

```
Player (CharacterBody3D, player.gd — wiring only)
├── Movement            PlayerMovement      walk/run/jump/gravity/slopes/step-up/coyote/buffer
├── CharacterVisual     placeholder meshes + AnimationPlayer + AnimationTree
│   └── AnimationController   state names → AnimationTree parameters
├── SpellCaster         aim (centre screen + assist), cooldown, projectile spawn
├── Health
├── RespawnHandler      checkpoint transform, death/fall respawn
├── NetworkSynchronizer local: sample+send 12 Hz · remote: buffer+interpolate
├── Nameplate           Label3D (hidden for local)
└── LocalPlayer (Node3D) — freed for remote players
    ├── PlayerInput            InputMap → intent (cleared while UI captures input)
    ├── CameraRig              yaw → Pitch → SpringArm3D → Camera3D (top-level)
    └── InteractionController  Area3D on the "interactable" layer
```

- `is_local` is set by the spawner **before** the node enters the tree. `_setup_local` / `_setup_remote` do the wiring.
- Movement is camera-relative through a `frame_yaw_provider` callable, so tests and future gamepad/cinematic cameras plug in without touching movement.
- Animation: an `AnimationNodeBlendTree` with a 6-way `AnimationNodeTransition` (idle/walk/run/jump/fall/land, cross-faded) feeding an `AnimationNodeOneShot` for casting filtered to the arm. Gameplay only calls `set_movement_state_name()` and `play_cast()`, so the placeholder animations can be replaced by editing `character_visual.tscn` alone.
- Remote players share the same scene: their `LocalPlayer` subtree is freed, physics is disabled, and `NetworkSynchronizer` drives the transform and animation state.

## Components discover each other by meta, not NodePaths

`SpellReceiver`, `Interactable`, `Health` and `RespawnHandler` register on their parent/body with `set_meta("spell_receiver", self)` etc. A projectile that hits a collider does `SpellReceiver.find_on(collider)`; the interaction controller does `Interactable.find_on(body)`. Any body gains behaviour by adding a child component, and there are no `$../..` paths in gameplay code.

## Spells

```
SpellDefinition (Resource)  id, name, description, icon, effect_type, range, cooldown,
                            projectile_speed, projectile_scene, strength, aim assist, sounds, colour
SpellCaster (Node3D)        try_cast() / cast_remote() / learn_spell()
SpellProjectile (Node3D)    ray-swept movement, burst, delivers SpellEffect
SpellReceiver (Node)        filters effect types, emits spell_received
SpellEffect (RefCounted)    definition, effect_type, caster, caster_id, hit position, direction, strength
```

Aiming: the camera ray from the screen centre is intersected with the world; a cone (`aim_assist_angle_degrees`) around it prefers the nearest `SpellReceiver` in range with line of sight from the wand. The projectile is fired from the wand tip toward the resolved point. Adding a second spell = a new `.tres` (+ optionally a new projectile scene); `SpellCaster` is untouched. Objects react by connecting to their receiver's signal (`MagicSwitch`, `PushableBlock`, `RotatingStatue`, `SecretWall`), never by checking the spell's name.

## Level mechanics

All in `objects/`: `MagicSwitch`, `MagicDoor` (AnimatableBody3D panel), `PushableBlock` (RigidBody3D), `PressurePlate` (Area3D), `RotatingStatue` + `StatuePuzzle`, `MovingPlatform` (AnimatableBody3D, `sync_to_physics`, waypoints, loop modes, activation), `SecretWall`, `Lever`, `Plaque`, `SpellTome`. Objects expose signals/methods; `levels/mvp/mvp_level.gd` holds only the level-specific wiring (e.g. "both switches open the door"). Greybox geometry is `GreyboxBlock` (`@tool`, size-driven mesh + collision).

## Networking

```
NetworkManager (autoload)
├── NakamaAuthentication   device auth (+ --instance suffix), display name in session vars
├── WorldSession           socket, "join_world" RPC → join authoritative match, decodes op codes
├── StateSynchronizer      roster (sid → name), ping, send/receive state & casts
└── ChatManager            room channel "world", sanitization, sender-name lookup via roster
```

Server (`nakama/modules/`): `world.lua` registers the `join_world` RPC (finds the match by label, creates it if missing) and a `ChannelMessageSend` before-hook that rejects empty/oversized chat. `world_match.lua` is the authoritative match handler: it owns the roster (names from join metadata, sanitized), sends the roster to joiners, broadcasts join/leave, relays state and spell casts to everyone else, and echoes pings.

Op codes are defined once in `multiplayer/network_protocol.gd` and mirrored in the Lua file.

### Authority (MVP)

| State | Authority | Notes |
|-------|-----------|-------|
| Player identity, display name, roster, join/leave | **Server** | Clients never trust another client's claims about who is present. |
| Player transform, velocity, movement state | Client-authoritative (relayed by the server) | The match handler is the place to add rate limits / sanity checks later. |
| Spell cast events | Client-authoritative, cosmetic on other clients | Carries `caster_id`; a future `target` field + server validation enables duels. |
| Puzzle / door / collectible state | **Local only** | Documented MVP limitation; receivers are signal-driven so a server trigger can call the same handlers. |
| Chat | Server-validated (length), client-rendered | Names resolved through the server roster. |

### Replication details

- Local players sample at `game/network/state_send_rate` (12 Hz) and send `{p, y, v, s, g}` as JSON (position, yaw, velocity, state name, grounded).
- Remote players keep a snapshot buffer and render 120 ms behind the newest snapshot, interpolating between surrounding snapshots and extrapolating briefly on velocity if starved. Large jumps (respawn) snap.
- Animation on remote players is driven by the replicated movement state name; casts trigger the same `play_cast()` and a cosmetic projectile.
- Two sessions of the same account are distinct players because everything is keyed by Nakama **session id**, not user id.

## Input

All gameplay reads InputMap actions through `PlayerInput`; no physical keys anywhere. Joypad bindings already exist for every action. While the chat field has focus, `GameSession.ui_input_captured` is true and `PlayerInput` clears its intent.

## Debug

`ui/debug/debug_overlay.tscn` (F3 cycles: overlay → overlay + rays → off). Disabled when `OS.is_debug_build()` is false or `game/debug/enable_debug_overlay` is off.

## Directory map

```
addons/com.heroiclabs.nakama   vendored official client (only third-party dependency)
assets/audio                   generated placeholder tones
assets/models                  source models (GLB) as exported by the art pipeline; never edited here
characters/player, components  player scene + components
core/                          game root, world, autoloads
gameplay/{spells,interaction,collectibles,health,checkpoints}
levels/mvp                     greybox level + wiring script
levels/dev                     development-only scenes (asset validation)
multiplayer/{authentication,synchronization,chat} + network_manager, world_session, player_spawner
nakama/                        local.yml + Lua modules (mounted into the container)
objects/{greybox,puzzles,platforms,interactables}
objects/environment            wrapper scenes for imported environment modules (transform, collision, layers)
tools/                         headless dev utilities (model inspection, screenshot capture)
resources/{spells,collectibles} data resources
tests/                         headless test runners
ui/{menus,hud,chat,debug}
```
