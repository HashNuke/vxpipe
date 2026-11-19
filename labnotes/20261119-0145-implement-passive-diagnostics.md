# Implement passive diagnostics

## Checkpoint A — readable conversation

- Ran `bin/setup` successfully. Planning milestone/design committed and pushed as
  `6777cda4`; implementation follows its six checkpoints.
- Red evidence: React test showed usage observations visible by default; presenter
  test showed all canonical kinds missing; decoder test showed kind lost at JSON
  boundary. Added canonical `event_kind`/`eventKind` without inferring from labels.
- Shared admin/debug React UI has Technical events off by default; all seven kinds
  remain archived and available on demand. Unknown/legacy kinds remain visible;
  Usage accounting and protocol Logs are unchanged.
- Added 100-item rendered pages after filtering. This bounds DOM rows, not the
  unchanged full-history API response. The loader already loads full history,
  so technical-only server cursor pages do not occur on this surface.
- Additional red/green test caught equal-timestamp ID sorting; carry canonical
  details-store order through the derived view instead.
- Astra xhigh review used `gpt-6-astra` as explicitly requested. Reviewer reproduced
  two live-pagination failures (already connected and ready→connected, message 101
  missing). Retained regression tests in conversationPagination.test.tsx; follow
  newest page unless the user explicitly browses older history. Re-review returned
  no remaining checkpoint A findings; focused review suite 12 passing tests.
- Verification so far: presenter 16/16; core/react full suite 50/50; Console assets
  full suite 1163/1163; workspace build/typecheck and Console typecheck pass.
  Root format, warning-free compilation and strict Credo pass. First umbrella test
  process exited 143 before summary; not counted as a pass. Persistent tmux rerun
  is tracked separately until a terminal result exists.
- Rendered headless Chrome with agent-browser against real Storybook components:
  Workbench technical fixture and admin ended-call fixture, desktop and 390x844.
  Confirmed default-hidden versus opt-in records, mobile filter menu, readable
  rows, no desktop overflow, filter keyboard operation and page controls. Chrome
  required `--no-sandbox` on this host. Screenshots are temporary evidence only.
- Sent concise progress through pushnotify at start and during review/fix cycle.
- No runtime deployment yet; checkpoint B onward remain unimplemented.

## Resumption handles

- Umbrella verification runs in tmux session `vxdiag-checks` (shell writes terminal
  results to `/tmp/vxpipe-A-test-final.exit` and `/tmp/vxpipe-A-unlock.exit`). Inspect
  those and the matching logs; do not restart a still-running suite. First run
  `/tmp/vxpipe-A-test.log` was interrupted and is not acceptance evidence.
- Browser fixture server runs in tmux `vxdiag-browser` on assigned Storybook port.
- Checkpoint A review agent `review_checkpoint_a` returned no remaining issues.
  Implementation remains uncommitted until root gates finish; planning commit
  `6777cda4` already pushed to origin/qa. After gates pass, finalize milestone/labnote,
  stage exact A paths, inspect cached diff, commit and push, then start checkpoint B.
- Final affected Console frontend run passes 22 tests and typecheck. Latest shared
  UI run passes 50 tests including all reviewer reproductions. No runtime code has
  changed since root verification started; later changes are frontend/docs only.
