---
name: stream
description: Run one GitHub issue as a work stream in a Docker container on this machine — a headless stream lead with the full harness inside, returning a PR and result.json. Use when the owner wants several streams at once, or for an issue the host lead should not hold in its own context. Subcommands via scripts/stream.sh — build, launch, status, collect, followup, stop, prune.
---
# Work stream

A stream is one wave in a container: one issue, one branch, one PR, one headless lead
that spawns its own builders and reviewer one level deep. The host lead (this session)
is its dispatcher. The only things that come back are the PR and
`<STREAM_RUNS_DIR>/<issue>-<slug>/result.json`; never read a stream's transcript.
Policy: `rules/operating-model.md` § Long-running and background work.

`S="bash ${CLAUDE_PLUGIN_ROOT}/scripts/stream.sh"`. Every subcommand reads the project's
`.claude/harness.env` (`STREAM_*` keys, `templates/harness.env.example`).

## 0. Once per project, then whenever a newer CLI or plugin should reach the streams

- Docker running; `$S build` (image `harness-stream:<project>`, latest Claude Code at
  build time; auto-update is off inside containers, so rebuild to move forward).
  `$S status` shows the image's CLI version beside the host's.
- The two 0600 env-files exist: `~/.config/claude-harness/containers.env` with
  `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`, printed once, one year) and
  `~/.config/<PROJECT_NAME>-harness/containers.env` with `GH_TOKEN` (a fine-grained PAT on
  this one repo: Contents, Pull requests, Issues read/write). `$S launch` refuses if
  either is missing, world-readable, or sets `ANTHROPIC_API_KEY`.
- `STREAM_RUNS_DIR` is in `.gitignore`.

## 1. Launch

1. One open issue with agreed scope. No open PR on `feat/<issue>-<slug>`.
2. Write `<STREAM_RUNS_DIR>/<issue>-<slug>/brief.md`: the task, the spec, the claim, a
   token ceiling, the issue number. Nothing the project's `CLAUDE.md` already says; the
   container runs the same rules. Say what the stream must NOT touch.
3. `$S launch --issue N --slug <slug> [--budget USD] [--max-turns N] [--model m]`. It
   prints the container, session id, token and run dir. Comment them on the issue in one
   line.
4. Two background tasks, both re-invoke you when they end:
   `$S collect <id> --wait` and
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wave-watchdog.sh <run dir>/stream.jsonl`.
5. Go on with other work. `$S status` any time.

## 2. On return

Read `result.json` only (`collect` prints it and exits by state):
- `0` **done**: PR open, token matches. `/harness:review-pr <pr_url>`; merge per
  § Worktrees and merges. Scorecard row from `result.json`'s `usage` and
  `total_cost_usd`, never from the summary's own numbers.
- `3` **needs_owner**: read `<run dir>/owner-questions.md`, get the answer (terminal, or
  `/harness:ask-owner` from here), then `$S followup <id> "Owner ruling: …"` and
  collect again. The container keeps the session; the answer lands in it.
- `4` **blocked**: the summary says what is outside the stream's scope. Decide: file it,
  or `followup` with the ruling.
- `1` **failed** / `2` **stopped**: read `errors` and the last lines of
  `<run dir>/stream.jsonl` and `stderr.log`. Resume with `followup` (same session) or
  fence it in durable state and `launch --relaunch`; never both.
- A watchdog STALE on a stream means `$S stop <id>` (SIGINT ends the run within seconds;
  the container keeps the session for a `followup`), never a second launch for the same
  issue.

## 3. Hygiene

- Never `docker rm` a container whose PR is open. `$S prune` at every checkpoint removes
  only containers whose PR is merged or closed; it lists the rest.
- `STREAM_MAX_CONCURRENT` is the cap; `launch` refuses above it. A stream counts as one
  or two gate-running agents on this machine.
- A stopped container (`docker stop`) cannot be resumed; `launch --relaunch` archives the
  run and starts fresh.
