---
name: verify-gates
description: Standalone synthetic-trigger verification pass for the deterministic gates (stop-test-gate, destructive-bash blocker, test-weakening guard). Run after harness-init, in a FRESH session, and any time the gates themselves change.
---
# Verify gates

**Must run in a fresh session.** Hook/settings changes are not hot-reloaded mid-session
— a session that was open when `.claude/harness.env` or the plugin's hooks were written
will not see them take effect. If you just ran `/harness:harness-init` in this same
session, restart Claude Code in this project directory first.

Confirm `.claude/harness.env` exists with at least `TEST_COMMAND` set — both hooks are
silent no-ops without it (see `templates/harness.env.example`).

## 1. Stop-test-gate — synthetic failing test

- Introduce a deliberately failing test (or a trivially false assertion) in a scratch
  file under whatever path the project's test runner picks up.
- Make a trivial change to a file matching `BUILD_RELEVANT_PATTERNS` (or any file, if
  that key is unset) and end the turn.
- **Expect**: the turn is blocked (exit 2) with the last ~60 lines of the failing
  `TEST_COMMAND` output fed back. Fix the test (revert it), end the turn again.
- **Expect**: the turn ends cleanly this time.
- **Also verify the loop guard**: if you want to confirm the escape hatch, leave the
  test failing across 3 consecutive blocked turns — the 4th should end with a
  non-blocking WARNING instead of blocking forever. Clean up the state file
  (`$TMPDIR/claude-harness-stop-test-gate/`) and the scratch test afterward.
- **Also verify the skip path**: with only a docs file changed (nothing matching
  `BUILD_RELEVANT_PATTERNS`), the hook should exit 0 immediately — no test run at all.

## 2. Destructive-bash blocker — synthetic dangerous commands

Try each of these (they should all be **denied** before execution, with a clear reason):
- `git push --force`
- `git push -f`
- `git reset --hard HEAD~1`
- `rm -rf ` + some path outside the safe scope (e.g. a made-up `important-data/` dir)

Then confirm these are **allowed** (not denied by this hook — normal permission flow
still applies):
- `git push --force-with-lease`
- `rm -rf build/` (or `node_modules/`, `dist/`, `.gradle/`, anything in the built-in
  safe-scope list, or a `PROTECTED_PATHS` entry you did NOT set)
- `rm -rf /private/tmp/some-scratch-dir` (or wherever the scratchpad lives)

If `PROTECTED_PATHS` is set, confirm `rm -rf` against one of those paths is denied even
though it wouldn't otherwise match the deny patterns.

## 3. Test-weakening guard — synthetic regression

- On a scratch branch: delete a test file, or add a `@Disabled`/`.skip(`/`xit(`-style
  marker to an existing test, or shrink a JSON fixture array.
- Run `${CLAUDE_PLUGIN_ROOT}/scripts/check-test-weakening.sh --base main --head
  <scratch-branch>` with no ruling text — **expect BLOCKED**.
- Re-run with `--body "owner ruling 2026-01-01: intentional, see docs/decisions.md"` —
  **expect ADVISORY PASS**.
- Clean up the scratch branch.

## Report

State PASS/FAIL for each of the three gates with what you actually observed (not "should
work" — the point of this skill is real synthetic triggers). Anything that didn't behave
as documented is a bug in the harness plugin itself, not the project — report it as such
rather than silently working around it.
