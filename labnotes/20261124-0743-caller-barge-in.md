# Caller barge-in baseline

QA call on 2026-11-24 at 07:40 UTC. Matched the gardening and commercial-property questions to accepted inputs and correlated each caller turn with an interrupted agent turn. Read persisted call facts and turn diagnostics. Scribe v2 Realtime used provider VAD commits with a 1.5 s silence threshold. Silero v6.2.3 ran in benchmark-only mode. The run closed incomplete with source_changed. Both target turns have available endpoint measurements.

| Measurement (ms) | Gardening | Commercial properties |
| --- | ---: | ---: |
| Estimated onset to Silero confirmation | 145 | 137 |
| Interruption request to server egress stop | 24 | 26 |
| Estimated onset to correlated egress stop | 1,145 | unavailable |
| Estimated speech end to Scribe endpoint | 1,994 | 2,193 |
| Estimated speech end to first response audio | 2,842 | 2,897 |

For gardening, the interruption request followed Silero onset confirmation by 976 ms. For commercial properties, confirmed speech preceded the interrupted output chunk's playback start by 305 ms. Its barge-in record reports missing onset evidence. Keep that duration unavailable. Server egress does not measure handset playout.

Use operational Silero on a new revision of the same call spec as the first comparison, retaining Scribe settings. Repeat both interruptions, especially across consecutive output chunks. Check premature interruptions on brief noises and backchannels. Measure endpoint delay separately and check for splitting a caller turn at a mid-question pause before tuning the silence policy. These data are a baseline, with no measured operational-Silero treatment effect.

Published the comparison as revision 12 (published version 9) of Demo AI receptionist. A database comparison with revision 11 verified the only source change was enabling participants.caller.capabilities.speech_to_text.vad. The next live trial covers two intentional interruptions and one brief acknowledgment during agent speech. Record whether the agent yields and whether it resumes after the acknowledgment.
