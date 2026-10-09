# Changelog

Newest first. A project pinned to an older version reads here what changed before it
bumps; the harness itself keeps no decisions log, so the why of each release lives in
the entry and in `docs/design/`.

## 0.3.0 — 2026-10-09 — work streams in containers

- **New: `scripts/stream.sh` and `/harness:stream`.** One Docker container per GitHub
  issue runs a headless stream lead (`claude -p`) with the full harness plugin inside;
  the host lead launches it and reads back only the PR and `result.json` in a
  bind-mounted run dir. Subcommands: build, launch, status, collect, followup, stop,
  prune. Secrets live in two 0600 env-files outside the repo (`CLAUDE_CODE_OAUTH_TOKEN`
  from `claude setup-token`, a repo-scoped `GH_TOKEN`); `ANTHROPIC_API_KEY` is refused.
- New image template `templates/docker/Dockerfile.stream` (non-root, pinned CLI, egress
  firewall to GitHub, Anthropic and npm, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`), the
  result contract `templates/stream-result.schema.json`, and the stream lead's preamble.
- `rules/operating-model.md`: a lead session is one wave, a stream is one wave in a
  container; within any session agents are one level deep; a stream counts toward the
  per-machine gate cap; a removed container is a lost agent; the watchdog, token and
  side-channel rules extended to streams.
- `harness.env.example`: `STREAM_*` keys; the header now says the file is read
  literally, which is what the hooks always did.
- `verify-gates` §6 exercises the stream mechanism; `checkpoint` lists streams and
  offers prune; `harness-init` asks about streams and explains the two env-files.
- Design note: `docs/design/2026-10-09-work-streams-in-containers.md`.
- Adopting project: add the `STREAM_*` keys, create the env-files, `stream.sh build`,
  then run `/harness:verify-gates` §6 once before the first real stream.

## 0.2.1 — 2026-09-30

- Retired the project-level sync-leaf-agent guard; the one-deep spawning rule is stated
  in `rules/operating-model.md` instead of enforced by a hook.

## 0.2.0 — 2026-09-17

- The lead runs the wave itself; the nested orchestration role was retired. One wave
  per lead session; rules-only `CLAUDE.md` template; scoped per-turn Stop gate; model
  scorecard; optional second-vendor seat; comment linter template.
