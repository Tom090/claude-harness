---
name: verify-gates
description: Standalone synthetic-trigger verification pass for the deterministic gates (stop-test-gate, destructive-bash blocker, test-weakening guard) plus the plugin citation check. Run after harness-init, in a FRESH session, and any time the gates themselves change.
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
- This project's absolute physical path is in `~/.config/claude-harness/trusted-projects`
  (`grep -qxF "$(pwd -P)" ~/.config/claude-harness/trusted-projects && echo trusted`).
  Untrusted, the Stop gate deliberately never runs `TEST_COMMAND`, and §1 below would
  false-fail. `/harness:harness-init` adds it; add it by hand only for a project you
  bound yourself.

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
- **Also verify the scoped path**: temporarily set
  `SCOPED_TEST_COMMAND="echo scoped: {files}; false"` in `.claude/harness.env`, change a
  file matching `BUILD_RELEVANT_PATTERNS`, end the turn. **Expect** a block whose output
  names that file, quoted, and not `TEST_COMMAND`'s output. Restore the key afterwards.
- **Also verify the skip path**: with `BUILD_RELEVANT_PATTERNS` set, change only a docs
  file (nothing matching it) — the hook should exit 0 immediately, no test run at all.
  With that key unset the equivalent check is a clean working tree (nothing changed at
  all), which also skips.
- **Also verify the untrusted path** (cheap, and worth doing once): temporarily comment
  out this project's line in `~/.config/claude-harness/trusted-projects`, then end a turn
  with a code change pending. **Expect** a one-line notice that the path isn't trusted and
  the gate is inactive — a *notice*, not a block, and `TEST_COMMAND` must not run (if it
  has an observable side effect, confirm the side effect didn't happen). A second turn
  should be silent (the notice is once per day per project). Restore the line afterwards
  and confirm the gate blocks again.

## 2. Destructive-bash blocker — synthetic dangerous commands

Each trigger below is inert if the hook is dead: the pushes target a remote name that
does not exist, the reset runs in a throwaway repo, and the delete targets a path that
does not exist. Run them exactly as written.

```bash
# setup: a remote name nothing resolves to, and a throwaway repo for the reset probe
throwaway=$(mktemp -d) && git -C "$throwaway" init -q && git -C "$throwaway" commit -q --allow-empty -m x
```

Expect all five to be **denied by the hook, before execution**, with a clear reason:
- `git push --force harness-verify-no-such-remote HEAD`
- `git push -f harness-verify-no-such-remote HEAD`
- `git push harness-verify-no-such-remote +HEAD:main` (a +refspec is a force push)
- `git -C "$throwaway" reset --hard HEAD` (never `HEAD~1` in the real repo)
- `rm -rf ./harness-verify-no-such-dir`

Then confirm these are **allowed** (this hook stays out of the way; the normal permission
flow still applies). Each is harmless when it does run — that's how you tell "allowed"
from "denied": you see the command's own output/error, not a policy message.
- `git push --force-with-lease harness-verify-no-such-remote HEAD` (git errors out on the
  unknown remote — that error is the PASS signal)
- Three recorded false positives, each fixed by per-segment checking; all must be
  allowed (git errors on the remote, and `&&` stops the rest from running):
  `git push harness-verify-no-such-remote HEAD && git worktree remove -f no-such-wt`,
  `git push harness-verify-no-such-remote HEAD; echo "n + 1"`,
  `git push harness-verify-no-such-remote HEAD:harness-verify-branch`
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

## 4. Comment linter (if wired)

If `scripts/check-comments.mjs` exists in the project: on a scratch branch add a comment
containing `#123` to a source file and run `node scripts/check-comments.mjs --diff`.
**Expect** exit 1 naming that line. Revert.

## 5. Plugin citations resolve

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-citations.sh`. **Expect** `check-citations: OK`.
Anything else is a plugin bug: a `§` citation pointing at a heading that no longer
exists in `rules/`, or a reference to a retired role.

## 6. Work streams in containers (if `STREAM_*` is configured)

Skip this section when the project has no `STREAM_REPO`/`STREAM_RUNS_DIR` keys or Docker
is not installed. The in-container gate checks need `.claude/harness.env` on the branch
the stream clones (the default branch), or a brief that writes one first. Prerequisites: Docker running, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/stream.sh build`
done, and the two 0600 env-files present (`stream.sh launch` names them). Every trigger
needs an open GitHub issue; create one scratch issue per sub-step and close it afterwards.
Use a short id, e.g. `--slug verify`.

- **Smoke.** Brief: "Print `pwd`, list the loaded plugins from the init event you can
  see, do not open a PR, and finish with state `done`." Launch with `--max-turns 3`.
  `stream.sh collect <id> --wait` must return 0 with `result.json` carrying `state: done`,
  `token_ok: true`, `session_id` equal to the `session` file, and `usage` present. In
  `stream.jsonl` the `system`/`init` event lists the harness plugin. Inside the container
  (`docker exec <container> …`): `cat ~/.config/claude-harness/trusted-projects` prints
  `/workspace`; `env | grep -c ANTHROPIC_API_KEY` prints 0; `curl -sS --max-time 5
  https://example.com` fails (firewall); `touch /run/stream/probe && stat` on the host
  side of the run dir shows a fresh mtime (the watchdog reads through the bind mount).
- **Gates inside the container.** Brief: "Run `git push --force origin HEAD` and report
  what happened; then add a file `tests/zz-verify.test.js` whose one test fails, and end
  your turn; then delete it and finish with state `done`." **Expect** a PreToolUse denial
  from the blocker in `stream.jsonl` (search for `force`), and a Stop-gate block followed
  by a clean end after the deletion. If the push is not denied, the blocker is advisory
  under `bypassPermissions`: record that in the report as a harness finding.
- **Real stream.** A scratch issue "fix a typo in README". **Expect** a PR with the token
  in its body, `result.json.pr_url` set, state `done`, and `collect --wait` returning 0.
  Close the PR unmerged.
- **Stop.** Launch a brief that will take a while ("explore the repo and summarise every
  file, then finish") and run `stream.sh stop <id>` after the first assistant event
  appears. **Expect** the run to end within seconds, `status` = `stopped 0`, a
  `result.json` with `subtype` `error_during_execution` or `no_result` (an interrupted
  run has no structured output), and the container still `running`,
  so a `followup` resumes the same session. `stream.sh prune` must list it as kept (no
  PR, or PR open).
- **Follow-up.** On the smoke stream: `stream.sh followup <id> "Reply with state done and
  the token."` then `collect --wait`. **Expect** a second result with the same
  `session_id`.
- Clean up: close the scratch issues and PRs, then `docker rm -f` the verify containers
  by hand (prune keeps containers without a merged PR on purpose).

## Report

State PASS/FAIL for each of the three gates, the citation check and (when configured) the stream checks with what you actually observed (not "should
work" — the point of this skill is real synthetic triggers). Anything that didn't behave
as documented is a bug in the harness plugin itself, not the project — report it as such
rather than silently working around it.
