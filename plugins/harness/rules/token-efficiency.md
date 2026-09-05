# Token efficiency — binding rules for all agent sessions

Token spend is a project goal in its own right — measured on a prior project's
multi-agent build: whole-file reads and verbose test output were >60% of builder
context.

## For builders and reviewers

1. **Quiet test output.** Pipe the project's `TEST_COMMAND` (from `.claude/harness.env`)
   through `tail -40`, or use a quiet reporter (`--reporter=dot`, `-q`). Verbose output
   only for the failing file, on failure. If the toolchain has a fast/scoped variant
   (a single debug build variant, a single test project), always prefer it over running
   every variant/target for zero extra signal.
2. **Grep-first, scoped reads.** Locate with Grep, then Read with offset/limit. Never
   whole-file-read a large corpus/test/lock file. Never re-read a file you just edited.
3. **Batch independent shell commands**; pipe noisy ones (package installs) through
   `tail`. Every tool round re-sends the whole context — round count is a cost
   multiplier.
4. **No doc-page WebFetching for API shapes the lead already knows.** The lead
   pre-digests API references into the brief — ask the lead if something is missing
   rather than re-fetching docs a delegate already has.
5. **Terse reports** (the agent definitions set word limits); PR bodies and PR comments
   stay substantive — they are the durable archive.

## For the lead / wave-lead

6. **Small issue scope per session** — but batch small RELATED residuals into one
   issue/branch/PR/review round; the anti-pattern is both the bundled mega-issue AND the
   one-PR-per-nit tail.
7. **Fix cycles (review-and-fix)**: the reviewer fixes its own mechanical findings on
   the PR branch, test-first — no separate fix session and no extra verification round
   (the failing-then-passing test/corpus row IS the verification). Spawn a fresh fix
   session ONLY for design-level rework the reviewer routes back; seed it with the
   reviewer's PR comment, never a huge builder transcript. (Measured on a prior
   project's worst case: 3 fix sessions + 3 verification rounds for findings the
   reviewer could have patched in-session, roughly 10x the token cost of doing it
   in-session.)
8. **Reviews are scoped**: adversarial probing concentrates on changed mechanisms, a
   single consolidated findings round; not a re-derivation of settled work. Full
   adversarial depth (own corpus, differential vs the default branch) is for NEW rule
   families/mechanisms; residual cleanups gate on the permanent test suite.

## For judgment-tier and play-testing roles

9. **Screenshot budget.** A screenshot is the most expensive token unit an agent
   spends — far more than an equivalent amount of text, and it doesn't compress the
   way prose does. Judgment-tier verdicts (Fable-tier or equivalent — see
   `${CLAUDE_PLUGIN_ROOT}/rules/operating-model.md` § Design-led wave shape) are capped
   at **≤12 screenshots** per play verdict, one map/level. Execution-tier play sessions
   (an Opus-tier play-tester or equivalent) are bounded by whatever screenshot/session
   budget the wave brief sets — never open-ended, even though their cap is typically
   looser than a judgment-tier verdict's.
10. **Headless before browser.** A screenshot is never the first instrument for a
    mechanics question. If a project has a headless systems-verification harness (see
    `${CLAUDE_PLUGIN_ROOT}/rules/operating-model.md` § Headless systems verification),
    run it before opening a browser at all — a multi-system integration question
    (does food reach every house, is a progression tier reachable, does a threat system
    still bite) is answered in seconds headlessly and only obscured by a bounded,
    single-path browser session. Reach for the browser only for what the harness
    structurally can't see: pixels, legibility, input feel.
