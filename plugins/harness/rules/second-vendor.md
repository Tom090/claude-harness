# Second-vendor seat

A second vendor's CLI reads every PR and, when routed, builds. Facts learned in the
field; each cost a session at least once.

- It reads `AGENTS.md`, not `CLAUDE.md`. `AGENTS.md` stays thin: it points at `CLAUDE.md`
  and `.claude/rules/`, inlines the build, test and lint commands and the two or three
  load-bearing conventions, and asks for a list of the rule files actually read.
- Run `codex exec` with stdin closed (`< /dev/null`); it otherwise waits on stdin.
- Its read-only copy has no dependencies installed: it cannot run tests and must say so.
- As a builder in a workspace-write worktree it cannot commit; the worktree's git index
  is outside its sandbox. The lead commits, pushes and opens the PR, naming the vendor as
  builder in the body.
- A "model at capacity" cut-off resumes cleanly; resume rather than respawn.
- Model: the Opus-equivalent tier by default; the top tier only for owner-invoked
  escalations. Its builds cost about four times a fast-model pass for the same change;
  route on the scorecard, not on the tier.
- The seat earns its place on docs PRs too: it has found tests an auditor's own grep of
  the same file missed.
