# Retire embedded docs

## Scope and decisions

Remove the embedded Astro site and its dedicated `bin/site-dev` launcher from
the umbrella. Retire `bin/setup --with-docs`, the associated dependency step,
site lockfile monitoring, generated-directory checks and advertised site URL.
Update setup and launcher tests and the current development documentation.

Keep the legacy `astro` slot in worktree port metadata so existing checkouts
remain readable without a metadata migration. Console and Storybook keep their
current ports and launchers. Application Tailscale support and formal Lean
verification remain unchanged.

## Implementation evidence

- The setup help regression failed while `--with-docs` was still advertised,
  then passed after removing the option.
- Removed site-only launcher assertions while retaining coverage of Console
  HTTP/Tailscale startup, argument validation, dotenv loading and port overrides.
- Setup tests retain optional Lean success/failure coverage and verify that
  setup no longer advertises Astro.
- Review found stale site-launcher instructions in the architecture guide and
  optional docs setup instructions in the isolation guide; both were removed.
- Historical milestone evidence remains intact, with a note identifying the
  retired setup option and launcher.

## Validation

- `python3 test/shell/setup_test.py`: 32 tests passed.
- `bash test/bin/launchers_test.sh`: passed.
- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed.
- `mix test`: the complete default umbrella suite passed, seed 484706.
- `mix deps.unlock --check-unused`: passed.
- `git diff --check`: passed.

No source-cutover or speech state machine changed, so the Lean lane was not
required. No live-provider tests were run.
