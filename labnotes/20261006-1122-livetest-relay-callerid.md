# Live test relay warm-up and caller ID error

## Context

Follow-up review of `817453a4`/`18cb9d8b` (outgoing call review fixes). Task from the user: fix
two review findings, reproducing each with a failing test first.

## Relay warm-up (issue 7)

- Observed: after the fix commit, every cold `bin/livetests run --only live_telephony_*` failed at
  "every public Funnel relay to serve health before dialing" (0/10). With `tools:up` started
  ahead, 4/4 passed. Polling with `curl --resolve` showed all three relays reachable after 69 s;
  earlier probes timed out or were closed.
- One discarded attempt failed with `eaddrinuse`: my own throwaway `python3 -m http.server 4600`
  was still running. Kill local probes before live runs.
- Red: added slow and dead relays to the fake curl in `test/shell/livetests_tools_test.sh`;
  failed with "tools:up did not wait for a slow relay".
- Fix: `await_public_relays` in `bin/livetests` (dns.google A records, then `curl --resolve`
  each relay; any HTTP status counts, 000 does not). Fakes need stdin redirected, so probes
  use `< /dev/null`.
- Live after fix: cold runs telnyx/twilio x2 all passed (35-132 s per run including warm-up).

## Caller ID error (issue 8)

- Red: Calls review tests, persistence lock test and Gateway authoring HTTP test expected
  `telephony_caller_id_missing`; got `provider_credential_unavailable` / `invalid_call_spec`.
- My first control case was wrong: publish refuses with errors stored at save time, so saving
  against the caller-ID-less fixture made the control report the caller-ID error. Saving against
  a valid service and publishing against an empty repository isolates the credential path.
- Fix: `TelephonyServices.check_requirement/2`; propagated through persistence, test repository,
  plan bindings, call spec credentials and `CallSpecWrites`.

## Evidence

- Shell suites: livetests, tools, telephony pass.
- Calls 134, Persistence 213, Console 215 tests, 0 failures; review tests 4/4.
- Root gates: see the commit message.
- Caveat: "Telephony webhook failed" warnings are captured by ExUnit and only printed for failing
  tests, so grepping passing-run logs for them proves nothing.

## Explicit `to` and `/calls` (issue 9)

- User decisions (2026-10-06): rename `/outgoing-calls` to `/calls`; pass the destination as an
  explicit `to`; record dialed and caller ID numbers on the call.
- Probe before the change (throwaway test, deleted): missing or `555-0100` phone variable gave
  `503 outgoing_call_start_failed` plus a failed call record; a valid one gave 201.
- `to` is pinned into the plan as the callee's `connection.number` before compilation, so the
  engine resolver and gateway dialer needed no change.
- `from_number` is read from the service at admission. The dialer still reads the service at
  dial time; an edit to the service in that sub-second window could make them differ.
- Kept `claim_outgoing_call/5` (fixed-number callers) and added `/6` with `to`, avoiding churn
  across 39 call sites.

## `variables` request field (issue 10)

- Public inputs found by search: the outgoing `/calls` body and the web preparation body
  (`@preparation_fields` in `call_admissions.ex`). Error paths from `CallSpecCompiler` and
  `CallInvocation` reached clients as `["initial_variables", ...]`; now `["variables", ...]`.
- Left internal names alone, including the `"initial_variables"` key inside the outgoing
  idempotency digest, so digests of stored keys do not change.

## GPT-Live over a carrier call (2026-10-06)

- User decision: one speech-to-speech provider (GPT-Live) over one carrier pair. Added
  `ConfiguredTelephonyFixture.sts_sources/3`/`publish_sts/3`, a local spec test, and the live
  case `live_telephony_sts` (Twilio -> Telnyx). OpenAI is provisioned only when its key exists.
- Runner fixes found while running it: `live_telephony_*` tags now start the tools (red shell
  test first); `tailscaled` inherited fd 3 (the progress-report descriptor), so piping
  `tools:up 2>&1 | tail` never saw EOF; it now closes fd 3 and fd 9 (red shell test first); the
  relay wait default rose to 300 s after one cold start needed more than 180 s (others 69-70 s).
- The live case fails 5/5: answered, callee media attached, GPT-Live ready, but startup's room
  probe keeps blocking on `:media`. Re-running its preparation from the test diagnostics gives
  `media_connection` `:unsupported_audio` for the callee. Recorded as tasks on the GPT-Live
  milestone; not fixed here.
- Mistakes: a `pkill -f` pattern matched its own shell and killed the command running it.

## Opening rule (user decision, 2026-10-06) — not yet implemented

- Openings (first messages) must never be interrupted: they can be regulatory requirements.
- Text agents: collect caller speech during the opening and process it after the opening plays.
- Speech-to-speech agents: drop caller audio during the opening (never forward it to the
  provider); caller speech must not end the session or call.
- Findings: `AgentOutput.interrupt/2` interrupts every active agent turn on caller
  StartOfTurn with no opening exemption (text path breaks the rule too). `opening_audio`
  already gates input closed and discards it. `FirstMessage` status never becomes
  `:completed`, so "opening still playing" needs explicit tracking. GPT-Live
  (`GPTLiveOpening.decode/2`) and Google (`STSOpening.accept/2`) turn caller input during a
  fixed opening into `:session_failed`.
- Next: red tests for (1) text first message surviving caller StartOfTurn with the turn
  processed afterwards, (2) STS input gated during opening with the session surviving,
  (3) 24 kHz STS output converted to the room's 48 kHz; then fix, then the live STS case.

## Continuation outcome

The input refusal, opening protection and 48 kHz output are completed in
[the continuation labnote](20261006-1547-protect-phone-openings.md). The real
receiver-first Twilio → Telnyx GPT-Live call passed, then passed again after the
silence switch and tracing were removed. The direct hosted harness also passed
both checks after keeping its audio clock running while awaiting events.
The earlier failing-run notes above are historical; the wider GPT-Live checkpoint F
phone scenarios remain open.
