---
name: verify-gates
description: Standalone synthetic-trigger verification pass for the deterministic gates (stop-test-gate, destructive-bash blocker, test-weakening guard). Run after harness-init, in a FRESH session, and any time the gates themselves change.
---
# Verify gates

**Run in a fresh session if the plugin itself was installed or enabled during the current
session** — plugin/hook *registration* is not hot-reloaded. `.claude/harness.env` is read
by the hook scripts at run time, so a harness.env written earlier in this session IS
picked up without a restart. If in doubt, restart Claude Code in this project directory
and re-run this skill.

Prerequisites, check first:
- `.claude/harness.env` exists with at least `TEST_COMMAND` set — both hooks are silent
  no-ops without it (see `${CLAUDE_PLUGIN_ROOT}/templates/harness.env.example`).
- `jq` is installed (`command -v jq`). Without it the blocker falls back to `python3`,
  and without either it cannot inspect commands at all.

**Every trigger below is written to be harmless if the gate is NOT live** — a
verification that destroys work when the thing it verifies is broken is worse than no
verification. Do not "simplify" them into real force-pushes or real deletions.

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
- **Also verify the skip path**: with `BUILD_RELEVANT_PATTERNS` set, change only a docs
  file (nothing matching it) — the hook should exit 0 immediately, no test run at all.
  With that key unset the equivalent check is a clean working tree (nothing changed at
  all), which also skips.

## 2. Destructive-bash blocker — synthetic dangerous commands

Each trigger below is inert if the hook is dead: the pushes target a remote name that
does not exist, the reset runs in a throwaway repo, and the delete targets a path that
does not exist. Run them exactly as written.

```bash
# setup: a remote name nothing resolves to, and a throwaway repo for the reset probe
throwaway=$(mktemp -d) && git -C "$throwaway" init -q && git -C "$throwaway" commit -q --allow-empty -m x
```

Expect all four to be **denied by the hook, before execution**, with a clear reason:
- `git push --force harness-verify-no-such-remote HEAD`
- `git push -f harness-verify-no-such-remote HEAD`
- `git -C "$throwaway" reset --hard HEAD` (never `HEAD~1` in the real repo)
- `rm -rf ./harness-verify-no-such-dir`

Then confirm these are **allowed** (this hook stays out of the way; the normal permission
flow still applies). Each is harmless when it does run — that's how you tell "allowed"
from "denied": you see the command's own output/error, not a policy message.
- `git push --force-with-lease harness-verify-no-such-remote HEAD` (git errors out on the
  unknown remote — that error is the PASS signal)
- `rm -rf ./build/harness-verify-no-such-dir` (matches the built-in build-cache scope)
- `mkdir -p /tmp/harness-verify-scratch && rm -rf /tmp/harness-verify-scratch` (a literal
  /tmp path). Note a command substitution in the target — `rm -rf "$(mktemp -d)"` — is
  *denied*: the guard cannot resolve the path, and it default-denies on ambiguity.

If `PROTECTED_PATHS` is set, confirm `rm -rf <that path>/harness-verify-no-such-dir` is
denied even though the path would otherwise look ordinary. Clean up `$throwaway`.

## 3. Test-weakening guard — synthetic regression

- On a scratch branch: delete a test file, or add a `@Disabled`/`.skip(`/`xit(`-style
  marker to an existing test, or shrink a JSON fixture array.
- Run `${CLAUDE_PLUGIN_ROOT}/scripts/check-test-weakening.sh --base <DEFAULT_BRANCH from
  .claude/harness.env, e.g. main> --head <scratch-branch>` with no ruling text —
  **expect BLOCKED**.
- Re-run with `--body "owner ruling 2026-01-01: intentional, see docs/decisions.md"` —
  **expect ADVISORY PASS**.
- Clean up the scratch branch.

## Report

State PASS/FAIL for each of the three gates with what you actually observed (not "should
work" — the point of this skill is real synthetic triggers). Anything that didn't behave
as documented is a bug in the harness plugin itself, not the project — report it as such
rather than silently working around it.
