# Testing: four kinds, and what each may assert

<!-- Starter rules from the harness. Fill the placeholders; delete what does not apply. -->

1. **Rule tests** (`{{RULE_TEST_PATTERN}}`, colocated): given a fixture, the mechanism does
   what the design says. Exact values are fine when the value is the rule. The title
   names the rule; a reader can trace it to a design doc or a constant.
2. **Invariant tests with tolerance**: a floor or ceiling over a fixture set, with the
   derivation in the test's doc comment. A floor with no derivation is a golden in
   disguise and moves to kind 3. If the denominator or the mechanism changes shape, the
   floor is re-derived, never re-pinned.
3. **Golden tests** (`{{GOLDEN_TEST_PATTERN}}` only): exact readings of seeded runs.
   Change detectors, not specs. A PR that moves one regenerates it and states the cause
   per value in the PR body. A golden that moves with no cause anyone can state is a bug
   found. Nothing outside a golden file pins a seeded-run reading.
4. **Fixture tests** (`{{FIXTURE_PATH}}`): real inputs replayed. The assertion is the
   outcome the input had. A divergence on replay means the system now refuses something
   it accepted; the expectation is updated with the cause. These are the per-PR gate.

- Every new mechanism ships with rule tests and, where it has a system-scale effect, a
  derived invariant. A floor read off today's run is not a derivation.
- Every chance-based subsystem draws from its own seeded stream; a test that asserts
  cross-subsystem draw ordering is retired.
- Red rule test: the mechanism or the rule is wrong; fix one and say which. Red
  invariant: re-read the derivation; if it holds, fix the change, else stop and report.
  Red golden: state the cause, regenerate; if you cannot, stop. Diverged fixture: state
  what is now refused and why that is right.
- "Measured, therefore pinned" is refused in review.
- The test command stays under {{TEST_TIME_BUDGET}}. A broad sweep is not a gate; it
  runs, if at all, once at wave end on the merged default branch, never beside other
  runs.
- A comment can be load-bearing for a test that scans the file as text; a comment-only
  edit still runs the tests.
