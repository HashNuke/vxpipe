# Phone recovery acknowledgement

D1's first umbrella run covered 1,788 tests, with 40 exclusions and one failure
in the Twilio cue-disconnect recovery harness: no source recovery speech arrived.
All other applications passed. The isolated cue-disconnect scenario passed an
initial run plus 20 repeats.

The fixture responds to the source agent's transfer acknowledgement with speech,
but it never sends provider speech-start/completion events for that acknowledgement.
The recovery helper discarded earlier controls while waiting for the recovery text.
A pending cancelled speech request must drain before the project-owned TTS queue
can start the recovery request. This is a candidate ordering problem; add bounded
control diagnostics and reproduce before claiming it as the observed cause.

The full 13-test Twilio harness also passed an initial run plus ten repeats; the
original failure has not reproduced independently. Review confirmed that the mock
does not finish the earlier speech request when it is emitted. The recovery helper
now supplies its `SpeechStarted` and `SpeechMetadata` acknowledgements before
continuing to await the exact recovery text. It still checks actual speech output,
media, caller ownership and continued conversation. No runtime behavior changes.
Both carrier harnesses are being repeated together before the final umbrella run.

The combined Telnyx/Twilio harness passes all 26 tests in an initial run plus five
repeats. The helper's acknowledgement matches the existing capability contract:
cancelled provider speech finishes before queued replacement speech starts.
The final static checks and umbrella rerun are in progress.

Production webhook selection has not changed during this investigation. Do not
extend deadlines or add sleeps to make the harness pass.

Final review: the fixture only acknowledges the exact earlier transfer speech;
it does not skip the recovery assertion or replace the source transport. The final
combined umbrella passes 1,788 tests, zero failures, 40 excluded. Root formatting,
warnings-as-errors compilation, strict Credo and unused dependency checks pass.
Commit this small fixture correction separately from the reviewed D1 removal.
