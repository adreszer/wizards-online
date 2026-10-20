# Hosting the server (Coolify)

The hosted backend is Nakama + PostgreSQL deployed by Coolify from `docker-compose.coolify.yml`. The local dev stack (`docker-compose.yml`, `nakama/local.yml`) is separate and keeps its dev secrets and cheats.

## What is in the image

`deploy/nakama/Dockerfile` bakes `nakama/modules` and `nakama/content` into the official Nakama image, plus:

- `deploy/nakama/production.yml`: config without secrets.
- `deploy/nakama/start.sh`: migrates the database, then starts Nakama with the secrets from the environment and refuses to start if one is missing.
- `deploy/nakama/school_rules.local.json`: per-server rule overrides merged over `nakama/content/school_rules.json` by `School.load_rules()` (production: `cheats_enabled` off; admins keep their cheats). Locally the file is gitignored, so a dev server can carry its own.

No port is published on the host. Coolify's proxy terminates TLS on the domain routed to `nakama:7350` (HTTP and WebSocket on one port); clients connect with `https` on 443 and the Nakama addon switches the socket to `wss`.

## Environment

| Variable | Set by | Notes |
|---|---|---|
| `NAKAMA_SERVER_KEY` | you | Ships inside the client (`game/network/server_key.template` in `project.godot`), so it is not a secret, but it must match the client. |
| `ADMIN_USER_IDS` | you | Comma-separated Nakama user ids that are always admins. |
| `SERVICE_PASSWORD_POSTGRES`, `SERVICE_PASSWORD_CONSOLE`, `SERVICE_PASSWORD_64_HTTPKEY`, `SERVICE_PASSWORD_64_SESSION`, `SERVICE_PASSWORD_64_REFRESH` | Coolify | Generated once per resource. Changing the session keys logs everyone out; changing the Postgres password after the first start needs the same change inside the database. |

## First deploy

1. DNS: an `A` record for the game domain (e.g. `play.example.com`) to the Coolify server, and optionally one for the console.
2. Coolify → project → New resource → the GitHub repository, branch `main`, build pack **Docker Compose**, compose file `/docker-compose.coolify.yml`.
3. Domains for the `nakama` service: `https://play.example.com:7350` (the port is the container port Coolify routes to). Optional console: add `,https://console.example.com:7351`; it logs in as `admin` with `SERVICE_PASSWORD_CONSOLE`. Leave `postgres` without a domain.
4. Environment: set `NAKAMA_SERVER_KEY`; check that the `SERVICE_PASSWORD_*` values were generated.
5. Turn **auto deploy off**. Released clients must keep matching the server, so the server is redeployed when a client build is released, not on every push.
6. Deploy. `curl https://play.example.com/healthcheck` answers `{}`.
7. Admin: start a release build, connect once, find the account in the console (Accounts) and put its id in `ADMIN_USER_IDS`; restart the resource.

## Backups

Coolify → the resource → Scheduled tasks, daily, container `postgres`:

```
sh -c 'pg_dump -U postgres nakama | gzip > /var/lib/postgresql/data/backup-$(date +%a).sql.gz'
```

That keeps one dump per weekday inside the database volume; copy them off the server (or to S3) for real safety. Restore: `gunzip -c backup-Mon.sql.gz | psql -U postgres nakama` into an empty database.
