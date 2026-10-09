# Work streams in containers (harness 0.3.0)

## The problem

Since 0.2.0 the owner-facing lead session runs every builder and reviewer itself, one
level deep. That is reliable for one stream of work. It conflicts as soon as the owner
wants several streams at once: the lead's context is the merge point for everything, and
the alternative, a nested orchestrating agent, was retired because nested background
spawns died mid-turn (`docs/field-feedback/2026-08-31-baby-app.md` §1) and their leaf
agents notified the root session instead of the agent that briefed them
(`docs/field-feedback/2026-09-30-tray-product-leaf-agent-guard.md`).

## The shape

The lead becomes a dispatcher. Each work stream (one GitHub issue) runs in its own Docker
container on the owner's machine. Inside, a top-level headless Claude Code session is the
stream lead: it runs the unchanged harness (plugin, hooks, Stop gate, agents one level
deep, enforced by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`), opens the PR, and reports
back only through durable state: the PR plus `result.json` in a bind-mounted run dir.
The host lead never reads a container's transcript.

Both recorded failures were in-process nesting bugs. A container session is a top-level
session, so neither applies. What changes shape is communication: cross-session
messaging does not cross a container boundary, so there is no notification from a
finishing stream. The host learns results from files and git, which the 2026-08-31
feedback already named as the thing that worked best (durable-state-first recovery).

## Precedent

Anthropic's cloud sessions and Managed Agents use the same shape, hosted: one task, one
sandbox, one branch, one PR, a coordinator that delegates one level deep. Codex cloud,
the Copilot coding agent and Cursor background agents do the same. This is the
self-hosted version, built from Anthropic's reference devcontainer.

## Decisions

- Fresh clone inside the container over a repo-scoped token; never a bind mount of the
  host checkout, so the host's worktrees are untouched.
- Secrets outside the repo in two 0600 files; `ANTHROPIC_API_KEY` refused because it
  overrides the OAuth token in `-p` mode.
- `bypassPermissions` pinned explicitly, as a non-root user, behind a default-deny
  egress firewall; the container plus the firewall is the sandbox.
- SIGINT finishes the turn and writes the result; SIGTERM drops it. `stop` sends INT
  first. The container idles after a run so `followup` can resume the same session.
- Owner questions go to a file in the run dir and the stream ends with `needs_owner`;
  the host lead relays. One Telegram long-poll per bot rules out polling from inside.
- Token figures in `result.json` come from the result event, never from the model's
  own summary.
- A stream counts as one or two gate-running agents against the per-machine cap of four
  or five; `STREAM_MAX_CONCURRENT` defaults to 3.

## Known limits

- No in-process notification: `collect --wait` and the watchdog are background tasks
  that re-invoke the host lead.
- A `docker stop`ped container cannot be resumed; relaunch archives the run.
- Several stream leads on one subscription token share its rate limit; budget caps bound
  spend, not throttling.
- Browser-equipped roles (designer, UAT) stay host-side until the image carries a browser.
