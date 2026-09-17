# Tenant Services Storybook

## Outcome

- Added Services as the third working tenant destination in the shared workspace navigation and
  deterministic Full journey.
- Added typed inventory metadata for Google, Zenmux, Deepgram, Telnyx and Twilio.
- Added create-only credential setup with provider-specific fields, local contract validation,
  duplicate protection and write-only secret handling.
- Kept credential binding metadata separate from read-only telephony service registration,
  provider connection and outbound-number metadata.

## Decisions

- The frontend mirrors the closed `ProviderAuth` shape for immediate feedback: printable ASCII API
  keys with provider byte limits, Twilio `AC` plus 32 hexadecimal digits, bounded auth tokens and
  the existing credential-name grammar. The eventual endpoint remains authoritative.
- Provider-side validation/readiness is not represented. Telephony metadata says Registered or Not
  registered based only on platform records.
- Attempt results carry a version so each success closes and resets secret state, including repeated
  successes. Conflicts keep the current form available for correction; closing and reopening starts
  a fresh attempt without the prior message.
- The modal makes background content inert, moves focus to Provider, contains Tab navigation,
  supports Escape and restores trigger focus.

## Red-green evidence

- Form tests were added before components and failed on missing modules.
- Provider field selection, validation, secret clearing, focus restoration, keyboard containment,
  duplicate no-overwrite, telephony metadata and complete-journey submission each failed before
  their corresponding implementation.
- Astra review found and drove fixes for a no-op Full journey action, duplicate enforcement, a
  fictional verification state, conflated service/credential names, repeated-success secret state,
  tenant state reuse, unavailable-state submission and responsive long identities.

## Verification

- Console: 75 tests pass; TypeScript and ESLint checks pass.
- React package: 30 tests pass.
- Production Storybook build passes with existing Vite client-directive and bundle-size warnings.
- Browser inspection covered dark/light desktop, 390 x 844 mobile, long service/credential identity,
  Google and Twilio field sets, successful repeat creation, duplicate conflict, keyboard focus and
  horizontal inventory scrolling without document overflow.
