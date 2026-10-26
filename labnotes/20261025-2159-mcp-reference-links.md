# MCP reference links

## Scope and decisions

- Add independently optional `setup_notes`, `setup_url`, and `documentation_url`
  to the public integration definitions, hosted API response, and Storybook MCP
  connection/manage forms. Notes render above the Setup and Documentation links.
- Missing metadata produces no empty card or link. Notes stay plain text, and
  links use HTTPS. Native provider documentation remains required.
- HubSpot's existing guidance is setup notes; its documentation link is labeled
  Documentation. The illustrative Example knowledge entry demonstrates both links.
- Callback URLs were already read-only. Give copy fields a muted text, surface,
  and border treatment while retaining selection and the working Copy control.

## Compatibility and implementation

- The definitions schema now uses plural `setup_notes`; new definitions reject
  the old singular key. The API importer normalizes legacy `setup_note` to the new
  field, and its response mapper can also read old immutable snapshots.
- The API stores the full definition JSON in SQLite. These additive metadata
  fields need no SQL migration, and old stored notes remain readable.
- Prepare the API reader before publishing definitions with the new fields.
  This checkpoint only changes local repositories; no deployment was performed.
- Shared Storybook setup information is rendered for both connect and manage
  flows, without exposing directory-owned authentication parameters.

## Test evidence

- Tests were written before implementation. The public schema failed the optional
  combinations/new field cases; the API failed the metadata round-trip cases;
  frontend tests failed 10 cases while one passed.
- Public definitions: four tests pass, including all eight optional combinations,
  invalid values, plural naming, and the provider documentation requirement.
  The validator accepts all three current definitions and the template.
- API: focused tests and the complete race-enabled suite pass. `go vet ./...`
  and the server build pass. Coverage includes SQLite publish/read, omitted keys,
  and legacy stored notes being emitted under the new key.
- Frontend: TypeScript and all 86 MCP Storybook tests pass. API response examples
  validate against the updated JSON Schema.
- An initial static-build invocation used an incorrect relative config directory;
  reran from the umbrella root, which is required by the Storybook configuration.
- Final full frontend, build, and rendered checks are recorded below.

## Final verification

- All 912 frontend tests in 119 files pass, TypeScript passes, and the static
  Storybook build succeeds. Existing chunk-size and jsdom scrollTo notices remain.
- Headless Chrome at 1440px and 390px, dark and light themes: HubSpot notes appear
  above Documentation; the Example knowledge fixture shows Setup and Documentation
  together below notes. Custom MCPs without metadata have no empty note container.
- The callback input is readOnly=true and disabled=false, with the muted text
  and soft surface tokens. Copy produces the Copied confirmation. Clipboard read
  permission was unavailable to the browser automation, so direct clipboard read
  was not used as evidence. Editable credential fields keep their normal surface.
- Manage remains 580px tall with consistent Disconnect/Close actions. The mobile
  Authentication body scrolls to expose the callback and Reconnect controls while
  the footer stays visible. Desktop has no horizontal overflow.
- Offscreen mobile Manage clicks required explicitly scrolling the directory
  before clicking in agent-browser. Once visible, the modal opened normally.
- All three repository diffs pass whitespace checks. Storybook responds on 6006.
  The umbrella gates passed earlier in this checkpoint; no Elixir code changed
  after those checks. No commits or deployment were made.
