# Native tool rejections

## Scope and reproduced behavior

Continue from `428ce512` (10/20 milestone tasks, C2 complete). Close silent native
request rejection and retain the existing shared registry's duplicate protection.
No new executor, provider branch or replay cache is needed.

Focused red tests reproduced three issues before implementation: fresh requests
after hold/policy denial disappeared without a result or terminal failure;
completed private call references could execute a second business operation; and
worker saturation published `ToolCallStarted` despite rejecting admission.
Changing the replay's arguments to an invalid schema also reproduced a second
final result, so replay detection must precede argument validation.

Initial rejection lane: 4 tests, 3 failures (seed `827258`). Invalid-argument
replay lane: 3 tests, 2 failures (seed `99669`). Admission publication lane:
4 tests, 3 failures (seed `279826`). These are project-owned failures rather than
dependency behavior. Existing unknown-name, malformed-argument and read-only
variable cases supply adjacent rejection coverage.

## Implementation and decisions

- Ignore an already pending private reference before checking current input
  permission/origin; holding or retiring speech must not invalidate admitted work.
  A fresh request while input is held or denied terminates the capability with
  `:tool_not_permitted`, and its temporary allocation tree retires.
- Derive the opaque native invocation identity from activation and private call
  reference. New sequence, turn or arguments do not create another identity.
  Before descriptor validation, query the existing registry's active/consumed
  records. A retained-ID replay terminates the invalid exchange without another
  result or lifecycle publication. Actual registry submission still atomically
  enforces identity and capacity.
- Publish started and retain the room association only after registry acceptance
  and capability admission. Fresh schema/selection/capacity failures keep their
  bounded native error result; failed delivery terminates explicitly.

Consumed-ID protection has the existing configurable bounded retention window.
References rejected before registry submission are not retained. This change
does not promise lifetime deduplication after eviction. The full C3
retention/lease acceptance and C1 compiled-room partial multi-tool parity remain
open. No compatibility wrapper or separate native cache was added.

## Verification

Focused rejection/interruption lane: 11 tests, zero failures (seed `850554`).
Complete capability, native lifecycle, native identity and shared registry files:
156 tests, zero failures (seed `836200`). Formatting, warnings-as-errors compilation,
strict Credo and unused-dependency checks pass. Independent Astra xhigh source/test
review found no actionable defects and confirmed C1 bounded-rejection closure
after gates. The initial full umbrella run (seed `877574`) reproduced one outdated
allowlist unit fixture with no invocation registry. Replaced its result-only stub
with the existing real capability helper; the same unauthorized/no-started
assertions remain, with a provider receive trace verifying the bounded error and
an assertion that capability pending state clears. That whole file passes:
32 tests, zero failures. The umbrella run was stopped after this failure rather
than running unrelated slow suites on a known failing tree. The complete Call
Engine suite then passed: **2,385 tests, zero failures, 100 excluded**, seed
`370087`. Lean build, oracle checks and replay pass (seed `707748`); final full
umbrella acceptance stays in C4. A final documentation review found a stale C1 table count; confirmed
and corrected it to 4/5, consistent with the 11/20 checklist and index.
Independent Astra xhigh re-review reports no remaining actionable findings.
