#!/bin/sh
# Put every world object back to its default and make shared mysteries
# solvable again on the local dev server (playtesting secrets).
#   tools/reset_world.sh
# Per-player progress: tools/set_role.sh does not touch it; call the
# admin_set_profile RPC with {"name": "...", "forget_mysteries": true}.
set -e
HOST="${NAKAMA_HOST:-127.0.0.1}"; PORT="${NAKAMA_PORT:-7350}"; KEY="${NAKAMA_HTTP_KEY:-defaulthttpkey}"
curl -sS "http://$HOST:$PORT/v2/rpc/admin_reset_world?http_key=$KEY&unwrap" \
  -H 'Content-Type: application/json' -d '{}'
echo
