# Teammate CLI script

## Checkpoint

- Added `bin/teammate` as a non-interactive wrapper around `opencode run`.
- The default model is `opencode-go/muse-spark-1.3-contributor#high`.
- Task input is accepted as positional arguments or from standard input.
- `--model MODEL` and `--model=MODEL` override the default.
- Documented the `vxpag` tmux session convention in `AGENTS.md`.
- Documented the required subagent review and same-session teammate fix loop.

## Verification

- Red test: `test/bin/teammate_test.sh` initially failed because `bin/teammate`
  did not exist.
- Green test: `./test/bin/teammate_test.sh` passed using a fake `opencode`
  executable to verify delegated arguments and model selection.
- The exact model identifier was previously verified with the installed
  OpenCode CLI in tmux and completed a non-interactive request successfully.
- Updated the default identifier to include the `#high` variant after the
  focused test caught the previous medium-effort default.
