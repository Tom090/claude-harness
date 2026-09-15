---
name: validate
description: Build, lint, and test the project before opening a PR.
---
# Validate

Read `.claude/harness.env` for `TEST_COMMAND` and `LINT_COMMAND` and run them. Run
`LINT_COMMAND` only if `TEST_COMMAND` does not already contain it.

```bash
# shellcheck disable=SC1091
source .claude/harness.env 2>/dev/null
eval "$TEST_COMMAND" 2>&1 | tail -40
case "$TEST_COMMAND" in *"$LINT_COMMAND"*) ;; *) [ -n "${LINT_COMMAND:-}" ] && eval "$LINT_COMMAND" 2>&1 | tail -20 ;; esac
```

If `harness.env` is missing, run the stack's obvious test and lint commands and say the
file is missing. If lint supports auto-fix, apply it and re-run. Report PASS or FAIL with
the key errors only. Do not open a PR until this passes.
