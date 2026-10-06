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
