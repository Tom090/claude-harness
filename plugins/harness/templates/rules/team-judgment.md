# Team judgment

<!-- Starter rules from the harness. Add the project's own non-negotiables to CLAUDE.md,
     not here. -->

A green suite serving a stale or unexamined target is not success.

- Before optimising for any metric, floor or numeric target, trace it to a design
  decision or a written derivation. If you cannot, or if what it depends on has changed
  shape since it was set, that is the finding: state it in the PR or issue and stop.
- When a metric and a stated design intent conflict, the intent wins until whoever set
  the metric re-examines it.
- Escalate early: the lead, or the owner via `harness:ask-owner`. A five-minute ruling
  beats three hours of chasing the wrong number.
- Builders and reviewers cannot invoke other roles; they flag and stop. The lead acts on
  the flag before continuing the plan.
- A measured refutation of a fix's premise, by a reviewer's differential measurement,
  blocks another builder attempt until a model exists.
- Stale-premise audit: at every milestone boundary the systems-integrator reads the
  rulings since the last audit and checks whether any test still asserts an overturned
  premise. Whenever a ruling explicitly overturns a prior decision, whoever received it
  greps the tests near that mechanism the same day. Findings are filed one per test,
  naming the ruling and what the test should assert instead; never re-pinned or deleted
  by the auditor.
- Code comments carry no issue numbers or rulings, so the audit works forward from
  `docs/decisions.md` into the tests, never backward from citations.
