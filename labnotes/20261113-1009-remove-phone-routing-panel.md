# Unify the Telnyx connection editor

## Findings

- The production integration route still enabled the old Phone routing panel
  specifically for `/telephony`, despite the new connection modal. This was
  missed in the preceding UI checkpoint and remained visible after deployment.
- Edit Telnyx first fetched the generic service directory in one loading dialog,
  then mounted a second loading dialog for the Telnyx connection endpoint, then
  mounted the final editor. Their titles, anchoring, and sizing differed.
- The final form was shared with the approved inherited-credentials story, but
  its 680px width and some field/button styling depended on a Storybook wrapper.
  Production fell back to the generic 480px dialog width.

## Changes

- Remove the old routing panel, its form, unused styles, and tests exclusively
  exercising that removed UI. Keep the application response parser used by the
  connection modal. The underlying backend routing and records are unchanged.
- Telnyx now loads directly from its connection endpoint. Keep one shared dialog
  frame and header mounted through loading, failure, application selection, and
  editing. The form initializes only after its settings arrive.
- Own the responsive width, reserved height, header, field, and primary button
  styling in the shared Telnyx stylesheet. Loading and loaded states keep the
  same bounds. Longer content scrolls within the dialog.
- Preserve credential inheritance, overrides, application settings, test/save
  actions, cancellation, and focus restoration. Credential testing does not need
  an unrelated directory response.
- Keep scope below the Telnyx title; remove the redundant source subtitle under
  Credentials. Both saved keys use masked dots plus Saved. Missing public keys
  remain marked Not configured.
- Use the requested hint: "Configure this URL in Telnyx for the Voice API Application".

## Evidence

- Red: the existing production-route permission test, extended to `/telephony`,
  failed on the leftover Phone routing heading. Two delayed-load tests failed
  because Telnyx fetched the generic directory and lacked its final header.
- Green: 49 focused tests across integration browsing, scoped services, the
  Telnyx host and form, shared permissions, and the setup stories. A final focus
  adjustment passed the 17 affected host/story tests again. No full suite run.
- TypeScript, changed-file ESLint, formatting, compilation with warnings as
  errors, strict Credo, unused dependency checks, and diff whitespace pass.
- Headless Chrome with agent-browser verified the Telephony route at 1440x900
  and 390x844, with the old panel absent and the existing editor available.
- Delayed connection loading retained the identical dialog/header DOM nodes and
  rectangles at desktop and mobile sizes. Desktop measured 680x720 at (380,64);
  mobile measured 366x720 at (12,12). Both saved-key indicators were present.
- The specified inherited-credentials story and the production component preview
  measured identical desktop dialog bounds. The form and interaction logic are
  shared. Preview responses are synthetic; no environment files were read.
- A preview hot reload interrupted one mobile inspection; reopening after source
  updates settled completed the same check successfully.
