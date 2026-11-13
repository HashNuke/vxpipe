# Telnyx connection preview

## Scope and decision

- Updated the existing Console / Services / Tenant services Storybook flow and
  its shared provider dialog. The MCP integrations / Connect Telnyx story now
  reuses that flow as well.
- Each tenant edits one Voice API application ID. Platform credentials can be
  inherited, or the tenant can supply its own credentials. The webhook follows
  the credential scope; changing credentials preserves the tenant application ID.
- Application-only saves do not require replacing saved credentials. Preview
  hosts retain application IDs by tenant, and Cancel discards unsaved edits.
- Platform configuration shows credentials and its webhook, with guidance that
  application IDs are configured by each tenant. There is no platform application
  field, additional tab, custom service name, or caller-number field in this flow.
- Added direct inherited, missing-application, tenant-credentials, light and mobile
  stories. Existing connect, connected and platform stories use the shared dialog.
- All persistence is fixture state. Backend routing, live integrations UI,
  call-spec caller-ID support and deployment are outside this preview checkpoint.

## Verification and adjustments

- Red: two focused tests failed because the application field was absent.
- Red: application-only edits with saved tenant credentials could not save.
  Added an application editor with an explicit Update credentials action.
- Green: 26 tests across ScopedServicesStory and McpServicesStory; three focused
  Telnyx cases from OnboardingStory. Existing connection tests now enter the new
  application ID and explicitly open credential editing.
- Root and Console TypeScript checks, changed-file ESLint, Mix format,
  warnings-as-errors compilation, strict Credo and unused-dependency checks passed.
  No full test suite was run.
- Inspected the incumbent UI before editing and the resulting desktop, mobile
  and light views in agent-browser. Verified required-field feedback, save/reopen,
  Cancel, inherited-to-tenant credential switching, application-only saves and
  returning to platform credentials. No horizontal page overflow at 390px.
- Adjusted the application form footer margin after the first browser pass to
  keep its buttons clear of the scroll boundary.
- Storybook ran from a source copy without environment files. Its temporary
  configuration uses a synthetic HTTPS origin, an empty Vite environment directory
  and the existing dependency installations. The initial copy needed the shared
  wait-sound assets to satisfy the story import graph. No environment files were
  read, and no live provider requests were sent.

## Review

Under Vxpipe / Console / Services / Tenant services, start with
**Telnyx Inherited Credentials**, then **Telnyx Application Required** and
**Telnyx Tenant Credentials**. **Telnyx Credentials** covers a new connection;
Platform services / **Platform Telnyx** covers shared credentials.
