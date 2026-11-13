# Shared Telnyx applications and tenant overrides

Status: complete and verified on 2026-11-13. [The index](index.md) owns order.

## Outcome and requirements

Configure Telnyx once at platform level. A tenant can override only its Voice API
application, or supply its own credentials together with a tenant application.
Incoming calls on the shared application route by called number to the tenant
and its published call spec.

- Reuse encrypted credentials, tenant service bindings and published number routes.
  Add one platform application default; a missing tenant application ID inherits
  it. Keep explicit overrides dedicated and retain their existing uniqueness
  constraint. Sharing uses inheritance, not copies of the platform ID.
- Each modal section has Override / Use platform default in its heading. Override
  reveals fields. Editing tenant credentials clears the application ID and requires
  it to be entered again. Resetting credentials keeps the application override;
  inheriting the application requires platform credentials. Save persists changes
  together; Cancel writes nothing. Keep existing permissions and secret masking.
- Verify signatures and require exactly one matching published route. Tenant URLs
  stay within their tenant. Unknown or ambiguous numbers must not start calls.
  Repeated events must not create another call; later events keep their original
  call identity. Outgoing calls use the same effective settings as incoming calls.
- Migrate existing data where necessary. Keep service names and call-spec
  references intact. Do not add legacy fallback paths or an adoption workflow.
- Keep the webhook under Voice application and retain the reviewed concise copy.
  Saving in Vxpipe does not update remote Telnyx settings.

### Approved webhook rule

Both settings inherited → platform URL. Overriding the application alone, or
credentials together with an application, → tenant URL. Tenant credentials must
have an explicit application ID; do not silently reuse the platform application.

The platform endpoint also accepts tenant applications when the user has not
updated Telnyx's webhook. Use the event's application ID to locate a dedicated
binding, or application + called number for the shared application; verify with
that binding's effective public key before admitting the call. Tenant endpoints
remain restricted to their tenant. This is the current endpoint contract, not a
separate legacy fallback mode. See the [design note](../../docs/design/shared-telnyx-applications.md).

## Implementation tasks

Start behavior changes with focused failing tests and extend existing operations.

### A — Persist defaults and overrides

- [x] Finish the platform application setting, nullable tenant override and
  effective-setting resolver. Verify migration with existing bindings, independent
  inheritance/reset, the required application with tenant credentials, missing
  defaults and invalid credentials.
- [x] Add the modal's read/save flow to existing Console/Calls configuration
  operations. Save both changed sections in one transaction, authorize each, and
  return effective values/source with credentials masked.
- [x] Verify save/reload, application-only edits, credential/application edits, resets, denied
  writes and rollback when either section is invalid.

Exit: the backend persists and resolves exactly what the modal edits.

### B — Route shared-application calls

- [x] Resolve new incoming calls by effective application ID + called number over
  published routes. Extend existing conflict checks to prevent duplicate numbers
  on the shared application, including conflicts introduced by changing settings.
  Reject ambiguity at ingress too; reuse publication/admission transactions.
- [x] Apply the approved webhook rule to signature verification, the displayed URL
  and outgoing callbacks. A tenant application must work with inherited platform
  credentials; the platform endpoint must also accept a correctly signed tenant
  application. Reuse the existing public-origin helper.
- [x] Extend existing duplicate-event/leg lookup only where sharing requires it.
  Test two tenants/two numbers/one application, bad signatures, wrong tenant URLs,
  unknown/ambiguous numbers, repeated delivery after number reassignment, and
  outgoing calls. Later events use the original leg instead of rerouting by number.

Exit: shared calls reach the correct tenant and call spec exactly once.

### C — Connect and verify the modal

- [x] Connect the reviewed dialog to real reads/saves. Keep existing named service
  references; verify save/reopen, Cancel, resets, and clearing/requiring the
  application ID when tenant credentials are edited.
- [x] Inspect platform, inherited and overridden states at desktop/mobile sizes
  with `agent-browser`, including the webhook URL. Update the telephony usage docs.
- [x] Run the focused Calls, Persistence, Gateway and Console checks and all five
  root gates below. Record evidence before checking off the milestone/index.

Exit: the production modal persists its settings and calls use those settings.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix deps.unlock --check-unused
```

Live Telnyx tests remain separate from local signed-event acceptance. Provider
provisioning, credential rotation, configuration versioning and a telephony
lifecycle redesign are outside this milestone.

## Prerequisites and design review

Build on completed [scoped services](platform-and-tenant-services.md),
[Telnyx calls](telnyx-calls.md),
[outgoing corrections](outgoing-call-review-fixes.md), and
[public-origin handling](installation-url-and-client-metadata.md).
Use the [reviewed modal](../20261113-0927-telnyx-modal-refresh.md),
[design note](../../docs/design/shared-telnyx-applications.md) and
[telephony guide](../../docs/en/usage/telephony.md).

### Specification review — separate from implementation

Three checkpoints, nine tasks. This review removes compatibility work and the
unnecessary instruction to drop explicit-application uniqueness: inherited rows
can share the platform application with their stored IDs left null. Configuration
comes before routing, followed by production integration. Signature checks,
unambiguous number routing and duplicate protection remain necessary for sharing.

All nine tasks are verified. Configuration, migration, shared routing, duplicate
protection and production integration pass their focused acceptance checks. The
shared dialog was inspected in headless Chrome at desktop/mobile sizes. All five
root gates pass; the umbrella reports 5,262 tests, zero failures, 381 excluded
(seed 589797). The Console frontend suite passes 1,106 tests, with the final test
button and fixture changes covered by focused reruns. Four PostgreSQL concurrency
cases and populated migration acceptance also pass. Live-provider calls were not
run. See the [review evidence](../20261113-1123-simplify-telnyx-milestone.md) and
[implementation labnote](../20261113-1114-implement-shared-telnyx.md).


### Post-review corrections

Astra xhigh reproduced two UI integration gaps after the implementation commit:
editing an inherited application's outbound caller number was blocked, and a
service-only writer could not open the application editor. Both are fixed with
regression tests; credential and application permissions remain separate. The
follow-up Astra review found no additional confirmed defects. See the
[fix evidence](../20261113-1431-fix-telnyx-review.md) for automated and desktop/mobile
browser verification. These corrections do not change the approved backend contract.

Final follow-up acceptance: all five root gates pass; 5,264 Elixir tests and
1,109 Console frontend tests pass, with zero failures. Both original reproductions
are green. Desktop/mobile browser inspection and the follow-up Astra review pass.
