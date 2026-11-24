# Implement caller recovery

## Carrier exit

Ran checkout setup. The configured gateway test first failed waiting for a carrier command after disconnecting the Scribe transport on an answered Telnyx call. Added the exact-binding handoff to the original leg and packaged a 3.15 s mono 8 kHz PCM WAV. The Telnyx playback command sends the WAV inline to the caller. The recording is generated with FFmpeg's flite filter using the slt voice and the phrase “We have lost the audio connection. Please call back.”

The test then observed playback followed by hangup after a matching signed callback. A second red test killed the media process outright. Monitoring the exact registered media generation made that case pass. A third path disconnects recognition with storage unavailable. Verified caller-initiated hangup, missing completion, mismatched/duplicate callbacks, and the production adapter's payload in the gateway suite.

The journal test initially failed at the missing Calls boundary; it now exercises PostgreSQL, rejects another incarnation, and retains the first event deadline on retry. A terminal event can update the stored leg to ended. Missing storage evidence remains queued with the live owner. A separate recovery lookup test verifies scope, all carrier identities and the retained deadline. Signed HTTP replay with no live owner verifies against the pinned Telnyx credential before writing terminal evidence. Both persistence and gateway focused suites passed. Live handset outcomes remain open.

An exact-media failure signal is queued to the leg owner. A regression test
suspends the owner while closing the recognizer and confirms that teardown can
finish before the owner resumes and requests playback. Nine scoped gateway
cases passed. An additional configured French-language call exposed delivery
of the English recording. The activation filter now checks the pinned language,
using English for the QA default where no language was specified.

The live harness discovers the machine's two Telnyx test numbers. No personal
number is needed for automated carrier interoperability. A controlled listener
is still needed to attest to the words heard and the length of perceived silence.
This checkpoint implements callback-and-end. Transfer and recognizer replacement
remain separate milestone checkpoints.

The broader suite caught a source hold/arm path without a carrier binding.
Recovery now requires an explicit eligible binding before inspecting the
attachment. The hold/arm regression and French-language case passed together.

Release verification passed on the staged implementation: umbrella format,
warnings-as-errors compilation, strict Credo, unused dependency check, Lean
build and oracle replay, and all ten default umbrella test suites. Gateway
reported 916 tests with zero failures. Live carrier and handset checks run
separately.
