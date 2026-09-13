# Docker packaging direction

## User direction and changes

- Docker is the primary packaging and README installation path. Components must
  also be presented as libraries usable within consumers' Elixir applications.
- Keep the GitHub repository at `HashNuke/vxpipe`. Use organization namespace
  `vxpipe` for the Docker image; assume `vxpipe/vxpipe` as the image repository.
  A registry publishing configuration and release tag are not yet selected by
  this documentation checkpoint.
- Update the README's product positioning and source clone instructions without
  inventing runnable Docker commands for an unimplemented image. Clearly label
  the current quick start as a source demo and link the component documentation.
- Record the final Docker-first README requirement in the delivery milestone's
  specification, checklist, and acceptance checks, along with the unchanged
  GitHub ownership and consuming-Elixir-host example. Update the milestone index
  description while retaining its unchecked state and existing order.
- Record a local specification review separately from implementation progress.
  This clarification does not begin container implementation or release the
  existing pre-delivery review hold. No publishing or repository transfer occurs.
- Preserve the source-development guide as the destination for source setup once
  the root README's Docker instructions become runnable.

## Verification

- All 81 relative links and heading anchors across the four changed documents
  resolve, and all ten shell snippets parse with `bash -n`. The initial link
  checker incorrectly rejected an existing directory link in the milestone index;
  accepting directory targets fixed the checker without changing that link.
- Compared the milestone index to HEAD: all 24 identities, their order, and their
  completion states are unchanged. Delivery remains not implemented, with no
  completed implementation boxes. The separate specification-review register
  now includes the distribution clarification.
- Checked that the README uses the exact source repository and planned image
  identities, explicitly mentions Elixir library use, and contains no speculative
  `docker run` command. `git diff --check` passes.
- Documentation only: no runtime behavior, dependency, or image-build changes;
  no new behavior tests or application suite run required.
