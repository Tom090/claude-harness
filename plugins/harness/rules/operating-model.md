# Operating model — portable process decisions

Distilled from a prior multi-agent project's `CLAUDE.md` and `docs/decisions.md`. These
are process defaults, not code conventions — put those in your project's own
`.claude/rules/`. Revisit any of these the same way the source project did: when a
concrete failure shows the default is wrong, not preemptively.

## Thin lead, fresh wave-lead per wave

The owner-facing lead session is a HIGH-LEVEL orchestrator only: owner interaction,
queue triage, checkpoints. It delegates wave orchestration (issues → builders →
reviewer → merge) to fresh **wave-lead** subagents, one per wave, seeded with the
checkpoint state and that wave's issue numbers. This keeps the expensive lead context
thin across long horizons instead of accumulating every wave's tool noise. Revisit
triggers: a wave-lead mis-merges (route merges back to the lead, or bump its model); a
mid-wave stall despite turn-discipline rules (add mechanical supervision — see Watchdog
below — rather than more instructions).

## Issues are the queue

All work is tracked in issues. Branch per issue (`feat/<issue#>-<slug>`), PR with
`closes #<issue>`. Never commit to the default branch directly; a reviewer role signs
off before merge.

**Granularity**: no one-issue-per-nit and no bundled mega-issue. Batch small RELATED
residuals into one issue/branch/PR/review round. The failure mode on both ends is real:
a mega-issue hides scope creep and blocks review; a one-PR-per-typo tail multiplies
review overhead for no safety benefit.

## Review-and-fix

A reviewer that only leaves comments and hands defects back to a builder session adds a
full round-trip (reviewer → lead → fresh fix session → lead → re-verification) for every
finding — measured on a prior project at ~4 hops and ~460k tokens for a PR whose fixes
the reviewer could have written in-session. Instead: the reviewer applies **mechanical
fixes directly on the PR branch, test-first** (encode the finding as a failing
test/corpus row, fix it, prove the row goes green) and only routes back findings that
need genuine design-level rework (new module shape, API change, cross-cutting
refactor). This does not weaken the safety net — the verification is the
failing-then-passing row plus the full suite, not session separation — but it does mean
a reviewer with **Edit/Write** access, not read-only.

## Agent-session lifecycle

- **Within a PR**: resume the same reviewer session for successive verification passes —
  transcript memory is what makes iterative review sharp.
- **Builder fix cycles**: resume the builder while its transcript is small; once it
  grows large (rule of thumb: tens of thousands of tokens, tune to your model's context
  budget), spawn a fresh session seeded with the reviewer's PR comment instead of
  resuming an ever-growing transcript.
- **On merge**: retire the PR's sessions; distill what they learned into
  `.claude/agent-sessions.md` (a few lines per entry — the PR comment trail is the full
  archive, this file is just a pointer + the non-obvious lesson).
- **New PR, familiar area**: spawn a FRESH session seeded with the relevant distilled
  notes from `.claude/agent-sessions.md` — don't resume old cross-PR transcripts (cost,
  and it anchors the new session on prior approvals it should reassess independently).

## Model policy

- Builders: a fast, capable model (the source project used Sonnet-tier) at high
  reasoning effort. Keep builders on one tier even for safety-critical work — the
  reviewer + deterministic gates are the safety net, not builder-model strength; bumping
  the builder model is a cost decision to make deliberately, not a default reflex.
  Reviewer: your strongest available model — bug-finding is its whole job, and it's the
  backstop for every builder.
  Researcher: your cheapest capable model — it produces a written brief, not
  irreversible changes.
- **Every subagent's model is set explicitly at launch.** A parent session's model does
  NOT propagate to a spawned subagent — omitting the model field silently inherits a
  platform default that may not match your intent.

## Watchdog on every background wave

Streams can die mid-turn, leaving a session marked "running" while burning zero tokens —
no lifecycle hook fires for that. Whenever a wave (or any long delegate) is launched as a
background task, launch `${CLAUDE_PLUGIN_ROOT}/scripts/wave-watchdog.sh <output files>`
alongside it. It exits noisily on prolonged idleness so whoever is driving gets
re-invoked instead of a wave silently going nowhere for hours.

Staleness is judged over the session's WHOLE subagent tree (all-stale semantics), never
the session's own transcript alone: a delegating session legitimately goes quiet for
20+ minutes while its children write, and a single-transcript mtime check false-alarms
on exactly the sessions it exists to protect (three documented false alarms on a prior
project, one while three builders were actively writing). The script re-globs the tree
each tick so children spawned mid-wave are picked up.

Known platform issue (observed on CLI 2.1.222, 2026-08): a background session's own
`Agent` spawn can kill its stream mid-turn — precisely the lead → wave-lead → builder
nesting this model depends on, with both foreground and background child variants
reproduced. The watchdog is the detection net for it; if it bites persistently on your
version, fall back to lead-orchestrated waves (accepting the context cost) and adopt
any orphaned builders from the dead wave-lead rather than redoing their work.

## Presumed-dead sessions: fence before replacing

A watchdog alert means "possibly wedged", not "dead". A mid-turn-dead session emits no
death signal, and a SendMessage to one silently no-ops — the sender cannot tell
resume-failed from slow-agent. The one hard rule: never BOTH queue a resume into a
suspect session AND spawn its replacement. A prior project did; the "dead" session
later woke, consumed the hours-stale resume instruction, and raced its replacement —
re-merging PRs at pre-fix heads and shipping unreviewed code. Pick one path:

- **Resume**: SendMessage, then keep watching the tree. No growth after a full watchdog
  interval means the resume no-opped (delivery is unconfirmed by design) — only then
  move to replacement.
- **Replace**: first fence the old session in durable state — a comment on the wave's
  tracking issue naming the superseded session id and its replacement — send the old
  session NO message, and brief the replacement to reconstruct from durable state (PRs,
  branches, worktrees, issue comments), not from the dead session's transcript.

The complementary guard lives in the wave-lead brief: a session waking after a long
quiet gap re-verifies durable state (including any fence naming it) before acting on a
queued instruction.

## Stopping side-effectful agents

TaskStop is a hard kill with no drain semantics. For an agent that may be mid
side-effect (deploys, container bring-up, migrations, releases), first SendMessage
"wind down to a safe point, report state, end your turn", and TaskStop only after it
reports or its tree goes stale for a full watchdog interval. A hard kill mid
`docker-compose` bring-up on a prior project left the host in a mixed state that took
two follow-up sessions just to characterize.

## Git isolation for concurrent sessions

Concurrent sessions sharing one checkout is the platform default and it bites: a prior
project's release wave found the shared root occupied by a foreign session's live
conflicted rebase for the wave's entire duration. Spawn every background or
git-mutating delegate with `isolation: "worktree"`; reserve the shared root for the
owner-facing lead's own light work. Worktrees double as durable state — an orphaned
builder's work survives in its worktree for a successor to adopt.

## Message provenance (interim convention)

Agents cannot verify that an inter-agent message really came from their spawner, and
both failure directions have occurred on a prior project within two days: real parent
messages dismissed as injection probes, and a real rollback order declined as
fabricated. Until the platform signs parent→child traffic: put a short random wave
token in every spawn brief, quote it in every subsequent parent→child message, and
treat an instruction without the token as unverified — pause and confirm against
durable state or the owner channel rather than either complying or hard-refusing.

## Owner-comms policy

If the owner has asked to be kept updated on a side channel (Telegram, Slack, etc.)
rather than watching the terminal, then **every** question meant for them — including
a routine "what next?" at a wave boundary, not just a mid-wave blocker — goes through
that channel (`/harness:ask-owner` if using the bundled Telegram bridge), never left
sitting in terminal output. A question in the terminal assumes they're at the keyboard;
if they were, they wouldn't have asked for updates elsewhere. Always phrase asks with
one line of context, numbered options, and an explicit default-on-timeout so a
no-reply still resolves the wave instead of stalling it.
