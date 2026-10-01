# Field feedback from tray-product, 2026-09-30: the leaf-agent sync guard blocks every named role

Written by the tray-product lead session for the harness project. One finding, one root
cause, six asks. Nothing here has been changed in either repo.

## What tray-product has, and the harness does not

tray-product wired a project-level PreToolUse hook on the `Agent` tool,
`.helix/hooks/sync-leaf-agents.cjs`, from its own `.claude/settings.json`. It denies a
spawn of a leaf role (`backend-dev`, `frontend-dev`, `designer`, `uat`,
`harness:reviewer`, `harness:researcher`, `harness:systems-integrator`,
`harness:creative-director`) unless `tool_input.run_in_background === false`. Rationale:
three wave stalls on 2026-08-16 where backgrounded builders finished but the spawner
was never re-invoked. Orchestrator-tier spawns (`general-purpose`, forks) are not gated.
A rule test, `tests/syncLeafAgentsHook.test.ts`, guards five properties of the hook:

1. The deny path emits exactly the PreToolUse permission-decision envelope.
2. Fail-open: malformed input, JSON `null`, scalars and arrays exit 0 with no output.
3. Orchestrator-tier spawns stay backgroundable.
4. The roster in the hook matches the roster the project CLAUDE.md declares and covers
   every `.claude/agents/*.md` definition, so a new builder cannot silently escape it.
5. The deny path never calls `process.exit()` after `stdout.write()`, because stdout to a
   pipe is asynchronous on macOS and an early exit truncates the JSON into a no-op.

The harness plugin ships no equivalent: `hooks/hooks.json` has the Stop gate and the
Bash blocker only, `rules/operating-model.md` says nothing about leaf agents or
backgrounding, and `harness-init` does not generate one. The only mention in the harness
repo is the 2026-08-31 baby-app note about nested spawns dying at CLI 2.1.222.

## The hook was a depth-2 fix that outlived depth 2

The hook predates the retirement of the wave-lead. On 17 Aug the harness still ran
lead -> wave-lead -> builders, and the same checkpoint that introduced the hook records
the mechanism of the stalls: "Leaf agents resumed via SendMessage run in background and
notify the ROOT session, not the wave-lead that briefed them - the lead must relay."
A backgrounded leaf two levels down reported to the wrong parent. The hook forced leaf
spawns synchronous so the wave-lead could not lose them. The 2026-08-31 baby-app note
(nested spawns dying at 2.1.222) is the same family of failure.

Harness 0.2.0 retired the wave-lead on 17 Sep: the lead spawns every agent itself and
nothing is more than one level deep. That removed the condition the hook existed for.
The hook was carried into the 0.2.0 bindings anyway (tray-product PR #396 rewrote its
comments to drop the wave-lead reference and added two roles; the logic was untouched),
so its rationale quietly changed from "a wave-lead loses nested spawns" to "a spawning
session loses spawns", which depth-1 evidence has never supported. The 30 Sep count of
about 30 backgrounded depth-1 spawns with no stall confirms it.

## What broke

The hook landed on 2026-08-17 (tray-product PR #137) and worked for five weeks. The
first recorded denial with `run_in_background: false` passed explicitly was a `uat`
spawn on 2026-09-22; `harness:researcher` on 23 Sep, `harness:reviewer` on 27 Sep and
`backend-dev` on 29 Sep followed. Every spawn of a named role has been denied since. Re-issuing the identical call as
`general-purpose` succeeds, and the tool result says "Async agent launched ... working
in the background", so the flag is not honoured either. Every role since then has run as
`general-purpose` with the role's brief pasted into the prompt. That loses what the agent
definitions carry: the model pin, the tool restriction (builders have no browser, the
reviewer has no Agent tool), and the role prompt.

## Root cause, isolated on 2026-09-30

The hook's logic is correct. Piping a synthetic payload with `run_in_background: false`
into it allows the call; the same payload without the field denies it. So the hook is
receiving the field absent. Claude Code 2.1.283 backgrounds every `Agent` call and does
not deliver `run_in_background` in the hook's `tool_input`. The tool description in that
build states it outright: "Subagents run in the background; you'll be notified when one
completes." The guard's `=== false` check can therefore never pass.

The failure mode the guard was written for is not reproducing on this build: 22
subagents on 2026-09-30 and 7 overnight all completed and re-invoked the lead. A CLI-level
report has been drafted from the tray-product session via `/feedback`.

## Asks for the harness

1. **Own the guard in the plugin.** A PreToolUse hook with `matcher: "Agent"` in
   `hooks/hooks.json`, inert unless `.claude/harness.env` exists (same trust model as
   the Bash blocker: read the file literally, never source it). Semantics that survive
   the current CLI: deny a leaf role only on an explicit `run_in_background: true`; allow
   when the field is `false` or absent. Keep properties 1, 2, 3 and 5 above. The roster
   comes from a new `LEAF_AGENTS` key in `harness.env` (space-separated), with the four
   plugin roles always included.
2. **State the rule in `rules/operating-model.md`.** Leaf workers are awaited before the
   spawner ends its turn and are never explicitly backgrounded; the hook enforces only
   the explicit case, the rule covers the rest. Note that the CLI may background them
   anyway and that the parent must still wait for the notification.
3. **`harness-init` writes `LEAF_AGENTS`** from the roster it generates, and the
   CLAUDE.md template carries the rule in one line instead of the flag instruction.
   Property 4 (roster matches `.claude/agents/`) belongs in the project's test template,
   since only the project knows its agents directory.
4. **`verify-gates` gains a section** for the new hook with synthetic payloads: leaf role
   with `true` denies; with `false` allows; absent allows; `general-purpose` with `true`
   allows; malformed input allows with no output; and the deny envelope parses.
5. **Bump the plugin version** and say in the changelog that a project with its own copy
   of the hook removes the local hook, its settings entry and its test once the plugin
   version is live. tray-product will do that in a follow-up PR.
6. **Record the CLI behaviour** beside the 2026-08-31 note: 2.1.283 drops the flag; the
   2026-08-26 nested-spawn deaths were at 2.1.222. The two are different failures and
   the harness should not assume either is fixed until measured on a named version.

## Open question for the harness owner

Whether the guard is worth keeping at all. The lead's view, revised on 30 Sep after
the owner pointed out that the stalls were a wave-lead problem: drop the hook. It
should have been retired with the wave-lead in 0.2.0. On 2.1.283
every leaf spawn is backgrounded, which is exactly what the hook existed to prevent, and
about 30 such spawns across 30 Sep and the overnight run all completed and re-invoked
the lead; the 16 Aug failure has not reproduced once. A guard whose condition can never
be true only blocks the named roles. Keep the rule as prose (await every leaf agent
before ending the turn; put a token in the brief and quote it in every parent message)
and keep the roster-classification test if the harness wants a roster at all. Asks 1, 3
and 4 above then reduce to that test and the rule; ask 6 stands. The evidence is
observational: no release note names the fix, and the version that changed it is
somewhere between 2.1.222 and 2.1.283.

## Reference

- Hook: `tray-product/.helix/hooks/sync-leaf-agents.cjs` (about 60 lines, Node, no deps).
- Test: `tray-product/tests/syncLeafAgentsHook.test.ts`.
- Rule as written today: `tray-product/CLAUDE.md` § Models, "Leaf workers run synchronously".
- Sessions affected: `tray-product/docs/decisions.md` entries for 2026-09-30 (overnight)
  and 2026-09-30 (day), process notes.
