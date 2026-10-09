#!/bin/bash
# Container-side half of a harness work stream. Runs as the `node` user inside the
# image built from templates/docker/Dockerfile.stream; the host half is scripts/stream.sh.
#
#   stream-entrypoint.sh run                 the container's entrypoint: clone, set up,
#                                            run the stream lead once, write the result,
#                                            then idle so follow-ups can resume the session
#   stream-entrypoint.sh followup "<text>"   (via docker exec) resume the same session
#                                            with a new message, e.g. the owner's answer
#
# Reads ONLY environment (set by stream.sh from the project's harness.env, read literally)
# and /run/stream (the bind-mounted run dir). Files it writes there:
#   status          launched | running | followup | done <rc> | failed <rc> | stopped <rc>
#   interrupted     marker the host writes before SIGINT, so the run ends as `stopped`
#   stream.jsonl    the stream-json log of every run, appended
#   result.json     the last run's result event merged with its structured output
#   prompt.md       the exact prompt sent (preamble + brief)
#   setup.log, firewall.log, entrypoint.log, stderr.log
#   claude.pid      while a `claude` process is running (used to deliver SIGINT)
set -u

RUN=/run/stream
PLUGIN=/opt/claude-harness
mode="${1:-run}"

status() { printf '%s\n' "$*" > "$RUN/status"; }
log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >> "$RUN/entrypoint.log"; }
fail() { log "FAILED: $*"; status "failed ${2:-1}"; }

need() { [ -n "${!1:-}" ] || { fail "env $1 is unset" 2; exit 2; }; }

# Run `claude` once as a child so signals can be delivered to it (SIGINT finishes the
# turn and writes a result; SIGTERM drops the turn, exit 143). Appends to stream.jsonl.
run_claude() {
    local prompt_file="$1"; shift
    local args=(
        -p --output-format stream-json --verbose --include-hook-events
        --permission-mode bypassPermissions --permission-prompts none
        --plugin-dir "$PLUGIN" --strict-mcp-config
        --json-schema "$(cat "$PLUGIN/templates/stream-result.schema.json")"
        --name "hs-${STREAM_ISSUE}"
    )
    [ -n "${STREAM_MODEL:-}" ]          && args+=(--model "$STREAM_MODEL")
    [ -n "${STREAM_EFFORT:-}" ]         && args+=(--effort "$STREAM_EFFORT")
    [ -n "${STREAM_MAX_TURNS:-}" ]      && args+=(--max-turns "$STREAM_MAX_TURNS")
    [ -n "${STREAM_MAX_BUDGET_USD:-}" ] && args+=(--max-budget-usd "$STREAM_MAX_BUDGET_USD")
    [ -n "${STREAM_MCP_CONFIG:-}" ]     && args+=(--mcp-config "$STREAM_MCP_CONFIG")
    args+=("$@")

    cd /workspace || { fail "no /workspace" 2; return 2; }
    claude "${args[@]}" "$(cat "$prompt_file")" >> "$RUN/stream.jsonl" 2>> "$RUN/stderr.log" &
    local child=$!
    echo "$child" > "$RUN/claude.pid"
    trap 'kill -INT "$child" 2>/dev/null' INT
    trap 'kill -TERM "$child" 2>/dev/null; status "stopped 143"' TERM
    local rc
    wait "$child"; rc=$?
    while [ "$rc" -gt 128 ] && kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
    trap - INT TERM
    rm -f "$RUN/claude.pid"
    return "$rc"
}

# result.json = the last result event's bookkeeping fields + its structured output.
# Token figures come from the event (metered), never from the model's own words.
write_result() {
    local rc="$1" line
    line=$(jq -c 'select(.type=="result")' "$RUN/stream.jsonl" 2>/dev/null | tail -1)
    if [ -z "$line" ]; then
        jq -n --arg rc "$rc" --arg issue "${STREAM_ISSUE}" --arg branch "${STREAM_BRANCH:-}" \
            '{issue: ($issue|tonumber), branch: $branch, pr_url: null, state: "failed",
              summary: "no result event in stream.jsonl (see stderr.log)", subtype: "no_result",
              is_error: true, exit_code: ($rc|tonumber), token_ok: false, collected_at: (now|todate)}' \
            > "$RUN/result.json"
        return 1
    fi
    printf '%s\n' "$line" | jq --arg token "${STREAM_TOKEN:-}" --arg rc "$rc" '
        (.structured_output // {}) + {
            session_id, subtype, is_error, num_turns, stop_reason, total_cost_usd, usage,
            modelUsage, duration_ms, errors: (.errors // null),
            permission_denials: (.permission_denials // []),
            exit_code: ($rc|tonumber),
            token_ok: ((.structured_output.token // "") == $token),
            collected_at: (now|todate)
        }' > "$RUN/result.json"
    jq -e '.is_error == false and (.state | IN("done","blocked","needs_owner"))' "$RUN/result.json" >/dev/null 2>&1
}

finish_run() {
    local rc="$1"
    # The host's `stop` leaves an `interrupted` marker before sending SIGINT; the CLI
    # reports an interrupted run as error_during_execution, which is not a failure here.
    if [ -f "$RUN/interrupted" ] || [ "$(cut -d' ' -f1 "$RUN/status" 2>/dev/null)" = "stopped" ]; then
        write_result "$rc" || true
        rm -f "$RUN/interrupted"
        status "stopped $rc"; log "stopped by signal (rc $rc)"
        return
    fi
    if write_result "$rc"; then
        status "done $rc"; log "done (rc $rc, state $(jq -r .state "$RUN/result.json"))"
    else
        status "failed $rc"; log "failed (rc $rc, subtype $(jq -r '.subtype // "?"' "$RUN/result.json" 2>/dev/null))"
    fi
}

case "$mode" in
run)
    status running; log "run start: issue ${STREAM_ISSUE:-?} branch ${STREAM_BRANCH:-?} session ${STREAM_SESSION_ID:-?}"
    for v in STREAM_ISSUE STREAM_BRANCH STREAM_REPO STREAM_SESSION_ID STREAM_TOKEN CLAUDE_CODE_OAUTH_TOKEN GH_TOKEN; do need "$v"; done
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then fail "ANTHROPIC_API_KEY is set; it would override the OAuth token in -p mode" 2; exit 2; fi
    [ -f "$RUN/brief.md" ] || { fail "no brief.md in run dir" 2; exit 2; }

    if [ "${STREAM_FIREWALL:-1}" != "0" ]; then
        if ! sudo "$PLUGIN/scripts/stream-firewall.sh" "${STREAM_EXTRA_EGRESS:-}" >> "$RUN/firewall.log" 2>&1; then
            fail "firewall setup failed (firewall.log)" 3; exit 3
        fi
    else
        log "firewall disabled by STREAM_FIREWALL=0"
    fi

    {
        gh auth setup-git --hostname github.com &&
        git clone "https://github.com/${STREAM_REPO}.git" /workspace &&
        git -C /workspace checkout -b "$STREAM_BRANCH" &&
        git -C /workspace config user.name "${GIT_AUTHOR_NAME:-harness-stream}" &&
        git -C /workspace config user.email "${GIT_AUTHOR_EMAIL:-harness-stream@localhost}"
    } >> "$RUN/setup.log" 2>&1 || { fail "clone/branch failed (setup.log)" 4; exit 4; }

    if [ -n "${STREAM_SETUP_COMMAND:-}" ]; then
        log "setup: $STREAM_SETUP_COMMAND"
        (cd /workspace && bash -c "$STREAM_SETUP_COMMAND") >> "$RUN/setup.log" 2>&1 || { fail "setup command failed (setup.log)" 5; exit 5; }
    fi

    pre=$(cat "$PLUGIN/templates/stream-lead-preamble.md")
    pre=${pre//\{\{ISSUE\}\}/$STREAM_ISSUE}
    pre=${pre//\{\{REPO\}\}/$STREAM_REPO}
    pre=${pre//\{\{BRANCH\}\}/$STREAM_BRANCH}
    pre=${pre//\{\{TOKEN\}\}/$STREAM_TOKEN}
    { printf '%s\n\n' "$pre"; cat "$RUN/brief.md"; } > "$RUN/prompt.md"

    log "claude start"
    run_claude "$RUN/prompt.md" --session-id "$STREAM_SESSION_ID"; rc=$?
    finish_run "$rc"

    # Idle with traps intact so `docker kill -s INT/TERM` still reaches a follow-up's
    # claude process (its pid is in claude.pid) instead of dying at PID 1.
    trap 'p=$(cat "$RUN/claude.pid" 2>/dev/null); [ -n "$p" ] && kill -INT "$p" 2>/dev/null' INT
    trap 'p=$(cat "$RUN/claude.pid" 2>/dev/null); [ -n "$p" ] && kill -TERM "$p" 2>/dev/null; exit 143' TERM
    while :; do sleep 3600 & wait $!; done
    ;;
followup)
    text="${2:-}"
    [ -n "$text" ] || { echo "usage: stream-entrypoint.sh followup \"<message>\"" >&2; exit 2; }
    [ -f "$RUN/claude.pid" ] && { echo "a claude process is still running (claude.pid)" >&2; exit 3; }
    status followup; log "followup start: ${text:0:80}"
    printf '%s\n' "$text" > "$RUN/followup.md"
    run_claude "$RUN/followup.md" --resume "$STREAM_SESSION_ID"; rc=$?
    finish_run "$rc"
    ;;
*)
    echo "usage: stream-entrypoint.sh run | followup \"<message>\"" >&2; exit 2 ;;
esac
