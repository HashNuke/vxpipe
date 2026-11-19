# Diagnostic source worker

- Continuing from f7631886. Three source-worker tests and a separate pool test
  failed for missing worker/pool APIs before implementation.
- Added a temporary benchmark-only source worker with one sequential inference
  request. Capture reservations cover queued and in-flight packets, including
  provider landmarks. It normalizes through AudioTimeline, uses bounded async
  inference, and emits fixed acoustic boundary tuples through another independently
  bounded CaptureHandoff. No transcript or speech-control event is emitted.
- Source gaps/inference failures reset only the benchmark recurrence and advance
  its epoch. Provider settlement does not reset this standalone state. Initial
  coverage stays partial through its first complete endpoint; missing/uncertain
  timing stays nullable. Identical input duplicates do not execute another model.
- Worker monitors its owner, collector and inference runtime and checks grants
  every250ms. Revocation stops it, discards queued/in-flight reservations and lets
  the runtime's owner monitor retire its inference task. Native execution capacity
  still remains reserved until actual task termination. Output saturation retires
  observation rather than growing another queue. Status output redacts PCM.
- SourceSupervisor separately bounds sources (default16, max32) and native jobs
  (default1, max8). It loads its own pinned model lazily, avoiding dependency on
  operational ModelCache startup. Its startup API is coordinator-only, not a
  voice admission API. Exhausted pool restarts degrade diagnostics only.
- Initial worker/pool checks4/0. Automatic source selection/attachment, reuse-mode
  consumer, raw Opus decoder, collector correlation and persistence are still
  pending. No combined C checkbox or live support is claimed by this foundation.

- Real packaged-model evidence preserves fixture onset4096 and endpoint34816,
  including partial model windows across three one-second packets. Output
  saturation, deduplication, source-gap resets and status redaction pass.
- A retained shutdown test failed with two still-reserved packets after supervised
  stop. The worker now traps parent exits for graceful cleanup. Untrappable crashes
  remain fenced by receiver/owner death; cleanup is not the safety mechanism.
- Astra xhigh final review clean:19tests/0, including nine independent probes for
  fragmented8/16/48kHz PCM, pending samples, failures, source mismatch, owner/
  collector/runtime death and hard crashes. Final broad/static reruns follow.
- Prior timeline umbrella run reported a Cartesia startup close-reason mismatch and Twilio
  media-harness startup failure. Cartesia same-seed file passed12/0 in isolation.
  Twilio original startup case passed in the isolated file, but a separate silent
  transfer case failed with media_session_not_found. These are unresolved broad
  acceptance failures, not relabelled green. The Engine failure predates this
  worker implementation, which is not yet production-wired. Focused logs remain
  under /tmp/vxpipe-{cartesia,twilio}-startup-repro.log.

- Final affected suite109/0; format, warnings-as-errors compile, strict Credo,
  unused-lock check and Lean pass. Prior timeline umbrella run finished exit2,
  with the two failures above; other applications passed. No cause is asserted
  from isolated passing tests, and final root acceptance remains open.
