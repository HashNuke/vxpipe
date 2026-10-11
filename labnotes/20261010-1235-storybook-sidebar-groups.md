# Storybook sidebar groups

## Findings and scope

- User requested two sibling groups: `@vxpipe/react` and `Console`.
- The existing titles mixed `@vxpipe/react`, `vxpipe_console`, and `Vxpipe/Console`.
  Storybook sanitizes both `vxpipe_console` and `Vxpipe/Console` to `vxpipe-console`,
  colliding a root with a nested group and leaving Console pages outside their folder.
- Call spec editor was a Console sibling of Services, not a child of Services.
  The inconsistent hierarchy made this relationship difficult to see.
- Before the change, the rendered sidebar did not contain the `@vxpipe/react` label.

## Changes

- Standardized titles on `Vxpipe/React` and `Vxpipe/Console`, with an explicit review order.
- Used Storybook's manager label renderer to display the literal package name; a slash
  in a title is always interpreted as a hierarchy separator.
- These title changes preserve their sanitized story IDs and existing links.
- Updated the Console frontend README with the sidebar convention.
- This is a metadata/configuration cleanup; no component behavior changed. Verification
  uses the generated story index and rendered sidebar rather than adding tests for
  Storybook's own hierarchy implementation.

## Verification

- `bin/setup` completed. Because the previous server occupied port 6006 when setup
  first allocated checkout ports, it selected 6007. Restored this checkout's Storybook
  reservation to 6006 in both local metadata and the shared registry under their locks,
  after checking availability and other checkout reservations. The restarted server and
  future `npm run storybook` launches now use 6006. No new worktree was created.
- `npm run build-storybook` passed. Compared its index with the original live index:
  all 203 story IDs are unchanged, with exactly `Vxpipe/React` and `Vxpipe/Console` groups.
- Chrome verification passed at 1440×1000 and 390×844: the package label reads
  `@vxpipe/react`, all Console pages are inside Console, and Services and Call spec
  editor have equal indentation. The Workbench preview renders; browser error checks
  were empty. Confirmed the updated manager loads on port 6006 with HTTP 200.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix credo --strict` passed.
- `mix test` passed the MCP, providers, and agent-runtime applications, then encountered
  repeated speech inference failures because the local Ortex native library fails macOS
  loading with `mis-aligned LINKEDIT string pool`. Stopped the run after confirming this
  dependency blocker and repeated downstream timeouts; the full suite is not green and
  was not completed. No backend source changed in this task.
- `mix deps.unlock --check-unused` passed separately.
- Existing root lockfile changes and the untracked documentation site predate this task.
