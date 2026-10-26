# Service directory categories and story coverage

## Scope and decisions

- User requested AI models first/default, then Telephony, a separator, Calendar,
  CRM and Office suite. Custom MCP is a prominent action opposite the page title;
  mobile uses a category dropdown and full-width custom action.
- User identified the existing Choose services story as still using the legacy
  provider dropdown. Shared the story-only directory/MCP workflow across tenant
  setup, platform setup, navigation, legacy inventory and Morse credential stories.
- Platform directories expose AI and telephony only; MCP connections stay tenant
  scoped. Retained inventory loading/errors, credential pending/errors, inherited
  AI/telephony credentials, overrides, webhook scope and read-only behavior.
- User rejected descriptions and tenant/preview disclaimers in AI credentials.
  Removed these, retaining capability tags, inputs and actions. AI directory rows
  also use names and capabilities without taglines.
- Live production pages, backend and service catalog data are unchanged. Existing
  user work remains uncommitted; no commit was requested for this checkpoint.

## Implementation and checks

- Category/CTA red run: 2 failures against the previous directory, then 13 passing.
- Story coverage red run: 5 expected failures (old modal/dropdown flow). After
  extraction/adapters, 50 focused story, onboarding and scope tests passed.
- TypeScript passed. First complete frontend run: 834 passed and one failure from
  a nested main landmark; fixed the shared preview's embedded rendering.
- Browser: checked the original Choose services directory and Google credentials
  at 1440 and 390 px, plus the simplified dedicated Google modal. Existing
  desktop/mobile directory category evidence is retained in local review captures.
- Static Storybook build passed before the final landmark/layout corrections;
  final verification results will be appended below.

## Final verification

- Added a focused red test for duplicate creation from the legacy inventory
  directory: the old adapter dismissed the error. The corrected adapter keeps
  the dialog open with the conflict message; editing updates the existing row.
- Final frontend: 107 files / 836 tests passed; TypeScript and ESLint passed.
- Final static Storybook build passed. No production entry imports the prototype.
- Root completion gates all passed: format check, warnings-as-errors compilation,
  strict Credo, the default umbrella test suite and unused-dependency check.
  Expected test logging included simulated failures; suite summaries had zero
  failures. No Lean lane was needed because no speech/state-machine code changed.
- Final rendered pass covered tenant credentials/error at desktop/mobile, platform
  directory (AI/telephony only), legacy inventory save failure, Morse credentials,
  read-only inventory and mobile category/custom-MCP navigation. Capability tags
  wrap, fields/actions stay within the viewport, and the old provider dropdown is
  absent from these Storybook dialogs.
- No new design suppressions were added. Unrelated historical font findings and
  pre-existing project context drift were left unchanged.
