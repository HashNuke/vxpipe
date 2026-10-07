# Readiness change notification

## Decision

Startup readiness collectors re-probe when a resource owner reports a readiness change,
instead of discovering the change on their next poll. `Readiness.Watch` is a duplicate-key
registry (`Vxpipe.CallEngine.ReadinessWatchRegistry`) keyed by the process that owns a
resource. A collector subscribes to the owners of the resources it tracks. An owner calls
`Watch.changed/0` when its readiness evidence changes. The collector then starts a probe
batch at once. If a batch is already running, it probes again as soon as that batch
finishes. The notification carries no status: the collector still asks each resource's
adapter, so adapters remain the single source of readiness. The 100 ms poll remains as the
fallback for owners that do not notify.

Owners that notify today:

- The speech-to-text capability, after provider events and prepared-policy completion. It
  compares only the fields its readiness is derived from, so frequent transcript events
  cost no hashing.
- The text-to-speech capability, when its provider session reports ready.

The speech-to-text ingress derives its status from the speech-to-text capability, so the
batch that the capability's notification triggers re-probes the ingress too.

## Evidence

The protected-opening room tests (`opening_audio_room_test.exs`, from `465d563c`) failed
7 of 20 solo runs and 7 of 10 runs on a saturated 4-core machine. They assert the opening
with ExUnit's 100 ms default. Timestamped tracing of 200 openings showed two causes:

1. At the first probe after attach, `speech_to_text`, `speech_to_text_ingress` or
   `text_to_speech` was still connecting. Each became ready a few milliseconds later. The
   collector saw it only at its next 100 ms poll, so the opening started 102-107 ms after
   attach. Live calls had the same added latency on every opening that raced provider
   connection.
2. The first test in each test VM took 40-75 ms (median 50 ms) because the test VM loads
   modules lazily, while releases preload them at boot.

After the change, the same 200-opening trace had no poll gaps and every opening started
within 10 ms (median 3-5 ms), including the first test per VM. The test helper now preloads
the loaded applications' modules, as a release does.

## Rejected alternatives

- Raising `assert_receive` timeouts. It hid both causes, and left the production latency
  in place.
- A shorter poll interval. Polling still bounds latency by the interval, and costs probe
  work on every room while it waits.
- Carrying the new status in the notification. That would make two sources of readiness
  truth; probing through the adapter keeps one.

## Tests

`readiness/collector_test.exs`: a change notification re-probes without a poll; a change
during a running probe re-probes once that probe finishes; a real speech-to-text provider
and a real text-to-speech provider connecting each make readiness ready with polling
disabled and no refresh. Each test failed before its part of the change.
