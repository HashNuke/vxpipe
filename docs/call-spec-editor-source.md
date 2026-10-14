# Call spec editor source model

## Decision

The framework-free editor modules under Console assets hold the portable source
itself. Parsing preserves optional fields, explicit nulls, provider options and
legacy concrete model IDs. Serialization sends only this source; the graph and
inspector state are separate projections. Historical schema `20260915.01` opens
read-only and cannot be edited by changing the document's read-only flag.

API-authored `speech_to_text.vad` is preserved through source round-trips and
provider/model changes. It accepts only a boolean on human input STT. Omission
means false; the editor adds no VAD control or implicit source field.

Participant edits clone the source and update structural references together:
direction, transfers, audio/transcript route keys and recipients, and visibility
overrides. Variable section and field renames update grants, required fields and
phone-number references. Literal prompts and descriptions are never searched or
rewritten. Removing a referenced variable leaves an empty required selection so
validation asks the operator to choose a replacement. It never substitutes a
fixed phone number or changes a transfer destination silently.

New specs require an explicit incoming/outgoing choice before the editor opens.
Outgoing creation requires a configured phone service and seeds a dial callee
handled by an agent; incoming creation seeds a web caller. Direction has no switch
in Call settings, and applying full JSON cannot change the chosen direction.
The shared Calls save workflow compares later revisions with revision one's
direction, including legacy incoming specs, before persisting. This applies to
Console, API and trusted host writes. A direction change requires a new spec;
existing history remains intact. Each direction's omitted first-message behavior
remains owned by the backend. Capability overrides can be removed to
inherit defaults, and omitted wait slots remain distinct from explicit silence.

The new-spec seed uses the selected direction and a text-capable agent. It uses
Google's catalog recommendation when installed, or
the first available language-model provider in deterministic order. The model ID
always comes from the catalog. Voice capabilities are explicit additions. Public
speech options and voice parameter names also come from adapter descriptors;
Deepgram STT declares its required encoding/sample rate, and Flux TTS retains a
separate voice. Existing source is never reseeded when opened.

## Validation and presentation

Client validation accumulates independent problems using backend JSON paths and
UTF-8 byte limits. It validates structural source rules, references, direction,
phone numbers, tools, variables, media and visibility policies. Runtime-specific
provider options, credential availability, telephony routing and compilation
remain authoritative backend checks; the client does not duplicate adapters.

A shared fixture in `examples/contracts/call-spec-editor-validation.json` is
executed by Call Engine and Console tests. Each invalid case specifies the
backend's first error path; the accumulating client must include that path.
Boundary cases must pass both. This is a drift check for the listed cases, not a
claim that the TypeScript validator implements every backend compiler decision.

Error presentation maps paths to a canvas node or Call settings, inspector tab,
field and operator label. Unknown paths retain the backend reason in the issues
list. Save/publish feedback distinguishes validation, missing services, conflict,
permission, expired session and retryable failures. These pure functions return
presentation data; the UI owns focus, badges, toast replacement and dismissal.

## Inspector edits

Call settings composes standard form controls over the source-edit functions.
Model controls show Provider and Model side by side, followed by a catalog-driven
Voice field when relevant. Recommendations select defaults without decorating names.
Credential selectors and generic option forms are omitted. Existing credential names,
model options and provider options are preserved until explicitly replaced.
Advanced `options` and `provider_options` are edited in the full call-spec or
participant JSON editor, retaining explicit empty objects, nulls and nested values.
Changing provider replaces the whole selection with that provider's recommendation;
changing model preserves the provider's credential name and provider_options while
resetting model options to the descriptor's defaults.

Variable rows belong to named sections. Their name and type use inline fields;
Enum and Required use one checkbox row. Enum entries are typed tags with no
per-value type selector. Nested fields and array items share these controls.
Constraint and nullable controls are absent, while existing source keywords are
preserved. Invalid hidden constraints retain focused error guidance to the JSON
editor. The backend makes variable values nullable by default; see
[variable nullability](variable-nullability.md) for the source contract and migration
implications. A section permission matrix includes obsolete
grants so the operator can clear a reference to a missing section; it cannot grant
new access to a missing section. Section and top-level field renames still use the
source functions that rewrite permissions and dial references atomically.

Section schemas must have an object root without `enum`. Both client validation
and the Engine's `CallSpec` validation reject section-level enumeration at
`call_variables.sections.<name>.schema.enum`. Field schemas, including nested
object fields and array items, still support enumeration. Existing section enums
are not silently dropped: remove them in the full JSON editor before saving or
compiling the spec. The section modal has no Allowed values control.

Entry and human inspectors edit the same participant records. Changing connection
service applies the selected role's admission rules and removes phone-only fields
when switching to web. An outgoing callee uses a fixed number or the outgoing
request's `to`; transfer destinations also support a declared string variable.
Saved connections are not normalized on load. Opening text has an explicit TTS
selection, independent of participant defaults. Clearing an optional private
briefing removes the field; opening a saved null leaves it unchanged. Description
fields are omitted from participant forms. Existing description values remain in
the source and are editable through JSON.
Participant capability panels show the call default and any explicit override.
The human inspector's transfer timeout edits the one call-wide transfer policy.

The Agent inspector displays the effective first-message mode without a redundant
Default option. Opening a source preserves omission; selecting the direction's
default removes an override. Transfer-history defaults also stay implicit.
Changing either mode replaces its dependent fields in one edit. Its
transfer picker and canvas share the eligibility rule, and existing invalid
references remain removable. Tool editing preserves per-tool visibility across a
key rename, rejects reserved keys and collisions, and keeps host keys equal to
their registered tool names. MCP integration names come from lookups; tool names
are entered explicitly and resolved by the backend. The tool dialog holds its
draft locally until Add or Save, so Cancel does not change the source.

### Agent model types

The Models tab separates Speech-to-Speech from LLM plus Text-to-Speech. Human
inspectors expose only Speech-to-Text. Opening existing selections never normalizes
the source, including text-only agents and saved output-recognition selections.
Only the active model type's controls appear; a type change removes incompatible
agent overrides and seeds missing selections from catalog recommendations in
provider-name order. A type is unavailable when a required selection has neither
a saved/default selection nor a catalog recommendation. A required provider can
revert to a call default only when one exists.

Capability inheritance is per capability, and the portable source has no value
that disables one inherited capability for one participant. When a type change
conflicts with call defaults, the editor copies those defaults to other agents
that inherit them, preserving their explicit overrides, then removes the
conflicting defaults. This is one source edit and leaves human speech recognition
unchanged. Keeping incompatible defaults would make the selected type fail backend
compilation; changing backend inheritance or adding a new schema flag was rejected
for this UI change. The tradeoff is that those other agents now hold explicit
selections for the removed defaults.

Call settings also exposes one AI model type at a time. It derives the selected
type from the default capabilities without rewriting source on load. An explicit
call-wide type change removes incompatible defaults and agent overrides in one
edit, then fills missing defaults using catalog recommendations. Compatible
overrides and human participants stay untouched. Switching to LLM also removes
output speech recognition, which belongs to the speech-to-speech path. Preserving
conflicting overrides would leave agents inheriting both model paths under the
existing source contract. Required AI providers cannot be cleared to an absent default, and a
type with no saved selection or catalog recommendation is unavailable.

## Issue presentation boundary

Client validation and the last field-related server error remain separate. The
header counts client issues; node and tab badges use the merged, deduplicated
field issues. Backend failures persist across unrelated edits and unsuccessful
retries, and clear when their source value changes or a save succeeds. Late
responses are compared with the submitted source before attaching a field error.
Network, conflict, session and authoring-permission outcomes never become field
issues. Secret-material errors use client-owned text rather than the server reason.

Rendered inspectors register source paths in an issue scope. The scope assigns an
error to its exact control, nearest represented collection, or visible-tab summary.
A dialog takes precedence over an underlying card with the same path. Show requests
carry an identifier so normal edits do not steal focus; tool dialogs and collapsed
constraints reveal their controls before focus moves. Global DOM selectors alone
were rejected because hidden tabs, portals and duplicate paths make them ambiguous.

The JSON editors serialize the current portable source without normalization. The
full editor replaces the entire source; the participant editor replaces only the
selected participant and validates its fields and newly introduced cross-reference
errors. Existing unrelated issues do not block a participant edit. Both preserve
large integers using the existing lossless parser. They reject syntax errors,
unsupported fields and schema-version changes before updating the draft. Historical
sources remain read-only, including at the source-edit boundary.

JSON drafts are staged explicitly with Apply and Discard. Page-owned draft storage
retains incomplete input across inspector unmounts and contributes to departure
protection. Save and publish wait for pending JSON edits. Review returns to the
pending editor, including drafts for participants removed by a different edit.
An original-source snapshot prevents stale JSON from overwriting newer changes.
Copy and download export the visible full JSON text, including unapplied input.
Generic key/type/value option forms were removed because they obscured routine model
selection; JSON is the deliberate escape hatch for advanced configuration.

Existing Console
toasts provide action feedback with an optional standard Button; their success
expiry and persistent failure behavior are reused. The full editor connects these
components to request handling, selection and recovery. Show selects the source's
node and tab and opens the phone inspector; unmapped issues stay in the drawer.

## Draft and request lifecycle

The editor reducer keeps the current portable source and the last successfully
saved source separately. A request captures its submitted source. Save success
advances the saved baseline and revision metadata to that snapshot, preserving
any edits made while the request was pending. Replacing the current document on
success was rejected because it would silently discard those later edits. Publish
targets a saved, unchanged revision; success marks that revision as published even
if the operator starts the next draft while publication is pending.

An injected transport runs outside the pure reducer, allowing the same lifecycle
to drive the Storybook prototype before production wiring. Client errors prevent
requests, concurrent clicks cannot start duplicate writes, and failed requests
retain both source and baseline. Retry submits the current draft. Explicit reload
aborts pending work and preserves a monotonically increasing request ID so late
responses cannot attach to the replacement document. Unmount aborts requests and
suppresses late session-expiry notifications. The editor confirms Back, Open
services and Reload when changes would be lost, and installs a browser-unload
guard. The host supplies navigation and reload transport; production router
blocking remains part of W. No expected-revision parameter is invented: the existing Calls
save workflow allocates and appends immutable revisions.

Incomplete success metadata produces retryable feedback without claiming a save.
The transport adapter will still validate response shapes at the production API
boundary. The inspector dispatcher selects the settings, Entry, Agent and Human
panels. Clicking a transfer edge opens the source participant's Transfers tab;
destinations are managed there, with editing disabled for read-only revisions.
The locked Entry edge opens Entry's Connection tab. Selecting an edge or adding
a participant also opens the corresponding inspector sheet on phones.
Rename and tool failures retain their local field drafts and replace the editor's
notification. Failed reload keeps the current document; recovery actions are
disabled during a write or reload so an old notification cannot start concurrent
recovery. Invalid-request defects log only the action name and a fixed message.

The full-page stories use injected outcomes through the real editor lifecycle,
rather than pre-rendering an outcome in disconnected components. Loading and
spec/catalog failures use page states with Retry; they do not create action toasts.
The full editor and stories have passed their build and rendered verification;
the prototype is ready for the milestone's user review.

## Alternatives and implications

A mutable graph compiled into JSON was rejected because it could lose fields and
change source digests on a no-op save. Persisted layout metadata and automatic
legacy migrations were rejected for the same reason. Frontend provider/model
inventories and hard-coded wire formats were rejected because they could drift
from installed adapters.

No React, transport, persistence or live-provider operations belong in the pure
source modules. They can be tested without rendering. Browser verification belongs to the later
inspector and production integration checkpoints. The backend still validates
every save and publish; client acceptance never grants authoring authority.

## Verification

Focused red runs preceded source parsing, graph projection, participant and
variable edits, validation, error placement, seed and public option defaults.
The shared backend fixture covers required fields, byte/range boundaries,
references, direction, tools, variables and policies. Separate tests cover all
example round-trips, legacy read-only behavior, immutable edits, public model and
voice separation, and every save/publish outcome in the milestone. Execution
counts and full-suite evidence are recorded in the implementation labnote.

The full editor prototype now composes these boundaries in 34 page stories.
The frontend lane passes 491 tests, TypeScript and lint; the Storybook production
build and all five root gates pass (3,448 tests, zero failures, seed 991936).
Rendered checks cover all page stories at desktop and phone widths, recovery
confirmations, field navigation, clipboard feedback and downloaded JSON.
The user explicitly deferred UI review on 2026-10-08 and authorized production
endpoint/router integration and the remaining acceptance work.

## Console authoring boundary

Console's installation-operator endpoints reuse Calls authoring and persistence.
Reads resolve the latest immutable revision or an explicit revision, and return
source plus the latest and currently published revision numbers. Appending to a
spec first checks that the ID exists in the requested tenant; shared principal-aware
authoring enforces the same rule for Gateway and CLI writes. Creation assigns a
database primary key internally (serialized as a decimal string) and request bodies cannot assign or rename identity. A foreign or missing
ID returns 404. Publishing addresses an explicit saved revision. See [call-spec identity](call-spec-identity.md) for allocation and migration details.

Editor lookups contain effective credential names, tenant telephony application
names and configured MCP integration names. MCP names come from the configured
integration source filtered to application and matching tenant scopes, without
remote discovery. Credentials, URLs, headers and connection IDs are not returned.
The existing operator session, CSRF and private/no-store pipeline protects these
routes. Request logging filters the entire source body so prompts and source
values do not enter request logs. Existing structured authoring errors are shared
with the tenant API; unexpected failures return a fixed unavailable response.

## Production request and navigation ownership

The editor API client encodes tenant/spec paths, sends exact source bodies with
CSRF and same-origin credentials, disables caching, validates response shapes and
passes abort signals to every request. Catalog choices come from the existing
provider/model listing endpoints. The route container cancels superseded loads,
keeps failed initial loads in a retryable page state, and never turns a failed
write into navigation away from the draft.

The React Router data router owns browser-history blocking. The editor still
owns confirmation for its own Back/reload/recovery controls; confirmed departures
bypass the router guard once. First-save URL replacement preserves the mounted
editor and edits made while the request was pending. Explicit revision URLs are
read-only and link to the latest editable source. A second frontend repository,
new expected-revision protocol and automatic historical-source migration were
rejected; existing immutable append/publication contracts remain authoritative.

Production acceptance passes 503 frontend tests, TypeScript, lint, the production
asset build and all five root gates (3,458 tests, zero failures, 120 excluded;
seed 991936). Desktop/phone browser checks cover authoring, failures, history and
responsive refitting. All three examples preserve source digests through tenant
API creation and editor saves. A published editor route starts a local call with
a synthetic credential and no provider generation request. No live tests ran.

## Exact source integers

The editor parses source JSON with [lossless-json](https://github.com/josdejong/lossless-json), retaining integer tokens beyond
JavaScript's safe integer range as native `bigint` values. Safe integers and
floating-point tokens retain ordinary number behavior. Source serialization emits
big integers as unquoted JSON numbers; the backend contract is unchanged. The
codec is shared by API reads/writes, source export, dirty-state comparison and
backend-issue retention. Structured numeric controls parse their input text through
the same integer conversion, and schema validation accepts arbitrary-size integer
bounds while retaining non-negative checks on length/item constraints.

Native `Response.json()` was rejected for source reads because precision is
already lost before a later serializer can recover it. Converting large integers
to strings would change enum and option types. Making valid documents read-only
would avoid corruption but unnecessarily remove authoring support. A dedicated
JSON parser avoids relying on newly introduced browser reviver/raw-JSON APIs or
maintaining a project-owned JSON tokenizer. Native bigint also survives the
editor's structured clones without custom object reconstruction.

The original API round-trip regression now preserves `9007199254740993` exactly.
Focused tests cover negative and larger integers, adjacent enum values, numeric
bounds, numeric-looking strings, revision state, unrelated edits and source export.
The Large Integers page story exercises the same inspector and editor lifecycle.
