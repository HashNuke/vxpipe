# Morse-code API milestone planning

Date: 2026-10-14. Scope: research/design and milestone documentation only.

## Request and decisions

- The user requested an independent Go Morse TTS/STT service in the sibling
  `morsecode-audio` project, Railway hosting at `morse-audio.definerun.com`,
  arbitrary compatibility keys, no persistence and Vxpipe MorseCodeApiTTS/MorseCodeApiSTT.
- Clarification explicitly selected complete TTS/STT API compatibility, excluding
  unrelated ElevenLabs products. No application implementation or deployment was
  requested in this first task.
- Added the [milestone](milestones/remote-morse-code-audio.md) before delivery and
  the [design document](../docs/remote-morse-code-audio.md). All implementation
  boxes remain unchecked; the index grows from 47 to 48 specifications.

## Inspection and research

- Initial git status was clean. Read repository instructions, milestone index,
  prerequisite milestone contracts, provider packaging and speech ownership docs.
- Inspected actual local Morse codec defaults, manifest registry, ElevenLabs
  HTTP/WS construction, runtime dispatch and Console provider catalogs.
- Existing endpoint struct fields do not imply supported constructor injection;
  public validators reject additional options. A named remote provider needs
  configuration, model/service catalog and runtime changes, not only a URL swap.
- Official ElevenLabs pages establish HTTP/timed streaming, both TTS WS modes,
  realtime/batch STT and single-use token interfaces. The design links sources.
  Initial guessed WS paths and Markdown fetches failed; linked canonical HTML
  reference pages worked. No live ElevenLabs requests or credentials were used.
- `bin/setup` succeeded: dependencies, frontend assets and dev/test migrations.
  It preserved the existing local environment; tracked setup files did not change.
  The protected live-provider environment file was not read or modified.

## Separate specification review

Local review checked missing contracts and dependency order, independently of the
implementation checklist (no implementation progress is claimed):

- Full TTS scope includes MP3 defaults, timing variants and multi-context WS;
  an initial PCM round trip cannot satisfy the final compatibility claim.
- Browser authentication requires tokens/first-message variants. Proposed bounded
  in-memory one-time tokens imply a one-replica baseline and restart invalidation.
- No retention conflicts with transcript lookup, historical request stitching and
  durable asynchronous jobs. These remain explicit compatibility decisions for
  owner acceptance, rather than silent scope reductions or permission to add storage.
- Morse tones require specific onset/commit tests; human VAD and Scribe inferred
  endpoint timing cannot be inherited without evidence.
- Provider manifests belong in Providers; concrete sessions remain in CallEngine.
  Tenant/platform credential handling and Console/editor integration are included.
- Checkpoint F needs HTTP streaming, G needs realtime STT and F; full parity waits
  for all WS/format/auth work. Hosted acceptance follows local conformance/load.
- Independent signal fixtures and bidirectional Go/Elixir checks avoid a codec
  proving only its own mistakes. Performance targets are proposed, not measured.

## Validation

The first index-count check found that the pre-existing summary understated the
completed entries by one. Recounted the ordered checklist and corrected the
summary to 48 total, 36 complete and 12 incomplete after adding this milestone;
no existing completion checkbox changed.

Final validation passed: 30 local document links, all 48 ordered milestone links,
consecutive index numbering, nine unchecked implementation checkpoints, new-file
trailing-whitespace checks and `git diff --check`. Runtime tests and browser checks are not applicable to this
documentation-only checkpoint; they remain explicit implementation gates. No
sibling project was created and no commit, deployment or application behavior
change was made.

## Naming correction

The user renamed the capabilities to `MorseCodeApiTTS` and `MorseCodeApiSTT`.
Updated the proposed shared provider to `morse_code_api`, its namespace to
`Vxpipe.Providers.MorseCodeApi`, its runtime setting to
`MORSE_CODE_API_BASE_URL` and its live-test tag to `live_morse_code_api`.
Milestone and document filenames retain their stable identities. This is a
documentation-only correction; implementation checkboxes remain unchanged.

## Local endpoint and Railway handoff clarification

The user requested temporary configurable endpoints for development against the
local Go server, then a switch to the app they will deploy on Railway. Updated
the milestone and design to use a development-local default, explicit production
origin, a single HTTP/WS derivation contract and restart-based cutover without
changing credentials or saved call specs. No implicit fallback to the future
hosted domain is allowed.

Expanded A/F/G with listener configuration, endpoint validation, all-operation
routing and two-origin/TLS acceptance. Expanded I with independent Docker build,
Railway config, environment example, deployment runbook, health/readiness,
nondefault PORT tests, explicit WS shutdown and read-only-container evidence.
The user deploys; preparation can finish locally while hosted acceptance remains
pending. Reviewed dependency order separately: deployment preparation may begin
after A; final hosted acceptance follows H and the user's deployment.

Consulted official Railway networking, healthcheck and config-as-code references.
Some Dockerfile/teardown reference fetches returned unavailable content; exact
schema and platform timeout verification remain implementation tasks. No Go app,
runtime configuration or deployment was changed by this documentation revision.

Revision validation passed: 175 relative links across the changed planning/design
documents and index, whitespace checks, nine unchanged unchecked checkpoints,
and checks removing the old hosted-default/agent-provisioning wording.
`git diff --check` passed. Runtime/container tests remain implementation tasks.

### Configuration handoff review

Made the milestone's environment ownership explicit with a local/hosted settings
table: Go reads `HOST`/`PORT`; Vxpipe reads `MORSE_CODE_API_BASE_URL` and owns its
compatibility credential. The runbook must validate readiness and authenticated
discovery before speech enablement. This documentation clarification leaves
existing implementation progress and staged work intact; it does not deploy or
change runtime configuration.
