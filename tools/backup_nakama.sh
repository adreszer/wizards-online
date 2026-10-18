#!/usr/bin/env bash
# Backs up the Nakama database (accounts, wallets, storage: profiles, records, house points,
# clubs, gardens…) with pg_dump from the compose project's postgres container.
# Usage: tools/backup_nakama.sh [database] [out dir]   (defaults: nakama, backups/)
# Restore: gunzip -c FILE | docker exec -i wizards-postgres psql -U postgres -d nakama
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${1:-nakama}"
OUT="${2:-backups}"
CONTAINER="${POSTGRES_CONTAINER:-wizards-postgres}"
mkdir -p "$OUT"
FILE="$OUT/${DB}-$(date -u +%Y%m%d-%H%M%S).sql.gz"
docker exec "$CONTAINER" pg_dump -U postgres --no-owner "$DB" | gzip > "$FILE"
echo "backup written: $FILE ($(du -h "$FILE" | cut -f1))"
