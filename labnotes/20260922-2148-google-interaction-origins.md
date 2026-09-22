# Google interaction origins

Baseline `3cf9603a`, with the five deliberate controller reds as the only
uncommitted file. The capability now supplies immutable opted-in contexts but
Google still uses caller input references and a legacy descriptor. Read the
Google response design, STSSession/STSInput, the shared input staging and
provider test transport. This checkpoint targets accepted context association
at the Google input callback; it does not claim response-owner adoption.

Design decision recorded in the milestone and Google response document before
tests/runtime. Google wire content is unlabelled, so the first accepted origin
must be fixed before its input is sent. Same-context operations are allowed
across `IN_PROGRESS`; a different context returns `:busy` before wire send
until a future covered cutover mechanism is proven. Keep an unadvertised local
opt-in fixture profile so existing legacy tests remain a usable baseline.

Focused red/green commands, review findings and gate evidence follow.

## Red/green evidence

From `apps/vxpipe_call_engine`, `ERL_FLAGS='+S 2:2' mix test
test/vxpipe/providers/google/sts_session_test.exs --seed 0` first passed the
23 existing cases and failed two new opted-in cases at provider initialization:
the descriptor did not yet accept the local opt-in. Added validated descriptor
opt-in and `submit_input/3` callback. It proposes a context before invoking the
legacy wire-send handler, commits it only on success, and restores the previous
context on a clean rejection. A different context returns `:busy` before wire
send; the exact context survives `IN_PROGRESS`. The first
green run had one test expectation error (`Session.push_text/3` returns `:ok`,
not a request handle); correcting that fixture made the focused file 25/0.

A subsequent invalid-UTF8 provider rejection test produced
`{:error, :session_failed}`, not `:invalid_text`: the shared provider boundary
maps non-retryable provider errors to allocation failure. Replaced that fixture
with an authentic `goAway` renewal gate, where provider input returns retryable
`:busy` and no context is committed. Focused file passes 26/0. The larger
Google-provider plus shared speech/context group passes 295/0, with three
integration tests excluded. No hosted call or full umbrella suite was used as
TDD red proof. The five actual-controller first/continued-response reds remain
uncommitted and unchanged.

Post-commit static gates are pending; review findings follow.

One additional provider-owned contract hole was identified locally before
review completed: direct `STSSession.push_audio/2`, `push_text/3` or
`input_activity/2` calls could bypass context on an opted-in allocation.
Recorded it in the milestone and reproduced 28/1 in the focused provider file.
Separated the private input-command implementation from the public GenServer
callback; legacy commands now return `:unsupported_operation` for opted-in
allocations while `submit_input/3` invokes the same wire logic after binding.
The focused file passes 28/0, and the larger Google-provider/shared-speech
group passes 297/0 with three integration exclusions. A closed-option test also
reproduced duplicate `response_start?` acceptance (27/1); explicit unique-key
validation made it 27/0 before the callback-bypass case was added.

Independent Astra xhigh read-only follow-up found no remaining actionable
issue in this scoped source diff. It did not run tests or hosted calls.
Post-commit root static gates remain pending.
