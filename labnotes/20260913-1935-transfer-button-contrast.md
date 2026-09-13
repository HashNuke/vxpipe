# Transfer button contrast

- Accepting changes the desk action to Disconnect. The quiet variant uses paper
  text, and the shared hover rule also uses a paper background. Chrome reproduced
  identical foreground/background colors after acceptance, explaining the apparently
  empty white button and the persistent touch hover state.
- Set the hover foreground to the existing ink token. Preserve the action, layout,
  palette, disabled state, and explicit transfer acceptance.
- Rendered Chrome inspection at 1440x1000 and 390x844 confirms readable Disconnect
  text against the hover background. The mobile check followed a real provider-backed
  transfer through Main room active and had no horizontal overflow.
- Verification: TypeScript and existing asset checks, plus the umbrella completion
  checks recorded in the human-transfer-failure labnote. No CSS unit tests added.
