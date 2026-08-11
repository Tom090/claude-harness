<!--
EXAMPLE BINDING, not a plugin rule. This is `.claude/rules/ux-verification.md` from the
mobile-app project the harness was extracted from, lightly trimmed of issue-number
references. It shows what a project-specific "verify changes in the running app, not
just in the diff" rule can look like once `/harness:harness-init` has bound the harness
to a real stack (here: Android + Compose + Maestro). Adapt the mechanism (emulator tool,
screenshot critique heuristics, extra reviewer passes) to your own stack; the shape —
a required running-app pass before every UI PR, self-critique then independent
re-verification — is the portable part.
-->
# UX verification

Diff review cannot see the defect class this kind of app actually suffers from (silent
failures, buried features, screens that don't match neighbouring ones). Any PR that adds
or changes a screen, dialog, sheet, or navigation MUST be verified in the running app.

## Requirement

- Run the project's UI-walkthrough tool before opening the PR: drive the changed
  screens on the emulator, read the screenshots yourself, self-critique, fix, re-run.
  Expect 2–3 iterations — the first render is rarely right.
- Commit the walkthrough flow(s) for the changed screens and name them in the PR body
  with a one-line summary of what the walkthrough showed. Flows are regression
  artifacts: extend or update them, don't delete them.
- Selectors are semantic (visible text, content descriptions) — never coordinates.
- The reviewer re-runs the PR's flows and judges the rendered screens independently.

## Critique heuristics (judge every screenshot against these)

1. **Reachability**: count taps from app-open to the feature. Core jobs must be ≤2 taps
   and thumb-reachable one-handed. A core feature behind an overflow menu is a finding.
2. **State honesty**: every async action shows progress and surfaces failure visibly.
   Silent rollback / zero-feedback retry is a defect even when the code is "correct".
3. **Real-world-use test**: readable and operable under the app's actual worst-case
   conditions (half-asleep and one-handed, outdoors in bright sun, on a low-end device —
   whatever fits your users) and in dark mode. Check both themes when a screen changes.
4. **Consistency**: uses the design system's tokens/components; matches the navigation
   and layout patterns of neighbouring screens rather than inventing local ones.
5. **Persona check**: for placement/findability questions the screenshots don't settle,
   consult a persona/user-research agent instead of guessing — cite its verdict in the
   critique.

## Fresh-eyes pass (context-free simulated user)

The heuristics above are applied by agents who know the app too well. A context-free
persona agent — no repo access, no feature checklist — catches "this feels like several
different screens stitched together" in a way a history-grounded review cannot:

- It role-plays a representative new user handed the app **cold**. It pursues
  self-invented goals on the emulator and reports confusion, dead ends, and
  cross-screen inconsistency in plain language.
- **The spawner preps the environment** (emulator, fixture backend, install, fixture
  sign-in) so the persona receives only "here's a phone with the app on it." Never make
  it read rules/skill files — that defeats the freshness.
- Run it as a full-app audit at release cuts, and at reviewer discretion on any PR that
  adds a screen or changes navigation.
- Its findings inform (never a ruling by itself) — taste and scope calls still go to
  whoever owns product decisions.

## Design-reviewer pass (convention-aware design critic)

A control can be styled correctly, findable, and non-confusing, and still be wrong:
given more prominence or screen position than its job warrants. A design-critic agent
judging **rendered screenshots only** against platform conventions and the
category-leader bar (control placement/prominence, hierarchy) catches that gap — it is
not component styling (the design-system owner's turf), not this-user findability
(the persona's turf), not naive-user confusion (fresh-eyes' turf).

## Production-data guardrail

If the app talks to a real backend, always drive walkthroughs against a fixture/emulator
backend signed in as a seeded fixture user — never a signed-in write flow against the
real production backend.
