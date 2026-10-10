# README onboarding guides

## Direction and scope

- The user clarified that the README needs a marketing introduction, a quickstart,
  and direct links to Docker and Elixir getting-started guides. Component READMEs
  and architecture/development references are not substitutes for those entrypoints.
- Keep a compact product introduction and replace the miscellaneous document list
  with exactly the two onboarding links. Preserve the user's existing License
  section unchanged.
- The user's follow-up explicitly makes the README quickstart Docker-based and
  very concise. Replace the initial source quickstart with a three-line Docker
  command preview and one Console link. Keep source commands in the Elixir guide.
  Mark the Docker command as a preview in one line: container packaging remains
  unimplemented, and no runnable/released-image verification is claimed.
- Add `labnotes/milestones/container-quickstart-plan.md` and `docs/getting-started-elixir.md`, keeping
  `vxpipe/vxpipe` as the planned Docker image and `HashNuke/vxpipe` as the source.
  Docker remains the primary planned package. The Docker guide explains the
  proposed mounted-config/environment-file inputs and identifies the schema,
  entrypoint, image tag, and media networking as pending release verification.
  The preview follows the approved mounted JSON/explicit `--config` direction;
  it does not establish implemented runtime defaults or release a milestone hold.
- The Elixir guide provides the already-verified source demo, prerequisites, next
  steps, and library entrypoints. Child manifests still use umbrella dependencies;
  an independent consuming-host installation is a delivery acceptance gate, so
  no unverified Hex/git dependency recipe is claimed.
- Point the deeper development guide at the two onboarding guides. No runtime,
  configuration, dependencies, or milestone completion changes are needed.

## Verification

- All 18 relative links and heading anchors resolve; all 11 shell snippets across
  the README and three guides parse with `bash -n`.
- The README is 25 lines before the License section, with a three-line Docker
  quickstart and exactly two getting-started document links. Its License section
  is byte-for-byte identical to HEAD, preserving the user's addition.
- Source-demo commands retain the launch already checked during the README
  quick-start checkpoint. No new application/browser/provider test is claimed
  for this documentation reorganization. The Docker command has only been
  syntax-checked and is explicitly a proposed interface, not a working image.
- `git diff --check` passed. No old source-quickstart anchor references remain
  in the current README or documentation. No milestone state was changed.
