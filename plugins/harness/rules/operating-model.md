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

## Design-led wave shape

An optional wave shape for projects where correctness alone doesn't guarantee the thing
is good to use/play/read — most commonly games and other experience-driven products.
Adopt it deliberately (it adds roles and a slower gate before build); the plain
issue → builder → reviewer → merge loop above stays the default for everything else.

**The wave shape**: design → sign-off → build → tune → experience report → verdict →
owner build. A design-authoring role writes the spec, a judgment-tier role (see below)
signs off before any code is written, builders build it, a tuning pass adjusts the
constants by playing the result, a play-testing role writes up what happened, the
judgment-tier role rules on it, and the owner gets a working build every wave.

**Unit of work: the experience slice.** An issue is still the queue item, but a slice
issue carries a spec with four parts:
1. **Pillar/goal served** — which product-vision pillar this slice exists for.
2. **Player/user-experience goal**, one sentence, about the *feeling* produced, not the
   mechanics implemented (e.g. "the player does X because they just watched Y" reads
   right; "adds X" or "implements Y" reads as a goal tuple, not an experience).
3. **The beat**: setup, pressure, response, recap (or this project's equivalent
   dramatic shape) — what triggers, what the user sees, what voice speaks to them, what
   they can do afterward.
4. **Acceptance**: the automated test suite stays the correctness gate, unchanged. The
   feel gate is separate and additive — a named play-testing agent plays it and states,
   in its own words, what happened and how it felt, and then the judgment-tier role's
   verdict.

Mechanism-only work (a new data field, a plumbing change with no user-facing feel) stays
an ordinary issue; it's sequenced inside a slice rather than issued as one.

**The play-and-tune loop**, for every gameplay/UX constant marked `// TUNABLE` (or this
project's equivalent convention):
1. A design role states the *intended feel* of the constant in the slice spec (not a
   number — a felt target: "should arrive before the player feels safe," not "= 40s").
2. The builder picks a first value, marks it `// TUNABLE`, as usual.
3. A systems/tuning role plays the build, adjusts the value, replays, and logs every
   change with its reason — tuning changes stay scoped to the tuning module/constants
   file, nothing else.
4. The play-testing report or the judgment-tier verdict can send a constant back for
   another pass. **Three passes is the cap per wave** — past that, the slice gets
   redesigned rather than re-tuned a fourth time; a constant that won't converge in
   three passes is usually evidence the beat itself is wrong, not the number.

**The Fable-tier (judgment-tier) placement rule.** A judgment-tier model — the
strongest available, spent sparingly — touches documents and verdicts only: it never
writes code and never runs a long or unbounded play session. It shows up at exactly
three moments per wave, cheapest first:
1. **Slice sign-off, before build** — reads the one-page slice spec, answers one
   question (does this have a dramatic shape and a voice, or is it a goal tuple in
   disguise?). Cheapest point to catch the failure mode; always runs.
2. **Play verdict, after build and tune** — reads the experience report and tuning log,
   plays a screenshot-bounded session (see
   `${CLAUDE_PLUGIN_ROOT}/rules/token-efficiency.md` for the budget), rules
   ship/tune/send-back with one specific named reason, never a checklist.
3. **Escalation, on flag only** — rules when another agent flags genuine uncertainty;
   this role doesn't go looking for escalations, it responds to a named one.

**Step-down pattern**: run the play-verdict moment (2) every wave while the model is
uncalibrated for this project — early waves, a new judgment-tier model, or a project
just adopting this shape. Once verdicts have proven reliable (the owner's own reaction
consistently matches the verdict), route moment 2 to on-flag-only, same as escalations,
and keep only sign-off (1) running every wave. This is a per-project tuning decision to
revisit explicitly, not a default to assume on day one.

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
- **Judgment tier.** The strongest available model is spent on judgment/planning turns —
  sign-off, verdicts, escalation rulings — sparingly, not on volume generation.
  Execution roles (builders, and most design-authoring roles) run one tier below that;
  reserving the top tier for judgment is what keeps its cost bounded across a wave.
  **Self-enhancement guard**: a judgment-tier role must never also author what it
  judges (the design-led wave shape's creative-director/judge role is the concrete
  case — it signs off on and rules on slice specs it did not, and must not, write) —
  same-family judges show measured bias toward their own output, so the judge and the
  author are always different roles even when both could technically run on the same
  model.

## Watchdog on every background wave

Streams can die mid-turn, leaving a session marked "running" while burning zero tokens —
no lifecycle hook fires for that. Whenever a wave (or any long delegate) is launched as a
background task, launch `${CLAUDE_PLUGIN_ROOT}/scripts/wave-watchdog.sh <output files>`
alongside it. It exits noisily on prolonged transcript idleness so whoever is driving
gets re-invoked instead of a wave silently going nowhere for hours.

## Owner-comms policy

If the owner has asked to be kept updated on a side channel (Telegram, Slack, etc.)
rather than watching the terminal, then **every** question meant for them — including
a routine "what next?" at a wave boundary, not just a mid-wave blocker — goes through
that channel (`/harness:ask-owner` if using the bundled Telegram bridge), never left
sitting in terminal output. A question in the terminal assumes they're at the keyboard;
if they were, they wouldn't have asked for updates elsewhere. Always phrase asks with
one line of context, numbered options, and an explicit default-on-timeout so a
no-reply still resolves the wave instead of stalling it.
