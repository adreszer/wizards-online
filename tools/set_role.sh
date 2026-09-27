#!/bin/sh
# Change a character's role and/or house on the local dev server.
#   tools/set_role.sh <display name | user id> <student|professor|admin> [house 0-4]
# Uses the runtime HTTP key from nakama/local.yml (server-to-server call).
set -e
TARGET="$1"; ROLE="$2"; HOUSE="$3"
HOST="${NAKAMA_HOST:-127.0.0.1}"; PORT="${NAKAMA_PORT:-7350}"; KEY="${NAKAMA_HTTP_KEY:-defaulthttpkey}"
if [ -z "$TARGET" ] || [ -z "$ROLE" ]; then
  echo "usage: $0 <display name | user id> <student|professor|admin> [house 0-4]" >&2
  exit 2
fi
case "$TARGET" in
  *-*-*-*-*) FIELD="\"user_id\":\"$TARGET\"" ;;
  *) FIELD="\"name\":\"$TARGET\"" ;;
esac
BODY="{$FIELD,\"role\":\"$ROLE\""
[ -n "$HOUSE" ] && BODY="$BODY,\"house\":$HOUSE"
BODY="$BODY}"
# `unwrap` lets the JSON object be sent as the raw payload (instead of a JSON-encoded string).
curl -sS "http://$HOST:$PORT/v2/rpc/admin_set_profile?http_key=$KEY&unwrap" \
  -H 'Content-Type: application/json' -d "$BODY"
echo
