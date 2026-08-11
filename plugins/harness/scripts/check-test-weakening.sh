#!/bin/bash
# Test-weakening diff guard.
#
# Flags a PR/branch that disables, deletes, or shrinks existing tests or corpus rows
# without an explicit ruling reference in the PR body. Meant to be run by a reviewer
# agent/role (see rules/operating-model.md) and by whoever merges a harness-only PR that
# touches this script itself. Not wired as a live hook: unlike the Stop/PreToolUse gates,
# this needs the FULL branch diff + the PR body text together, and PR bodies are
# constructed too many ways (--body, --body-file, heredoc) to parse reliably out of a
# single Bash command string — a script invoked explicitly is the honest "deterministic"
# shape here.
#
# Usage:
#   check-test-weakening.sh [--base REF] [--head REF] [--pr N]
#                            [--body-file PATH] [--body TEXT]
#
# base   defaults to `git merge-base main HEAD` (or the branch set by DEFAULT_BRANCH in
#        .claude/harness.env, default "main")
# head   defaults to HEAD
# ruling text source, first match wins: --body TEXT, --body-file PATH, --pr N (fetches
#   via `gh pr view N --json body -q .body`); if none given and the current branch has
#   an open PR, that PR's body is fetched automatically.
#
# Project-specific tuning (optional, read from .claude/harness.env if present; this
# script does NOT require the config file to exist — generic defaults below cover the
# common stacks):
#   TEST_RELEVANT_PATTERNS  extra colon-separated shell glob patterns (bash `case`
#                           syntax) treated as test-relevant, e.g.
#                           "firestore-tests/fixtures/*.json:*[Cc]orpus*"
#   RULING_KEYWORDS         extra pipe-separated grep -Ei alternatives that count as a
#                           ruling reference, on top of the generic defaults
#   DEFAULT_BRANCH          branch to diff against when --base is not given (default main)
#
# Exit 0: no weakening signals, OR signals found but a ruling reference is present.
# Exit 1: weakening signals found with NO ruling reference — needs a human/owner call.

set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

# shellcheck disable=SC1091
[ -f .claude/harness.env ] && source .claude/harness.env

base=""
head="HEAD"
pr_number=""
body_file=""
body_text=""
default_branch="${DEFAULT_BRANCH:-main}"

while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --pr) pr_number="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    --body) body_text="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$base" ] && base=$(git merge-base "$default_branch" "$head" 2>/dev/null || echo "$head")

# --- Resolve ruling-reference text ---
if [ -z "$body_text" ] && [ -n "$body_file" ] && [ -f "$body_file" ]; then
  body_text=$(cat "$body_file")
fi
if [ -z "$body_text" ] && [ -n "$pr_number" ]; then
  body_text=$(gh pr view "$pr_number" --json body -q .body 2>/dev/null)
fi
if [ -z "$body_text" ] && [ -z "$pr_number" ] && [ -z "$body_file" ]; then
  body_text=$(gh pr view --json body -q .body 2>/dev/null)  # current-branch PR, if any
fi

has_ruling_reference() {
  local pattern='owner ruling|owner-ruling|ruling:|decisions\.md|ratified'
  [ -n "${RULING_KEYWORDS:-}" ] && pattern="${pattern}|${RULING_KEYWORDS}"
  printf '%s' "$body_text" | grep -Eiq "$pattern"
}

# --- Test-relevant path patterns (generic defaults across common stacks, plus any
# project-specific patterns from TEST_RELEVANT_PATTERNS) ---
is_test_relevant() {
  case "$1" in
    *test*|*Test*|*spec*|*Spec*) return 0 ;;
    *[Ff]ixture*|*[Cc]orpus*|*[Pp]hrasing*) return 0 ;;
  esac
  if [ -n "${TEST_RELEVANT_PATTERNS:-}" ]; then
    local IFS=':'
    local pat
    for pat in $TEST_RELEVANT_PATTERNS; do
      # shellcheck disable=SC2254
      case "$1" in
        $pat) return 0 ;;
      esac
    done
  fi
  return 1
}

changed_files=$(git diff --name-only --diff-filter=ACDMR "$base" "$head" 2>/dev/null)
flags=()

while IFS= read -r f; do
  [ -z "$f" ] && continue
  is_test_relevant "$f" || continue

  in_base=$(git cat-file -e "$base:$f" 2>/dev/null && echo yes || echo no)
  in_head=$(git cat-file -e "$head:$f" 2>/dev/null && echo yes || echo no)

  if [ "$in_base" = yes ] && [ "$in_head" = no ]; then
    flags+=("DELETED test-relevant file: $f")
    continue
  fi
  [ "$in_head" = no ] && continue   # file added or renamed-away; nothing to compare

  # Signal: new disabling markers added (diff `+` lines only) — covers JVM/JS/Python/Go
  added_disablers=$(git diff -U0 "$base" "$head" -- "$f" 2>/dev/null | grep '^+' | grep -Ev '^\+\+\+' \
    | grep -Ec '@Disabled|@Ignore\(|\.skip\(|\bxit\(|\bxdescribe\(|pytest\.mark\.skip|t\.Skip\(|#\[ignore\]')
  if [ "${added_disablers:-0}" -gt 0 ]; then
    flags+=("DISABLED marker(s) added in $f ($added_disablers line(s))")
  fi

  if [ "$in_base" = yes ]; then
    # Signal: test-declaring line count decreased (JVM @Test, JS it/test/describe,
    # Python def test_, Go func Test)
    test_decl_regex='@Test\b|\bit\(|\btest\(|\bdescribe\(|\bdef test_|func Test[A-Z]'
    base_count=$(git show "$base:$f" 2>/dev/null | grep -Ec "$test_decl_regex")
    head_count=$(git show "$head:$f" 2>/dev/null | grep -Ec "$test_decl_regex")
    if [ "${head_count:-0}" -lt "${base_count:-0}" ]; then
      flags+=("TEST COUNT decreased in $f ($base_count -> $head_count)")
    fi

    # Signal: JSON corpus/fixture array shrunk
    case "$f" in
      *.json)
        base_n=$(git show "$base:$f" 2>/dev/null | jq 'if type=="array" then length elif type=="object" then (keys|length) else empty end' 2>/dev/null)
        head_n=$(git show "$head:$f" 2>/dev/null | jq 'if type=="array" then length elif type=="object" then (keys|length) else empty end' 2>/dev/null)
        if [ -n "$base_n" ] && [ -n "$head_n" ] && [ "$head_n" -lt "$base_n" ]; then
          flags+=("CORPUS/FIXTURE row count decreased in $f ($base_n -> $head_n)")
        fi
        ;;
    esac
  fi
done <<< "$changed_files"

if [ "${#flags[@]}" -eq 0 ]; then
  echo "OK: no test-weakening signals between $base and $head."
  exit 0
fi

echo "Test-weakening signals detected between $base and $head:"
for f in "${flags[@]}"; do echo "  - $f"; done

if has_ruling_reference; then
  echo
  echo "ADVISORY PASS: ruling reference found in PR body (owner ruling / decisions.md / ratified) — proceeding."
  exit 0
fi

echo
echo "BLOCKED: no ruling reference found in the PR body. Either this is an unintentional"
echo "regression (fix it), or it's a deliberate, approved change — cite the ruling (e.g."
echo "'owner ruling YYYY-MM-DD, see docs/decisions.md') in the PR body."
exit 1
