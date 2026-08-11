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
background task, launch `scripts/wave-watchdog.sh <output files>` alongside it. It exits
noisily on prolonged transcript idleness so whoever is driving gets re-invoked instead of
a wave silently going nowhere for hours.

## Owner-comms policy

If the owner has asked to be kept updated on a side channel (Telegram, Slack, etc.)
rather than watching the terminal, then **every** question meant for them — including
a routine "what next?" at a wave boundary, not just a mid-wave blocker — goes through
that channel (`/harness:ask-owner` if using the bundled Telegram bridge), never left
sitting in terminal output. A question in the terminal assumes they're at the keyboard;
if they were, they wouldn't have asked for updates elsewhere. Always phrase asks with
one line of context, numbered options, and an explicit default-on-timeout so a
no-reply still resolves the wave instead of stalling it.
