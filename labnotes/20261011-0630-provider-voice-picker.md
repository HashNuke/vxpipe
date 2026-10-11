# Provider voice picker

## Scope and decisions

- User requested provider voice-catalog research, a common fetch/filter contract,
  readable voice labels and a Storybook modal for quick UI review.
- Reviewed existing pure `models/0`, Speech.Model voice descriptors, provider
  registry, Calls authorization/service bindings and Console capability fields.
  Existing source keeps voice under the model-declared option parameter; preserve
  that value contract and keep display metadata outside the call spec.
- Researched official Cartesia, ElevenLabs, Rime, Deepgram, Google and OpenAI docs.
  Cartesia and ElevenLabs have native paginated account catalogs and different
  query filters. Rime exposes complete per-model public metadata. Static/versioned
  inventories remain an option for supported named-voice models. Newer upstream
  model features do not imply support in the currently installed adapter.
- `docs/provider-voice-catalog.md` records source links, callback and HTTP proposals,
  authorization/binding boundaries, cache isolation, compatibility, error handling,
  pagination and rejected alternatives. No milestone directory is present.
- Implemented the shared TypeScript client boundary, generic modal/filter controls,
  readable inline field and fixture adapters. Fixtures stay injected through
  Storybook context; production keeps its existing field pending authenticated
  backend integration. This is a review prototype, not live voice discovery.
- No provider credentials were read or used. Audio audition is a documented follow-up;
  the prototype does not contain placeholder playback controls.

## Verification and iteration

- Red: voice-picker test failed to import the absent implementation. Green: four
  tests cover staged selection/cancel, ID-only writes, provider-defined filters,
  pagination reset, stale response rejection, saved unknown voices, retry, readonly.
- TypeScript, ESLint and all 551 frontend tests (71 files) passed. Storybook build
  succeeded with existing chunk-size notices. Focused picker/capability checks:
  10 tests passed after layout refinement.
- Chrome/agent-browser: dark desktop 1360/1440px, light mobile 390px. Checked Cartesia
  language filtering, choice application, ElevenLabs multi-language filtering,
  empty search, and the real call-spec page field changing from a UUID to Skylar.
  Mobile document width equals the 390px viewport. Captures in
  `vxpipe-voice-picker-*.png` and `vxpipe-voice-field-page.png`.
- Fixed modal height after browser review showed controls moving when result counts
  changed. Header/footer stay anchored; filter/results area scrolls on small screens.
- Keyboard review found Escape returned focus to body because the conditional
  dialog had no Radix trigger. Added a failing focus-restoration assertion and an
  explicit return-to-field callback. The test now passes and Chrome confirms Escape
  returns focus to `Voice: Skylar`. Final TypeScript, ESLint and focused tests pass.
  Confirmed name-only voices have no redundant ID or unsupported filter controls.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency checks
  passed. Root tests reproduced the known Ortex macOS NIF LINKEDIT failure; the
  engine suite reported 2068 tests / 6 failures. Calls then passed 142 tests; stopped
  the remaining umbrella run in Gateway after the confirmed native-load blocker.
  No umbrella-wide green result is claimed. Closed the verification browser and
  left the Storybook server listening on port 6006.

## Remaining production work

- Implement provider catalog modules, authenticated endpoints, query validation,
  complete-inventory filtering and account-scoped bounded caching.
- Verify model compatibility, provider filter values and account-specific lists
  with recorded adapter fixtures and an explicit live integration lane.
- Bind the production client to the authorized spec/draft and effective service
  binding, including source credential-name overrides; no credentials selector UI.
