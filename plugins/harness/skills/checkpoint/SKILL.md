---
name: checkpoint
description: Pause and distill the lead session's state into durable sources (decisions.md, GitHub issues, session notes), then print a short "where we are / what's next" plan. Run at wave boundaries or whenever the session is getting heavy.
---
# Checkpoint

Durable state lives in GitHub issues/PRs + `docs/decisions.md` + `CLAUDE.md` — never in
chat history. This skill is the write-side of that contract: after it runs, this session
is safely disposable and a fresh session (or `/harness:project-status`) can reconstruct
everything that matters.

Do the following, writing only what is NOT already durable — skip any step with nothing new:

1. **Rulings → `docs/decisions.md`.** Any decision made this session (priorities, design
   calls, process changes) that isn't yet in the log: add an entry, newest-first, with
   the why. Rulings that exist only in chat are the #1 loss on reset.
2. **Open threads → GitHub issues.** Anything discussed-but-not-queued becomes an issue
   (or a comment on the existing one). Batch small related residuals per
   `${CLAUDE_PLUGIN_ROOT}/rules/operating-model.md`. Unfinished in-flight work: comment
   current state on its issue/PR so the next session starts from facts, not archaeology.
3. **Merged-PR hygiene.** If PRs merged this session and their sessions are retired,
   distill lessons into `.claude/agent-sessions.md` (a few lines each, per its own
   header rules).
4. **Commit durable-file changes** (`docs/decisions.md`, `.claude/agent-sessions.md`) —
   docs-only commits follow the normal PR flow; batch them with other pending meta
   changes when sensible.
5. **Print the checkpoint summary** (this is chat output, not a file):
   - Done this session (PRs/issues, one line each)
   - In flight (what + exactly where it stands)
   - Next up (the plan, in priority order, with issue numbers)
   - Session health: rough context state; recommend continuing vs seeding a fresh
     session with this checkpoint if the session is heavy.

Keep it tight — a checkpoint that takes 10 minutes won't get run. Most checkpoints
should be 2–5 tool calls plus the summary.
