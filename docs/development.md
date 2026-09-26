# Development guide

## Prerequisites

- Godot **4.7** (standard build; the project uses Jolt physics, built in since 4.4)
- Docker Desktop (or any Docker with Compose v2)
- Git

## Clone and run (offline)

```bash
git clone git@github.com:adreszer/wizards-online.git
cd wizards-online
godot --path .            # or open project.godot in the editor and press F5
```

On macOS there is no `godot` on the PATH by default; the binary is inside the app bundle. Either use the full path or alias it once:

```bash
alias godot=/Applications/Godot.app/Contents/MacOS/Godot   # add to ~/.zshrc
```

All commands below assume `godot` resolves.

Choose **Play OFFLINE**. The full level is playable without any backend.

Controls: WASD move · Shift run · Space jump · mouse look · left click / F cast · E interact · Enter or T chat · Esc pause · F3 debug overlay.

## Backend (Nakama + PostgreSQL)

```bash
docker compose up -d          # first run pulls images and runs migrations
docker compose logs -f nakama # optional: watch the server
docker compose down           # stop (add -v to wipe the database)
```

- Game API: `http://127.0.0.1:7350` (server key `defaultkey`)
- Console: `http://127.0.0.1:7351` (admin / password) — local development only
- Lua modules in `nakama/modules/` are mounted into the container; restart Nakama after editing them (`docker compose restart nakama`).

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

# gameplay tests: movement, camera, health/checkpoints, collectibles, spells,
# interaction, moving platform, level wiring
godot --headless --path . tests/run_tests.tscn

# two headless clients against a running Nakama (docker compose up -d first)
godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=1 --name=ClientA &
godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=2 --name=ClientB --role=b
```

Exit code is non-zero on failure; the summary is printed at the end.

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
