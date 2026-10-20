#!/bin/sh
# Migrates the database, then starts Nakama with the secrets from the environment
# (set in Coolify, see docs/deploy.md). Fails fast if one is missing.
set -eu
: "${POSTGRES_PASSWORD:?}" "${NAKAMA_SERVER_KEY:?}" "${NAKAMA_HTTP_KEY:?}"
: "${NAKAMA_SESSION_KEY:?}" "${NAKAMA_REFRESH_KEY:?}" "${NAKAMA_CONSOLE_PASSWORD:?}"
DB="postgres:${POSTGRES_PASSWORD}@postgres:5432/nakama"
/nakama/nakama migrate up --database.address "$DB"
exec /nakama/nakama --config /nakama/data/production.yml \
  --database.address "$DB" \
  --socket.server_key "$NAKAMA_SERVER_KEY" \
  --runtime.http_key "$NAKAMA_HTTP_KEY" \
  --session.encryption_key "$NAKAMA_SESSION_KEY" \
  --session.refresh_encryption_key "$NAKAMA_REFRESH_KEY" \
  --console.username "${NAKAMA_CONSOLE_USER:-admin}" \
  --console.password "$NAKAMA_CONSOLE_PASSWORD" \
  --runtime.env "ADMIN_USER_IDS=${ADMIN_USER_IDS:-}"
