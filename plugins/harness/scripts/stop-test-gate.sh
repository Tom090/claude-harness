#!/bin/bash
# Stop hook: deterministic quality gate.
#
# Runs the project's test/lint command and blocks the agent from finishing its turn
# (exit 2) if it fails. Scoped so docs-only / non-code sessions never pay the cost: it
# skips entirely unless the session touched files matching BUILD_RELEVANT_PATTERNS.
#
# CRITICAL: this hook fires in EVERY project where the harness plugin is enabled, so it
# is a no-op (exit 0, silent) unless the project has run /harness:harness-init and
# written .claude/harness.env with at least TEST_COMMAND set. This is what keeps the
# plugin safe to enable in a project before it's been bound.
#
# TRUST MODEL (owner ruling): TEST_COMMAND comes from a file inside the repo, and this
# hook runs it. A repo-shipped .claude/harness.env must therefore never be enough on its
# own — cloning a hostile repo would otherwise mean code execution at the end of the
# first turn. Two independent conditions are required before anything is executed:
#   1. .claude/harness.env exists in the project, and
#   2. the project's absolute physical path is listed, one path per line, in the
#      USER-level trust file ~/.config/claude-harness/trusted-projects (written by
#      /harness:harness-init, outside any repo, so no repo can add itself).
# harness.env is READ literally (KEY="value"), never sourced — reading a string is safe
# anywhere; only the trusted-path check gates actually running it.
#
# .claude/harness.env keys read:
#   TEST_COMMAND             required. e.g. "./gradlew testDebugUnitTest lintDebug" or
#                             "npm test && npm run lint" or "cargo test && cargo clippy".
#                             The full suite; /harness:validate runs it at PR time.
#   SCOPED_TEST_COMMAND      optional. Run per turn instead of TEST_COMMAND. `{files}` in
#                             it is replaced by the session's changed, still-existing
#                             files (those matching BUILD_RELEVANT_PATTERNS when set),
#                             each shell-quoted; without `{files}` it runs as written.
#                             Falls back to TEST_COMMAND when the file list is empty.
#                             This is what keeps N agents on one machine from running
#                             N full suites at once.
#   BUILD_RELEVANT_PATTERNS  optional. Space-separated path fragments, matched as fixed
#                             strings (substring, not glob) against the session's changed
#                             file paths — "this session touched code worth gating on",
#                             e.g. "app/ build.gradle.kts gradlew". If unset, the gate
#                             runs whenever the session changed ANY file at all
#                             (conservative default — no false skips); a clean tree
#                             skips, and a directory with no git signal always runs.
#
# Loop guard: caps consecutive blocks per session at 3 (state keyed on transcript_path,
# since Claude Code has no built-in Stop-hook loop-prevention field). After 3 blocked
# attempts it lets the turn end anyway with a loud non-blocking warning, rather than
# hanging the session forever on an unfixable failure.
#
# Input: hook JSON on stdin (transcript_path, cwd, hook_event_name, ...).
# Output: exit 0 = allow stop. exit 2 + stderr = block, stderr fed back to the agent.
#         exit 1 = non-blocking warning (shown, doesn't block) — used only for the
#         loop-guard escape hatch.

input=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

[ -f .claude/harness.env ] || exit 0

# --- Read config literally; never `source` a repo-controlled file (see TRUST MODEL) ---
harness_env_value() {
  local key="$1" line val=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # tolerate CRLF
    while [ "${line# }" != "$line" ] || [ "${line#$'\t'}" != "$line" ]; do
      line="${line# }"
      line="${line#$'\t'}"
    done
    case "$line" in
      "$key="*) ;;
      *) continue ;;
    esac
    val="${line#$key=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
  done < .claude/harness.env
  printf '%s' "$val"                           # last assignment wins, as `source` would
}

TEST_COMMAND="$(harness_env_value TEST_COMMAND)"
SCOPED_TEST_COMMAND="$(harness_env_value SCOPED_TEST_COMMAND)"
BUILD_RELEVANT_PATTERNS="$(harness_env_value BUILD_RELEVANT_PATTERNS)"
DEFAULT_BRANCH="$(harness_env_value DEFAULT_BRANCH)"
[ -n "$TEST_COMMAND" ] || exit 0

transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$transcript_path" ] && transcript_path="default"

# --- Scope: only run when the session actually touched relevant files. ---
# Union of: uncommitted working-tree diff, staged diff, everything committed on this
# branch since it diverged from the default branch, AND untracked new files (git diff
# alone misses brand-new files that were never staged).
if git rev-parse --git-dir >/dev/null 2>&1; then
  base_ref=$(git merge-base "${DEFAULT_BRANCH:-main}" HEAD 2>/dev/null || echo HEAD)
  changed_files="$(
    {
      git diff --name-only 2>/dev/null
      git diff --name-only --cached 2>/dev/null
      git diff --name-only "$base_ref" HEAD 2>/dev/null
      git ls-files --others --exclude-standard 2>/dev/null   # untracked new files
    } | sort -u | grep -v '^[[:space:]]*$'
  )"

  if [ -n "${BUILD_RELEVANT_PATTERNS:-}" ]; then
    relevant_files=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      for pat in $BUILD_RELEVANT_PATTERNS; do
        case "$f" in *"$pat"*) relevant_files="$relevant_files$f"$'\n'; break ;; esac
      done
    done <<< "$changed_files"
    [ -n "$relevant_files" ] || exit 0  # nothing relevant changed: skip, don't tax the session
  else
    # No patterns configured: gate on "did this session change anything at all".
    [ -n "$changed_files" ] || exit 0
    relevant_files="$changed_files"
  fi
fi
# Not a git repo: no changed-file signal to skip on — run the gate (conservative).

# --- Trust gate: nothing from the repo is executed unless the USER trusted this path ---
trust_file="$HOME/.config/claude-harness/trusted-projects"
project_abs="$(pwd -P 2>/dev/null)"
trusted=0
if [ -n "$project_abs" ] && [ -f "$trust_file" ]; then
  while IFS= read -r t || [ -n "$t" ]; do
    t="${t%$'\r'}"
    while [ "${t# }" != "$t" ] || [ "${t#$'\t'}" != "$t" ]; do
      t="${t# }"
      t="${t#$'\t'}"
    done
    case "$t" in
      ''|'#'*) continue ;;
    esac
    if [ "$t" = "$project_abs" ]; then
      trusted=1
      break
    fi
  done < "$trust_file"
fi

if [ "$trusted" -ne 1 ]; then
  # Untrusted: never eval TEST_COMMAND. Say so once a day, then stay quiet — a silent
  # inert gate is how people end up believing they're protected when they aren't.
  key_untrusted=$(printf '%s' "$project_abs" | shasum | cut -d' ' -f1)
  stamp="${TMPDIR:-/tmp}/claude-harness-untrusted-$key_untrusted-$(date +%Y%m%d)"
  if [ ! -f "$stamp" ]; then
    : > "$stamp" 2>/dev/null
    echo "harness: $project_abs not in $trust_file; stop-gate inactive. Run /harness:harness-init or add the path." >&2
    exit 1   # non-blocking notice: shown, does not block the turn
  fi
  exit 0
fi

# --- Loop guard state (per-session, keyed on transcript_path) ---
state_dir="${TMPDIR:-/tmp}/claude-harness-stop-test-gate"
mkdir -p "$state_dir" 2>/dev/null
key=$(printf '%s' "$transcript_path" | shasum | cut -d' ' -f1)
state_file="$state_dir/$key"
attempts=0
[ -f "$state_file" ] && attempts=$(cat "$state_file" 2>/dev/null || echo 0)

# --- Pick the command: the scoped one per turn when configured and there are files to
# scope to; otherwise the full suite. Deleted files are dropped (a runner cannot select
# tests for a path that is gone), and every path is single-quoted for the eval.
gate_cmd="$TEST_COMMAND"
if [ -n "$SCOPED_TEST_COMMAND" ]; then
  quoted_files=""
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    q=$(printf "%s" "$f" | sed "s/'/'\\\\''/g")
    quoted_files="$quoted_files'$q' "
  done <<< "${relevant_files:-}"
  case "$SCOPED_TEST_COMMAND" in
    *"{files}"*)
      [ -n "$quoted_files" ] && gate_cmd="${SCOPED_TEST_COMMAND/\{files\}/$quoted_files}" ;;
    *) gate_cmd="$SCOPED_TEST_COMMAND" ;;
  esac
fi

test_output=$(eval "$gate_cmd" 2>&1)
test_status=$?

if [ "$test_status" -eq 0 ]; then
  rm -f "$state_file" 2>/dev/null
  exit 0
fi

attempts=$((attempts + 1))
echo "$attempts" > "$state_file"

if [ "$attempts" -gt 3 ]; then
  echo "WARNING (stop-test-gate): '$gate_cmd' still failing after 3 blocked stops. Letting the session end anyway (loop guard) — do NOT open a PR until this is green." >&2
  rm -f "$state_file" 2>/dev/null
  exit 1
fi

{
  echo "BLOCKED: '$gate_cmd' failed (attempt $attempts/3). Fix the failure before finishing this turn."
  echo "$test_output" | tail -60
} >&2
exit 2
