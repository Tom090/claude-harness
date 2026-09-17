# Systems modeling and the design bar

<!-- Starter rules from the harness. Delete if the project has no mechanism-shaped
     problems (shared resources, equilibria, rates that scale with N). -->

## The design bar: a composition experiment before any mechanism is built

No mechanism is briefed to a builder until an executable experiment has run on the
project's reference fixtures (`{{FIXTURE_PATH}}`) and is written down:

1. the measured failure, per link, on the faithful fixture, not a hypothesis from code;
2. the smallest prototype of the proposed rule, run in a throwaway worktree;
3. a control: the same fixture without the change;
4. the supported domain: the fixture shapes and ranges the claim was measured over,
   with unmeasured combinations marked as predictions;
5. the visible signal the user gets and the recovery open to them;
6. a conservation trace where a quantity moves: it leaves one store, arrives, is consumed.

A prose rule with none of the above is a proposal, not a design.

## When a systems-modeler is required

- Proactive: multiple independent actors on one shared or regenerating resource, or a
  problem stated as rate-matching, equilibrium or "scales with N". The model (state,
  flows, invariant, convergence argument, probes reproduced) precedes the builder.
- Backstop: a reviewer's differential measurement shows a fix's premise false, not merely
  buggy. No further direct builder attempt until a model exists.
- A builder's "the model is refuted" is a measurement to reproduce on the model's own
  fixture before it halts anything.

## Rules of measurement

- No mechanism hypothesis in an issue body until the binding link is measured with the
  project's instrument.
- The modeler reproduces its own discriminating probe before handoff; an unrun
  prediction is not a spec.
- Fix the tightest link first; raising supply upstream of an unfixed cap fails on the cap.
- The modeler writes throwaway prototypes and probes; it never commits to the source tree.
