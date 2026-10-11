# Refresh product context

## Scope and decisions

- Ran the global Impeccable 4.5.2 `context` helper and read its init workflow.
  The helper requested a target because the Core and React workspaces inherit
  the root product and design records.
- The user chose to refresh the shared root `PRODUCT.md` and retain the existing
  audience, provider-neutral positioning, and Elixir/API consumption direction,
  updating facts supported by the repository.
- Preserve `DESIGN.md` and the existing `buildPath: comp` workflow preference.
  This is product documentation maintenance, not a UI or runtime change.
- Inspected the dirty worktree before editing. Existing application, Storybook,
  hook, lockfile, documentation, and labnotes changes belong to other work.

## Evidence and discrepancies

- The old product record describes only room creation and treats WebRTC/RTVI as
  future work. Current architecture and Console sample documentation describe
  working WebRTC/RTVI, text and speech turns, interruptions, and human transfers.
- Current Console routes and the call-spec authoring guide expose authenticated
  tenant administration, service configuration, call-spec revisions/publishing,
  and call inspection. Some older Console README paragraphs still describe
  superseded authentication paths; prefer current routes for those claims.
- `README.md` and `LICENSE` establish Apache-2.0. The README explicitly labels
  Docker distribution as coming soon; preserve it as a consumption direction
  without claiming an available release.
- Core and React are private npm workspaces. Storybook uses synthetic fixtures;
  prototype evidence is not provider interoperability or publication evidence.
- `docs/milestones/index.md` and `docs/getting-started-docker.md` are absent in
  this checkout despite existing references. Do not infer completion from missing
  milestone checklists or add those broken paths to the refreshed evidence list.

## Verification

- `bin/setup` passed: dependency preparation, frontend build, and development
  and test database migrations completed. The existing local environment was
  preserved. No live provider credentials were read or live tests run.
- Refreshed `PRODUCT.md` with the user-confirmed direction, current operator
  workflows, runtime capabilities, terminology, license, and explicit release
  limitations. Kept hosting, pricing, comparative performance, and formal
  compatibility/accessibility commitments open.
- Reviewed the final product diff against the inspected sources. Verified the
  schema marker, bare `web` platform value, and all 16 slash-containing path
  references. `git diff --check -- PRODUCT.md` passed.
- Rechecked worktree status: this task adds only the product-record edit and
  these labnotes to the previously observed changes. No design or workflow
  configuration was edited, and no commit was created.
- Live-mode configuration was not useful for the selected shared product scope:
  the root covers multiple packages and Console, with no single selected page
  or injection target. App-specific live setup belongs to a later scoped live
  session. The existing comp-first setting remains recorded.
- Documentation-only verification is proportionate here. No runtime/UI source
  changed, so no new tests, umbrella test run, or browser verification was needed.

## Commit follow-up

- The user requested a commit limited to the Impeccable documentation changes.
  Stage only `PRODUCT.md` and this labnotes file; preserve unrelated work.
- The user reported that Storybook had stopped after the refresh. On inspection,
  port 6006 had a Node listener and the root URL returned HTTP 200, so no restart
  was performed. Setup refreshed frontend dependencies, but the cause of the
  reported interruption was not established.
