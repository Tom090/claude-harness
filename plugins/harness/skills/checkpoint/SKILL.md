---
name: checkpoint
description: Pause and distill the lead session's state into durable sources (decisions.md, GitHub issues, session notes), then print a short "where we are / what's next" plan. Run at the end of every wave; a lead session is one wave, so the checkpoint is also the session's close.
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
   few lines each; per-role token figures into the decisions entry, taken from the
   metered figure in each task result, never from a child's self-report.
5. **Worktrees.** `git worktree list` against `gh pr list`: name every worktree with no
   open PR and offer to prune it. Never remove one whose PR is still open.
6. **Commit** the durable files and push them, so no launched branch carries them.
7. **Print the summary**:
   - What the owner can use now: the command to run it, and what changed since they
     last looked.
   - Asked of the owner, unanswered: numbered, so the next session opens on them.
   - Done this session; in flight; parked; next up in priority order.
   - The session ends here. The next wave starts in a fresh session.

Two to five tool calls plus the summary.
