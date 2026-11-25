# Handset disconnect at interruption cue

On QA revision bd89e063 the handset caller heard the interrupt cue and then disconnected. The live fixture had recognized “transfer test”. At 08:45:20.121 UTC the agent text-to-speech process received an invalid_playback response during cancellation and exited with provider_failed. The cancellation state recorded 2160 ms played and a terminal signal. At 08:45:20.141 the media session exited after the room reported agent_unavailable. The runner subsequently raised KeyError while polling the room for the next question. The recognizer fault injection and transfer checks had not yet run.

The missing connection in the test is a downstream symptom. Reproduce the overlapping playback completion and cancellation with a deterministic test before another handset window. The log establishes the failed cancellation response but does not establish why the playback validator rejected it. Both borrowed numbers were restored.

The capability had received 103,679 mono samples at 48 kHz. A paced 20 ms sink frame includes one sample of padding at the end of this utterance, so the sink reported 2160 ms while the speech protocol permits 2159 whole milliseconds. A deterministic test generated 959 samples, delivered the provider final, and interrupted at a sink receipt of 20 ms. The unmodified runtime exited with invalid_playback and returned unavailable (seed 672610), matching the handset failure.

The TTS capability now converts a final padded frame receipt back to source PCM duration for cancellation and normal settlement. The change covers both observed and ordinary interruptions and retains the protocol's bounds checks. The regression verifies that a second turn plays to completion on the same speech capability.

The final regression passed 26 consecutive times. The focused format and cancellation tests passed together (8 tests, seed 526430). The unattended Telnyx transfer first timed out waiting for the destination test room after bridge confirmation (seed 609971). A fresh call passed reciprocal speech, settlement and cleanup in 31 seconds (seed 984236). Both runs restored the two QA numbers. This live lane separately checks the downstream recovery bridge.

Formatting, compilation with warnings as errors, strict Credo and unused-dependency checks passed. The umbrella run had one canceled PostgreSQL query in persistence during overlapping test activity. The full persistence suite passed on its own with the same seed, and every other umbrella application passed in the original run.
