#!/usr/bin/env bash
# AGT Telegram test bot: long-polling bot in pure bash + curl.
# Runs inside the AGT app on the phone. No python, no node, no jq.
# Token comes from token.txt next to this script, or $HOME/bot-token.txt.
cd "$(dirname "$0")" || exit 1

TOKEN=""
if [ -f token.txt ]; then TOKEN=$(tr -d ' \t\r\n' < token.txt); fi
if [ -z "$TOKEN" ] && [ -f "$HOME/bot-token.txt" ]; then TOKEN=$(tr -d ' \t\r\n' < "$HOME/bot-token.txt"); fi
if [ -z "$TOKEN" ] && [ -n "$BOT_TOKEN" ]; then TOKEN="$BOT_TOKEN"; fi
if [ -z "$TOKEN" ]; then
  echo "$(date) no token found, waiting" >> bot.log
  sleep 30
  exit 1
fi

API="https://api.telegram.org/bot$TOKEN"
OFFSET=0
[ -f offset.txt ] && OFFSET=$(tr -d ' \t\r\n' < offset.txt)

send_msg() {
  curl -s -m 15 -X POST "$API/sendMessage" \
    --data-urlencode "chat_id=$1" \
    --data-urlencode "text=$2" >/dev/null 2>&1
}

unescape() {
  local s="$1"
  s=${s//\\n/$'\n'}
  s=${s//\\"/\"}
  s=${s//\\\//\/}
  s=${s//\\\\/\\}
  printf '%s' "$s"
}

echo "$(date) bot starting, offset $OFFSET" >> bot.log
ME=$(curl -s -m 15 "$API/getMe")
echo "$(date) getMe: $ME" >> bot.log

while true; do
  RESP=$(curl -s -m 60 "$API/getUpdates?offset=$OFFSET&timeout=50")
  if [ -z "$RESP" ]; then sleep 2; continue; fi
  # Split the result array into one chunk per update.
  CHUNKS=$(printf '%s' "$RESP" | sed 's/"update_id":/\n"update_id":/g')
  while IFS= read -r chunk; do
    case "$chunk" in *'"update_id":'*) ;; *) continue ;; esac
    UID=$(printf '%s' "$chunk" | grep -o '"update_id":[0-9]*' | head -1 | grep -o '[0-9]*')
    [ -z "$UID" ] && continue
    OFFSET=$((UID + 1))
    echo "$OFFSET" > offset.txt
    CHAT=$(printf '%s' "$chunk" | grep -o '"chat":{"id":-\{0,1\}[0-9]*' | head -1 | grep -o -- '-\{0,1\}[0-9]*$')
    TEXT=$(printf '%s' "$chunk" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | head -1)
    [ -z "$CHAT" ] && continue
    [ -z "$TEXT" ] && continue
    TEXT=$(unescape "$TEXT")
    case "$TEXT" in
      /start*)
        send_msg "$CHAT" "Hello. I am alive inside the AGT app on the phone in Nigeria. Deployed from git by a signed job. Send /ping, /status, or any text and I will echo it."
        ;;
      /ping*)
        send_msg "$CHAT" "pong. Phone time: $(date)"
        ;;
      /status*)
        send_msg "$CHAT" "AGT Telegram bot status: running on the phone. Uptime: $(uptime). Free space here: $(df -h . | tail -1)"
        ;;
      *)
        send_msg "$CHAT" "Echo from the phone: $TEXT"
        ;;
    esac
    echo "$(date) handled update $UID chat $CHAT" >> bot.log
  done <<EOF
$CHUNKS
EOF
done
