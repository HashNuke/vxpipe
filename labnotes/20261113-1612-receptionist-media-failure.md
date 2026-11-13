# Receptionist media failure

- The live release was the latest QA merge, with the earlier speech-configuration
  and post-hangup bookkeeping fixes present.
- Matched the user's Linphone attempt at 16:16 UTC: answered, then terminated
  roughly 0.66 seconds later. A controlled SIP call independently reproduced an
  unexpected carrier BYE within seconds. Both calls are correctly ended in the DB.
- The TTS capability failed with `audio_output_failed`; the underlying sink
  rejected its first push with `unsupported_audio`. The provider descriptor is
  mono signed little-endian PCM at 16 kHz. Gateway direct output requires 48 kHz.
- The TTS capability forwarded provider PCM unchanged. STS already normalizes
  to canonical playout with `PCMResampler`. Reuse that boundary for TTS, retaining
  native provider audio for acknowledgement and usage accounting.
- Do not change saved model/service configuration or relax the gateway's format
  contract. No environment files were read and no credentials were printed.
- Regression first: real ElevenLabs session adapter with a controlled transport,
  two audio chunks, held sink acknowledgement, confirmed playback and duration
  accounting. Rates 8, 16 and 24 kHz failed the canonical-rate assertion; 48 kHz
  passed. Keep the same tests after adding conversion before sink delivery.
- Normalization passes 52 focused speech tests. The full umbrella run exposed
  five older native-format expectations in compiled room tests. Updated them to
  assert canonical sample counts/rates; the Morse round trip decodes at 48 kHz.
  The affected compiled room and format tests now pass together (10 tests).
- Built and deployed the production release, then used a TLS SIP client with
  bidirectional PCMU RTP. A 30-second call received greeting audio and remained
  connected until the client sent BYE. The call row and cleanup completed.
- The first spoken-question test exposed a separate Google model rejection:
  the saved Gemini 2.5 Flash selection was unavailable to this account. The user
  had a newer published revision using Gemini 3.5 Flash-Lite. Kept it unchanged.
  A second 30-second test received both greeting and reply audio after the spoken
  question, with no provider warnings/errors and completed database cleanup.
- Earlier signaling-only acceptance checks did not establish successful greeting
  playback. Actual RTP and application evidence are required for this path.
- A subsequent broad run exposed a teardown assertion racing Registry's removal
  of a terminated room owner. The test now monitors any remaining listed owner
  and checks termination rather than demanding immediate Registry bookkeeping.
  The focused cleanup regression passes; production teardown is unchanged.
