---
name: validate
description: Build, lint, and test the project before opening a PR.
---
# Validate

Read `.claude/harness.env` (written by `/harness:harness-init`) for `TEST_COMMAND` and
`LINT_COMMAND` and run them:

```bash
# shellcheck disable=SC1091
source .claude/harness.env 2>/dev/null
eval "$TEST_COMMAND"
[ -n "${LINT_COMMAND:-}" ] && eval "$LINT_COMMAND"
```

If `.claude/harness.env` doesn't exist yet, this project hasn't been bound — run
`/harness:harness-init` first, or fall back to whatever this stack's obvious test/lint
commands are (`./gradlew testDebugUnitTest lintDebug`, `npm test && npm run lint`,
`cargo test && cargo clippy`, `pytest && ruff check`, ...) and tell the user
`harness.env` is missing.

If the lint command supports auto-fix (`spotlessApply`, `eslint --fix`, `cargo fmt`,
`ruff check --fix`), apply it and re-run before reporting.

Report PASS/FAIL with the key errors, quietly (pipe verbose output through `tail -40` —
see `rules/token-efficiency.md`). Do not open a PR until this passes.
