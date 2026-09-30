# Phone harness isolation

## Observation and decision

- The full umbrella run with seed 412687 returned HTTP 401 in the Twilio
  maximum-duration scenario, before the media socket opened. Its shared fixture
  used the same tenant, service, ingress, account and call identities as other
  scenarios, despite using different synthetic signing credentials.
- Webhook selection intentionally prefers a retained leg owner over the active
  service repository. Shared identities therefore allow one fixture's retained
  owner to be selected by another fixture. This is a plausible explanation for
  the full-run failure; the original collision has not been reproduced directly.
- Give each scenario a unique, valid 16-character tenant key and use it for the
  ingress identity. The provider account remains a synthetic fixture constant.
  Runtime authentication and retained-owner selection are unchanged.

## Verification

- Red: a focused factory contract test confirmed that two independently built
  scenarios shared their ingress and service identities.
- The first implementation appended an ID to the old tenant key and failed all
  27 focused tests because provider credentials require exactly 16 characters.
  Encoding the existing scenario ID in base 36 with a fixed prefix and padding
  satisfies that contract without introducing a separate identity generator.
- Green: scenario identity, Twilio harness and Telnyx harness tests passed:
  27 tests, zero failures, seed 412687.
- Full umbrella verification remains pending. A focused pass does not establish
  that the earlier full-run failure is resolved.
