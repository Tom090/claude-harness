#!/bin/bash
# Wave watchdog: mechanical stall detection for background wave sessions.
#
# Usage: wave-watchdog.sh <transcript-or-task-output-path>...
#   The lead launches this in the background right after spawning a
#   background wave, passing each spawn result's output_file. It exits noisily when a
#   watched session's whole transcript tree stops growing for >STALE_SECS, which
#   re-invokes the lead with the alert in the tool result — the mechanical version of
#   someone glancing at the terminal. Streams can die mid-turn leaving a session
#   "running" with zero token usage; no hook fires for that (verified against the hooks
#   docs on a prior project).
#
# Staleness is ALL-STALE over the session's subagent tree, not the session transcript
# alone: a delegating session's own transcript legitimately idles for 20+ minutes while
# its children write (blocked on a synchronous builder, or fanned out to background
# ones), so a single-file mtime check false-alarms on exactly the sessions this script
# exists to protect. For a transcript at <dir>/<id>.jsonl the tree is every *.jsonl
# under <dir>/<id>/ (subagents/agent-*.jsonl and any deeper nesting), re-globbed each
# tick so children spawned mid-wave are picked up. Alert only when the transcript AND
# every child are stale.
#
# A tree can also go quiet because its wave completed cleanly — the completion
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

mtime_of() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Freshest mtime across the transcript and every *.jsonl in its subagent tree.
# Fails (empty output) if nothing exists on disk yet.
newest_mtime() {
    local p="$1" best="" m f
    m=$(mtime_of "$p") && best="$m"
    local tree="${p%.jsonl}"
    if [ -d "$tree" ]; then
        while IFS= read -r f; do
            m=$(mtime_of "$f") || continue
            if [ -z "$best" ] || [ "$m" -gt "$best" ]; then best="$m"; fi
        done < <(find "$tree" -type f -name '*.jsonl' 2>/dev/null)
    fi
    [ -n "$best" ] && printf '%s\n' "$best"
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
        m=$(newest_mtime "$p") || continue
        age=$((now - m))
        if [ "$age" -gt "$STALE_SECS" ]; then
            echo "STALE: $(basename "$p") and its entire subagent tree idle ${age}s (threshold ${STALE_SECS}s)."
            echo "Wave transcript tree stopped growing: session wedged (check ListAgents, resume via SendMessage) or completed with the alert trailing its notification."
            exit 1
        fi
    done
done
echo "watchdog window ended (${MAX_LOOPS}x${INTERVAL}s) with no stall"
