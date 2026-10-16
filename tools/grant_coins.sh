#!/bin/sh
# Give (or, with a negative amount, take) coins on the local dev server; the reason goes in the ledger.
#   tools/grant_coins.sh <display name | user id> <amount> "<reason>"
#   tools/grant_coins.sh --ledger <user id>       the purse and its history, newest first
# Uses the runtime HTTP key from nakama/local.yml (server-to-server call). Display names
# work only for players online; offline players need their user id.
set -e
HOST="${NAKAMA_HOST:-127.0.0.1}"; PORT="${NAKAMA_PORT:-7350}"; KEY="${NAKAMA_HTTP_KEY:-defaulthttpkey}"
if [ "$1" = "--ledger" ] && [ -n "$2" ]; then
  curl -sS "http://$HOST:$PORT/v2/rpc/wallet_ledger?http_key=$KEY&unwrap" -H 'Content-Type: application/json' -d "{\"user_id\":\"$2\",\"limit\":50}"
  echo
  exit 0
fi
TARGET="$1"; AMOUNT="$2"; REASON="$3"
if [ -z "$TARGET" ] || [ -z "$AMOUNT" ] || [ -z "$REASON" ]; then
  echo "usage: $0 <display name | user id> <amount> \"<reason>\"   |   $0 --ledger <user id>" >&2
  exit 2
fi
case "$TARGET" in
  *-*-*-*-*) FIELD="\"user_id\":\"$TARGET\"" ;;
  *) FIELD="\"name\":\"$TARGET\"" ;;
esac
REASON_JSON=$(printf '%s' "$REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')
curl -sS "http://$HOST:$PORT/v2/rpc/admin_grant_coins?http_key=$KEY&unwrap" \
  -H 'Content-Type: application/json' -d "{$FIELD,\"amount\":$AMOUNT,\"reason\":\"$REASON_JSON\"}"
echo
