# Opening audio editor and voice-picker research

## Request and scope

Fix configured-provider filtering and disabled Publish in the QA editor. Audit
all existing provider voice-list/search code and the reviewed voice-picker
stories, then document the missing production work as a milestone.

## Findings and changes

- `createEditorApi.catalog` ignored the backend's `credential_available` flag
  and fetched model lists for unavailable providers. Filter before model requests,
  excluding missing availability metadata as well. The backend still owns tenant
  and platform permissions. Credential-free local Morse remains available under
  its existing backend contract.
- Publish was gated on an unchanged saved revision both in the header and reducer.
  It now saves a valid changed/new draft and publishes the exact returned revision.
  Subsequent edits stay dirty, double clicks do not duplicate requests, failed or
  malformed saves cannot advance, and unmount/reload cancels pending work.
  Save as draft still saves without publishing; invalid/read-only/forbidden or
  unapplied JSON states remain blocked.
- Opening audio omitted `credential_name`, so backend parsing used `default` even
  when the saved connection was named after its provider. On selection use an
  available canonical binding, then an explicit default or sole named binding;
  preserve already explicit names. No silent arbitrary choice among ambiguous
  noncanonical names. The authoritative save still validates availability.
- Voice discovery is not implemented in production. `models/0` mostly provides
  default/free-text descriptors; the shared TypeScript client contract and rich
  modal are implemented with Storybook fixtures. The Morse origin probe's voice
  request is test code, not an application discovery client.
- Added `docs/design/provider-voice-picker.md` and the corresponding milestone,
  with a provider reuse matrix, official API references, credential-scoped
  discovery, supported wire-format constraints and bounded on-demand loading.
  No DB cache/job subsystem or new modal is necessary. The milestone stays
  unchecked; local specification review is separate from implementation.

## Verification

- Red: four focused frontend files produced 12 expected failures for unavailable
  provider filtering, dirty/new Publish and missing opening-audio credentials.
- Green: seven focused files, **100 tests pass**: editor API/header/reducer/hook,
  opening-audio inspector, editor page and production route. Includes new-spec
  save/publish across URL replacement with no reload, exact snapshot publication,
  malformed/failed saves, duplicate clicks and cancellation.
- TypeScript check and ESLint for the six changed implementation files pass.
- Root format check, warnings-as-errors compilation, strict Credo and unused-lock
  check pass. No full test suite, live telephony, provider synthesis or paid calls.
- Headless Chrome inspected the existing Cartesia modal at desktop and 390px
  mobile width, and the editor opening-audio flow at 1440px/390px. Enabling blank
  opening audio disables Publish; completing text/provider makes it usable;
  one Publish click saves/publishes revision 4 in the fixture transport. The mobile
  header retains a readable Publish action and published revision badge.
- Browser inspection used an environment-free Storybook mirror because port 6006
  was unavailable. It exercises the real changed components with fixture catalogs
  and transport, not the new backend catalog (which is still planned). Screenshots
  are local scratch evidence and are not committed.
- Changed-document relative links and milestone index count pass: 63 entries,
  49 complete and 14 incomplete. Diff whitespace check passes.

## Limits and handoff

- Official docs establish API candidates, not authenticated interoperability.
  ElevenLabs Realtime voice-set compatibility, Flux metadata coverage and the
  installed Google TTS voice set have explicit implementation research gates.
- No environment files were read. No user call spec was changed or published.
- Unrelated concurrent production speech configuration/test/labnote edits in QA
  were left untouched and excluded from this commit. This checkpoint does not
  deploy the running application or claim production voice-picker completion.
