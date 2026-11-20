# Scribe acknowledgement compatibility

The real Scribe session acknowledgement omits `commit_strategy` while echoing the eight other diagnostic fields. Requiring all nine prevented the room observer from attaching and prevented run construction. Configured ContinuousSTT mode already pins `:vad`; manual STTSession continues to report diagnostics unsupported.

Added shared Scribe diagnostic eligibility on top of the existing exact acknowledgement validator: allow all nine keys or missing exactly `commit_strategy`. Conflicting echoed strategy and every other missing field remain rejected. RoomService and Calls Attachment use that shared eligibility. The persisted outer profile still records configured `commit_strategy: :vad`, while the inner provider acknowledgement contains only actual echoed keys. LatencyRun accepts exact eight- or nine-field maps; no placeholder or fabricated provider echo is stored. CapturePacket and persistence codec already preserve subsets and required no changes. No turn-control, provider execution, or model behavior changed.

Reference: [ElevenLabs realtime API](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime) separates the commit_strategy query parameter from the session_started config echo. The narrow eight-field compatibility condition follows the actual session evidence reviewed for this milestone, rather than accepting arbitrary incomplete profiles.

Red evidence:

- Engine RoomService: 29 tests, one expected failure (eight-field acknowledgement never started collector).
- Calls Attachment: 8 tests, one expected failure (`:unavailable`).
- Persistence: 20 tests, one expected failure (`:invalid_latency_run`).

Green evidence:

- Engine RoomService, Scribe acknowledgement and direct/wrapped session profiles: 41 passed, seed 151028. Includes existing manual unsupported coverage.
- Calls Attachment and LatencyRun: 16 passed, seed 834760. Includes explicit conflicting strategy and missing-other-field rejection, legacy nine-field acceptance, and actual eight-field capture.
- Persistence LatencyStore: 20 passed, seed 178002, including eight-field round-trip with no invented key and unchanged identity immutability. The refused-port log comes from the existing deliberate storage-unavailability test.

No provider requests, Telnyx tests, inference model tests or full-suite runs were performed.

Independent Astra xhigh source review is clean. Live browser verification uses
the actual echoed-key set and compares stored/API profiles without filling absent
keys; that live acceptance remains pending at this implementation checkpoint.
