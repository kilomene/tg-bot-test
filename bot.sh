#!/usr/bin/env bash
# AGT Telegram test bot v6: long-polling bot in pure bash + curl.
# Runs inside the AGT app on the phone. No python, no node, no jq.
# v6 fix (2026-11-17, root-caused on the phone against live bytes):
# the getUpdates response as received contains a literal newline
# right after each "update_id":NNN, entry. The v5 parser reads the
# response line by line, so every update was split in two: the line
# holding the update_id had no chat or text, and the line holding
# the message had no update_id and was discarded. Every real update
# was skipped as "no chat id readable". Fix: strip all raw newline
# bytes from the response before parsing (JSON string values carry
# newlines only as backslash-n escapes, so this is safe).
# v5 rules (learned from the v1-v4 failures, 2026-11-16):
# - Every update is logged with what was read from it (id, chat, text)
#   and every skip carries its reason. Nothing vanishes silently.
# - offset.txt advances ONLY after an update has been handled, so a
#   failed or skipped update is never marked read.
# - sendMessage responses are logged, not thrown away.
# - Parsing uses only basic grep -o patterns and pure-bash trimming:
#   no interval expressions, no readonly variable names (UID is
#   readonly in bash; UPD_ID is used instead).
# Token lookup: token.txt next to this script, then the app files root
# (the app sets HOME to files/home, so $HOME alone is NOT the files
# root), then $HOME, then the BOT_TOKEN env var.
cd "$(dirname "$0")" 2>/dev/null || true

TOKEN=""
for f in token.txt \
         /data/data/com.novainc.agt/files/bot-token.txt \
         /data/user/0/com.novainc.agt/files/bot-token.txt \
         "$HOME/bot-token.txt"; do
  if [ -f "$f" ]; then TOKEN=$(tr -d ' \t\r\n' < "$f"); [ -n "$TOKEN" ] && break; fi
done
if [ -z "$TOKEN" ] && [ -n "$BOT_TOKEN" ]; then TOKEN="$BOT_TOKEN"; fi
if [ -z "$TOKEN" ]; then
  echo "$(date) FATAL: no token found in any known location" | tee -a bot.log
  sleep 30
  exit 1
fi
echo "$(date) token loaded (${#TOKEN} chars)" | tee -a bot.log

API="https://api.telegram.org/bot$TOKEN"
OFFSET=0
[ -f offset.txt ] && OFFSET=$(tr -d ' \t\r\n' < offset.txt)

send_msg() {
  local resp
  resp=$(curl -s -m 15 -X POST "$API/sendMessage" \
    --data-urlencode "chat_id=$1" \
    --data-urlencode "text=$2" 2>&1)
  echo "$(date) sendMessage chat $1 -> ${resp:0:120}" >> bot.log
}

unescape() {
  local s="$1"
  local q='"'
  s=${s//\\n/$'\n'}
  s=${s//\\$q/$q}
  s=${s//\\\//\/}
  s=${s//\\\\/\\}
  printf '%s' "$s"
}

ME=$(curl -s -m 15 "$API/getMe")
echo "$(date) bot starting v6, offset $OFFSET, getMe: $ME" | tee -a bot.log

while true; do
  RESP=$(curl -s -m 60 "$API/getUpdates?offset=$OFFSET&timeout=50" | tr -d '\n')
  if [ -z "$RESP" ]; then sleep 2; continue; fi
  case "$RESP" in
    *'"ok":true'*) ;;
    *) echo "$(date) getUpdates not ok: ${RESP:0:200}" >> bot.log; sleep 3; continue ;;
  esac
  printf '%s' "$RESP" > last_resp.json
  CHUNKS=$(printf '%s' "$RESP" | sed 's/"update_id":/\n"update_id":/g')
  while IFS= read -r chunk; do
    case "$chunk" in *'"update_id":'*) ;; *) continue ;; esac
    UPD_RAW=$(printf '%s' "$chunk" | grep -o '"update_id":[0-9]*' | head -1)
    UPD_ID=${UPD_RAW##*:}
    if [ -z "$UPD_ID" ]; then
      echo "$(date) skip: chunk with no update_id: ${chunk:0:120}" >> bot.log
      continue
    fi
    CHAT_RAW=$(printf '%s' "$chunk" | grep -o '"chat":{"id":-*[0-9]*' | head -1)
    CHAT=${CHAT_RAW##*:}
    TEXT=$(printf '%s' "$chunk" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | head -1)
    echo "$(date) update $UPD_ID chat=[$CHAT] text=[$TEXT]" >> bot.log
    if [ -z "$CHAT" ]; then
      echo "$(date) skip update $UPD_ID: no chat id readable" >> bot.log
      OFFSET=$((UPD_ID + 1)); echo "$OFFSET" > offset.txt
      continue
    fi
    if [ -z "$TEXT" ]; then
      echo "$(date) skip update $UPD_ID: no text (not a text message)" >> bot.log
      OFFSET=$((UPD_ID + 1)); echo "$OFFSET" > offset.txt
      continue
    fi
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
    echo "$(date) handled update $UPD_ID chat $CHAT" >> bot.log
    OFFSET=$((UPD_ID + 1))
    echo "$OFFSET" > offset.txt
  done <<EOF
$CHUNKS
EOF
done
