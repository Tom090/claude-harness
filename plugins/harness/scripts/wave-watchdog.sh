#!/bin/bash
# Wave watchdog: mechanical stall detection for background wave sessions.
#
# Usage: wave-watchdog.sh <transcript-or-task-output-path>...
#   The lead (or wave-lead) launches this in the background right after spawning a
#   background wave, passing each spawn result's output_file. It exits noisily when any
#   watched transcript stops growing for >STALE_SECS, which re-invokes the lead with the
#   alert in the tool result — the mechanical version of someone glancing at the
#   terminal. Streams can die mid-turn leaving a session "running" with zero token
#   usage; no hook fires for that (verified against the hooks docs on a prior project).
#
# A transcript can also go quiet because its wave completed cleanly — the completion
# notification arrives on its own channel; treat this alert as "check ListAgents,
# resume via SendMessage if the session is genuinely wedged".
set -u
STALE_SECS="${STALE_SECS:-720}"
INTERVAL="${INTERVAL:-180}"
MAX_LOOPS="${MAX_LOOPS:-80}" # ~4h at default interval

[ $# -ge 1 ] || { echo "usage: wave-watchdog.sh <transcript-or-task-output-path>..." >&2; exit 2; }

# Task output files are symlinks to the subagent transcript JSONL — resolve them.
# python3 is not guaranteed everywhere, so fall back to readlink -f and then to the path
# as given (a plain, non-symlink file needs no resolution at all).
resolve() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" && return 0
    fi
    readlink -f "$1" 2>/dev/null && return 0
    printf '%s\n' "$1"
}

paths=()
for a in "$@"; do
    r="$(resolve "$a")"
    [ -n "$r" ] || r="$a"
    [ -e "$r" ] || echo "warning: $r does not exist (yet) — watching anyway" >&2
    paths+=("$r")
done

for _ in $(seq 1 "$MAX_LOOPS"); do
    sleep "$INTERVAL"
    now=$(date +%s)
    for p in "${paths[@]}"; do
        m=$(stat -f %m "$p" 2>/dev/null) || m=$(stat -c %Y "$p" 2>/dev/null) || continue
        age=$((now - m))
        if [ "$age" -gt "$STALE_SECS" ]; then
            echo "STALE: $(basename "$p") idle ${age}s (threshold ${STALE_SECS}s)."
            echo "Wave transcript stopped growing: session wedged (check ListAgents, resume via SendMessage) or completed with the alert trailing its notification."
            exit 1
        fi
    done
done
echo "watchdog window ended (${MAX_LOOPS}x${INTERVAL}s) with no stall"
