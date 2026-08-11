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
# Denies:
#   - `git push --force` / `-f` (allows the safer `--force-with-lease`)
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

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$PROJECT_DIR/.claude/harness.env" ] || exit 0
# shellcheck disable=SC1091
source "$PROJECT_DIR/.claude/harness.env"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

# --- git push --force / -f (allow --force-with-lease) ---
if printf '%s' "$cmd" | grep -Eq '\bgit\b.*\bpush\b'; then
  if ! printf '%s' "$cmd" | grep -Eq -- '--force-with-lease\b'; then
    if printf '%s' "$cmd" | grep -Eq -- '(--force\b|(^|[[:space:]])-f\b)'; then
      deny "Blocked by harness policy: git push --force/-f is disallowed. Use --force-with-lease if a force-push is truly required, never on the default branch, and confirm with the owner first."
    fi
  fi
fi

# --- git reset --hard ---
if printf '%s' "$cmd" | grep -Eq '\bgit\b.*\breset\b.*--hard\b'; then
  deny "Blocked by harness policy: git reset --hard discards uncommitted work. Stash (git stash -u) or commit first."
fi

# --- rm -rf (any flag order/spelling) ---
has_recursive=0
has_force=0
printf '%s' "$cmd" | grep -Eq -- '(-[a-zA-Z]*[rR][a-zA-Z]*\b|--recursive\b)' && has_recursive=1
printf '%s' "$cmd" | grep -Eq -- '(-[a-zA-Z]*f[a-zA-Z]*\b|--force\b)' && has_force=1

if printf '%s' "$cmd" | grep -Eq '\brm\b' && [ "$has_recursive" -eq 1 ] && [ "$has_force" -eq 1 ]; then
  # Pure-bash tokenizing (portable — BSD sed/grep on macOS don't reliably support \b in
  # substitutions): find the token exactly equal to `rm`, then treat everything after it
  # as candidate paths. Anything past a shell separator (&&, ;, |) only ever makes the
  # check MORE conservative (falls to unsafe=1 below), matching the default-deny intent.
  unsafe=0
  found_path=0
  seen_rm=0
  for tok in $cmd; do
    if [ "$seen_rm" -eq 0 ]; then
      case "$tok" in
        rm|*/rm) seen_rm=1 ;;
      esac
      continue
    fi
    case "$tok" in
      -*) continue ;;   # flag, ignore
    esac
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

  if [ "$found_path" -eq 0 ] || [ "$unsafe" -eq 1 ]; then
    deny "Blocked by harness policy: rm -rf outside the allowed build-cache/scratchpad scope (or targeting a PROTECTED_PATHS entry) is disallowed. Allowed: build/, node_modules/, dist/, target/, .gradle/, .kotlin/, .venv/, __pycache__/, /tmp or /private/tmp paths, and any *scratchpad* path. Confirm with the owner if you need to remove something else."
  fi
fi

exit 0
