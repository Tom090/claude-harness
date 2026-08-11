#!/usr/bin/env bash
# Telegram bridge to the project owner. No secrets in this file: TELEGRAM_BOT_TOKEN +
# OWNER_CHAT_ID live in ~/.config/<project>-harness/telegram.env (0600), never in the repo.
# <project> is PROJECT_NAME from .claude/harness.env (see skills/ask-owner/SKILL.md for
# setup); falls back to "claude" if harness.env is absent or PROJECT_NAME is unset.
#
# Usage:
#   telegram-owner.sh send "message"              one-way notify, returns immediately
#   telegram-owner.sh ask "question" [max_min]    send, then wait for the owner's reply
#                                                 (default 240 min; run as a background
#                                                 task — it blocks until reply/timeout)
#   telegram-owner.sh poll                        print any unread owner messages
#
# Only one getUpdates long-poll may run per bot at a time (Telegram returns 409) —
# don't run two `ask`/`poll` invocations concurrently.
set -euo pipefail

PROJECT_NAME="claude"
toplevel="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# shellcheck disable=SC1091
[ -f "$toplevel/.claude/harness.env" ] && source "$toplevel/.claude/harness.env"

CONF="$HOME/.config/${PROJECT_NAME}-harness/telegram.env"
STATE="$HOME/.config/${PROJECT_NAME}-harness/telegram.offset"
[ -f "$CONF" ] || { echo "missing $CONF (see skills/ask-owner/SKILL.md)" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONF"
: "${TELEGRAM_BOT_TOKEN:?}" "${OWNER_CHAT_ID:?}"
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

send() {
    curl -s "$API/sendMessage" -d chat_id="$OWNER_CHAT_ID" \
        --data-urlencode text="$1" | jq -e .ok >/dev/null
}

offset() { cat "$STATE" 2>/dev/null || echo 0; }

# One long-poll round: prints new owner-chat messages, advances the offset.
fetch() {
    local resp last
    resp=$(curl -s --max-time 60 "$API/getUpdates?timeout=50&offset=$(offset)")
    echo "$resp" | jq -r --arg c "$OWNER_CHAT_ID" \
        '.result[] | select(.message.chat.id == ($c|tonumber)) | .message.text // empty'
    last=$(echo "$resp" | jq -r '[.result[].update_id] | max // empty')
    if [ -n "$last" ]; then echo $((last + 1)) > "$STATE"; fi
}

case "${1:?usage: send|ask|poll}" in
    send) send "${2:?message}" ;;
    poll) fetch ;;
    ask)
        fetch >/dev/null   # drain stale messages so they can't masquerade as the reply
        send "${2:?question}"
        deadline=$(( $(date +%s) + ${3:-240} * 60 ))
        while [ "$(date +%s)" -lt "$deadline" ]; do
            reply=$(fetch)
            if [ -n "$reply" ]; then echo "$reply"; exit 0; fi
        done
        echo "NO_REPLY: owner did not answer within ${3:-240} minutes" >&2
        exit 3
        ;;
    *) echo "unknown subcommand: $1 (send|ask|poll)" >&2; exit 2 ;;
esac
