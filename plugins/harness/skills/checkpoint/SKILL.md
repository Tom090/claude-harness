---
name: checkpoint
description: Pause and distill the lead session's state into durable sources (decisions.md, GitHub issues, session notes), then print a short "where we are / what's next" plan. Run at wave boundaries or whenever the session is getting heavy.
---
# Checkpoint

Durable state is GitHub issues and PRs, `docs/decisions.md` and `CLAUDE.md`, never chat.
Write only what is not already durable; skip any step with nothing new.

1. **Rulings → `docs/decisions.md`.** Every owner ruling verbatim; every lead ruling
   labelled; the why in a line. Newest first.
2. **Parking list → the same entry.** Owner observations and threads discussed but not
   agreed are listed there as parked, one line each, with the lead's assessment. They
   are not filed as issues; an issue is filed only for scope the owner has agreed.
3. **In-flight work.** A comment on its issue or PR stating exactly where it stands.
4. **Merged-PR hygiene.** Retired sessions' lessons into `.claude/agent-sessions.md`, a
   few lines each; per-role token figures from the children's own reports into the
   decisions entry.
5. **Commit** the durable files.
6. **Print the summary**: done this session; in flight; parked (awaiting the owner);
   next up in priority order; session health and whether to seed a fresh session.

Two to five tool calls plus the summary.
