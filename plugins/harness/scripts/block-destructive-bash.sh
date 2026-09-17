#!/bin/bash
# PreToolUse hook on Bash: deterministic block of destructive commands.
#
# CRITICAL: this hook fires on every Bash call in EVERY project where the harness plugin
# is enabled, so it is a no-op (exit 0, no output) unless the project has run
# /harness:harness-init and written .claude/harness.env. This keeps the plugin inert in
# an unbound project rather than surprising a fresh repo with policy it never opted into.
#
# .claude/harness.env keys read:
#   PROTECTED_PATHS   optional. Space-separated extra path prefixes that must NEVER be
#                     `rm -rf` targets, even if a path would otherwise look like build
#                     cache — e.g. secrets or credential paths the project cares about
#                     beyond the generic .gitignore-style denials:
#                     PROTECTED_PATHS="secrets .env keystore.jks"
#
# harness.env is READ, never `source`d, by this hook: it runs on every Bash call in every
# enabled project, and sourcing a repo-controlled file that often would execute whatever
# a cloned repo put in it. Only literal `KEY="value"` lines are understood here (that is
# the documented format — see templates/harness.env.example).
#
# Denies:
#   - `git push --force` / `-f` / `+refspec` (allows the safer `--force-with-lease`)
#   - `git reset --hard`
#   - `rm -rf` (and flag-order/spelling variants) targeting anything OUTSIDE the
#     build-cache/scratch allowlist above. Bare/ambiguous targets (`rm -rf .`, `~`, `/`,
#     `$HOME`, or no path at all) are denied.
#
# Default-deny: an rm -rf whose paths can't all be confirmed safe is denied. This is a
# heuristic string-level guard (best-effort tokenizing of the command), not a full shell
# parser — it errs toward blocking on ambiguity, which only costs a permission prompt,
# never a false allow.
#
# Input: hook JSON on stdin: {tool_name, tool_input:{command}, ...}.
# Output: JSON on stdout with hookSpecificOutput.permissionDecision=deny to block;
#         exit 0 with no output to defer to the normal permission flow.

# Always drain stdin first: exiting without reading it leaves the caller writing into a
# closed pipe.
input=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
env_file="$PROJECT_DIR/.claude/harness.env"
[ -f "$env_file" ] || exit 0

# --- Read PROTECTED_PATHS without executing the file (see header) ---
# Deliberately NOT inside a $( ) command substitution: bash 3.2 (still /bin/bash on
# macOS) mis-parses `case` patterns nested in command substitution.
PROTECTED_PATHS=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"                        # tolerate CRLF
  while [ "${line# }" != "$line" ] || [ "${line#$'\t'}" != "$line" ]; do
    line="${line# }"
    line="${line#$'\t'}"
  done
  case "$line" in
    PROTECTED_PATHS=*) ;;
    *) continue ;;
  esac
  val="${line#PROTECTED_PATHS=}"
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  PROTECTED_PATHS="$val"                      # last assignment wins, as with `source`
done < "$env_file"

# --- JSON in/out: jq preferred, python3 fallback. If neither exists this guard cannot
# read the command at all — say so ONCE per day rather than silently going inert. ---
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print((d.get("tool_input") or {}).get("command") or "")' 2>/dev/null)
else
  warn_stamp="${TMPDIR:-/tmp}/claude-harness-nojson-$(date +%Y%m%d)"
  if [ ! -f "$warn_stamp" ]; then
    : > "$warn_stamp" 2>/dev/null
    echo "harness: neither jq nor python3 found — the destructive-command guard is INACTIVE. Install jq." >&2
    exit 1   # non-blocking error: surfaced to the user, does not block the tool call
  fi
  exit 0
fi
[ -z "$cmd" ] && exit 0

deny() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    printf '%s' "$1" | python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.stdin.read()}}))'
  fi
  exit 0
}

# --- git push force variants and git reset --hard: checked PER SEGMENT below ---
# Only tokens after the `push` (or `reset`) subcommand of a `git` invocation in the SAME
# shell segment are inspected. Checking the whole command string used to produce three
# recorded false positives, all fail-closed: a `-f` belonging to a later `git worktree
# remove -f` or `rm -f` in a chained command; a `+` in prose or arithmetic ("n + 1")
# after the push; a `HEAD:branch` refspec beside one of those. Per-segment, none apply.
push_force_msg="Blocked by harness policy: force-pushing (--force/-f, --force-with-lease combined with --force, or a +refspec) is disallowed. Use --force-with-lease on its own if a force-push is truly required, never on the default branch, and confirm with the owner first."
reset_hard_msg="Blocked by harness policy: git reset --hard discards uncommitted work. Stash (git stash -u) or commit first."

# check_git_segment <token>...: deny() on a force push or hard reset in one segment.
# Global git options before the subcommand are skipped; -C and -c consume an argument.
check_git_segment() {
  local seen_git=0 sub="" expect_arg=0 tok
  for tok in "$@"; do
    if [ "$seen_git" -eq 0 ]; then
      case "$tok" in git|*/git|\\git) seen_git=1 ;; esac
      continue
    fi
    if [ -z "$sub" ]; then
      if [ "$expect_arg" -eq 1 ]; then expect_arg=0; continue; fi
      case "$tok" in
        -C|-c) expect_arg=1; continue ;;
        -*) continue ;;
        *) sub="$tok"; continue ;;
      esac
    fi
    case "$sub" in
      push)
        case "$tok" in
          --force-with-lease|--force-with-lease=*) ;;      # the safe form, on its own
          --force) deny "$push_force_msg" ;;
          --*) ;;                                          # any other long option
          -*f*) deny "$push_force_msg" ;;                  # -f, or -f inside -uf etc.
          +?*) deny "$push_force_msg" ;;                   # +refspec; a bare + is prose
        esac ;;
      reset)
        case "$tok" in --hard) deny "$reset_hard_msg" ;; esac ;;
    esac
  done
}

# --- rm -rf (any flag order/spelling) ---
# Each shell SEGMENT is analyzed independently, and only a segment whose own command word
# is `rm` is ever examined. Doing this per-segment rather than over the whole string is
# what keeps three classes of false positive out (all seen in the wild; all fail-closed,
# so they cost a spurious denial rather than a missed one):
#   * `rm -f /tmp/some-random-name` — a stray "-r" inside an UNRELATED filename used to
#     satisfy the recursive-flag test, because flags were matched across the whole string.
#   * `rm -rf build/x; echo done` — tokens belonging to a LATER command used to be read as
#     extra rm targets, forcing default-deny on an otherwise-allowed path.
#   * `grep -n "rm -rf" file` — merely MENTIONING rm in a quoted argument used to trip the
#     guard, since `\brm\b` matched but no bare `rm` token was found.
# Command substitutions are split out as their own segments too, so `echo $(rm -rf /)` is
# still caught. This remains a heuristic string-level guard, not a shell parser: it cannot
# see through `eval`, an alias, or a path assembled at runtime, and it still errs toward
# blocking whenever a target can't be resolved to a literal safe path.
set -f          # no pathname expansion while tokenizing untrusted input

segments="$cmd"
segments="${segments//&&/$'\n'}"     # before the bare & rule
segments="${segments//||/$'\n'}"     # before the bare | rule
segments="${segments//\$(/$'\n'}"    # before the bare ( rule
segments="${segments//;/$'\n'}"
segments="${segments//|/$'\n'}"
segments="${segments//&/$'\n'}"
segments="${segments//\`/$'\n'}"
segments="${segments//(/$'\n'}"
segments="${segments//)/$'\n'}"

rm_deny_msg="Blocked by harness policy: rm -rf outside the allowed build-cache/scratchpad scope (or targeting a PROTECTED_PATHS entry) is disallowed. Allowed: build/, node_modules/, dist/, target/, .gradle/, .kotlin/, .venv/, __pycache__/, /tmp or /private/tmp paths, and any *scratchpad* path. Confirm with the owner if you need to remove something else."

# Fed by a pipe, NOT a heredoc: a command containing a line that is exactly the heredoc
# delimiter (any `cat <<EOF ... EOF` script) would end the heredoc early and leave
# everything after it unscanned. The pipe makes this loop a subshell, so deny()'s exit
# ends the subshell — the deny JSON is still written to the script's stdout exactly once,
# and the outer script then falls through to its own `exit 0` emitting nothing further.
printf '%s\n' "$segments" | while IFS= read -r segment; do
  [ -n "$segment" ] || continue

  # shellcheck disable=SC2086  # word-splitting is the tokenizer here (set -f is on)
  check_git_segment $segment

  seen_rm=0; has_recursive=0; has_force=0; unsafe=0; found_path=0; endopts=0

  for tok in $segment; do
    # --- locate the rm invocation: the first BARE `rm` token in this segment ---
    # Scan the whole segment instead of giving up at the first unrecognized word. rm is
    # routinely reached through another command word in the same segment —
    # `echo / | xargs rm -rf`, `find . -exec rm -rf {} \;`, `sudo rm -rf x`,
    # `VAR=1 rm -rf x` — and bailing out early left every one of those unscanned.
    # Only an UNQUOTED token that is exactly `rm` (or a path ending in /rm, or \rm)
    # starts an invocation, so merely mentioning rm in an argument still doesn't trip
    # the guard: in `grep -n "rm -rf" file` the token is `"rm`, not `rm`. `echo rm -rf /`
    # does trip it — prose shaped exactly like an invocation is denied, which costs a
    # permission prompt, never a false allow.
    if [ "$seen_rm" -eq 0 ]; then
      case "$tok" in
        rm|*/rm|\\rm) seen_rm=1 ;;
        *) ;;                                  # not the invocation — keep scanning
      esac
      continue
    fi

    # --- flags belonging to THIS rm invocation ---
    if [ "$endopts" -eq 0 ]; then
      case "$tok" in
        --) endopts=1; continue ;;
        --recursive) has_recursive=1; continue ;;
        --force) has_force=1; continue ;;
        --*) continue ;;
        -*)
          case "$tok" in *[rR]*) has_recursive=1 ;; esac
          case "$tok" in *f*) has_force=1 ;; esac
          continue ;;
      esac
    fi

    # --- everything else is a target path ---
    found_path=1
    protected=0
    if [ -n "${PROTECTED_PATHS:-}" ]; then
      for p in $PROTECTED_PATHS; do
        case "$tok" in
          "$p"|"$p"/*|*"/$p"|*"/$p"/*) protected=1; break ;;
        esac
      done
    fi
    if [ "$protected" -eq 1 ]; then
      unsafe=1
      continue
    fi
    case "$tok" in
      build|build/*|*/build|*/build/*|.gradle|.gradle/*|*/.gradle|*/.gradle/*| \
      .kotlin|.kotlin/*|*/.kotlin|*/.kotlin/*|node_modules|node_modules/*|*/node_modules|*/node_modules/*| \
      dist|dist/*|*/dist|*/dist/*|target|target/*|*/target|*/target/*| \
      .venv|.venv/*|*/.venv|*/.venv/*|__pycache__|__pycache__/*|*/__pycache__/*| \
      /tmp/*|/private/tmp/*|*scratchpad*)
        ;;  # allowed: build cache / scratch scope
      *)
        unsafe=1
        ;;
    esac
  done

  # Only -r AND -f together are guarded (`rm -r dir` alone defers to the permission flow,
  # as it always has). A bare/ambiguous target, or no target at all, is denied.
  if [ "$seen_rm" -eq 1 ] && [ "$has_recursive" -eq 1 ] && [ "$has_force" -eq 1 ]; then
    if [ "$found_path" -eq 0 ] || [ "$unsafe" -eq 1 ]; then
      deny "$rm_deny_msg"
    fi
  fi
done

set +f

exit 0
