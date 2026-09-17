# Specializing the builder roster

`generic-builder.md` is a fill-in-the-blanks skeleton, not a ready-to-use agent.
`/harness:harness-init` generates one or more concrete agents from it per project — the
plugin does not ship builder agents itself, because builder responsibilities are 100%
project-specific (there's no portable version of "implements Android UI" or "implements
Cloud Functions").

How to specialize, per detected/declared stack:

- **One builder per natural ownership boundary**, not one per file type. A small repo
  often needs exactly one `builder.md`; a repo with a clear frontend/backend split
  benefits from two (e.g. `frontend-dev.md`, `backend-dev.md`) so each can be briefed
  with a narrower `OWNED_PATHS` and a tighter tool/model footprint.
- Fill `{{OWNED_PATHS}}` with the actual directory the builder should touch — this is
  what keeps parallel builders from stepping on each other in the same wave.
- Fill `{{ADDITIONAL_RESPONSIBILITIES}}` with the ONE OR TWO things this project cares
  about most for this builder not to violate (a design-system rule, a secrets boundary,
  a data-migration convention) — resist listing everything; put the rest in
  `.claude/rules/`.
- If the project has a design-system / shared-component owner role, give it its own
  agent file rather than folding it into a generic builder — other builders should
  consume it, never restyle inline (mirrors the source project's design-system role).
- Keep every builder on the same model tier (see the harness plugin's
  `rules/operating-model.md` § Sessions and models) — a different tier for one builder is
  a routing decision made on the project's scorecard, not a default.
