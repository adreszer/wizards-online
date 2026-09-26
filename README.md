# Arcanum Halls — multiplayer magical-school adventure

A small third-person adventure prototype built in Godot 4.7: explore a mysterious magical school, platform, cast a spell, solve environmental puzzles, find secrets, collect fragments — optionally alongside other players via Nakama (presence + chat).

Original placeholder content only; nothing here references existing franchises.

- **Docs:** [docs/development.md](docs/development.md) (run it), [docs/architecture.md](docs/architecture.md), [docs/plan.md](docs/plan.md) (tracker + test status)
- **Quick start:** `tools/run.sh` (or `godot --headless --path . --import` once, then `godot --path .`) → Play OFFLINE
- **Languages:** Polish (primary) and English; pick on the main menu or run with `-- --lang=en` (see docs/development.md → Localization)
- **Online:** `docker compose up -d` → Play ONLINE (second client: `godot --path . -- --name=Rowan --instance=2`)
