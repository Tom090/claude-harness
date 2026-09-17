# Token efficiency

Token spend is a project goal. Whole-file reads and verbose test output were over 60% of
builder context on a prior project.

## Builders and reviewers

1. Quiet test output: pipe the test command through `tail -40` or a dot reporter;
   verbose only for the failing file. Prefer the scoped variant of any toolchain.
2. Grep first, then read with offset and limit. Never whole-file-read a large corpus,
   test or lock file. Never re-read a file you just edited.
3. Batch independent shell commands; pipe noisy ones through `tail`. Every tool round
   re-sends the whole context. An agent that runs the system pipes the output to a file
   and reads the summary, never the stream.
4. No doc-page fetching for API shapes the brief already gives; ask the lead instead.
5. Terse reports under the role's word limit; PR bodies stay substantive.
6. State your own metered token spend in one line at the end of every report. It is a
   cross-check; the figure of record is the one the parent reads from your task result.

## The lead

7. Small, well-scoped waves; batch related residuals; no one-PR-per-nit tail.
8. Set a token ceiling in the brief itself, before the child starts.
9. Per-role token figures come from the metered figure in each task result, never from a
   child's self-report and never by reconstruction. A fork's figure includes its inherited
   context; record it as such.
10. Briefs point at sections, not whole documents; they carry no rules the agent's own
    definition already gives it.
11. Reference fixtures and mechanism fixtures before any broad sweep; the sweep is not a
    per-PR gate.
