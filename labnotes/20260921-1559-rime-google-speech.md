# Rime and Google speech

2026-09-21. Started after the unified service-card UI checkpoint `ee299d3c`. The worktree was
clean. All four saved platform records (Deepgram, Rime, Google, Telnyx) were observed by a
read-only query in the earlier checkpoint; Deepgram, Rime and Google credential probes returned
valid without logging keys. A credential probe does not establish speech model availability.

Official Rime documentation describes `/ws3` batch `done` events and `clear`, but `clear` only
removes buffered text. Its streaming HTTP Coda endpoint accepts complete text, streams PCM and
ends one response per utterance; this initially looked simpler.

Two local, one-utterance probes with the saved platform credential changed that decision. The
HTTP endpoint (`audio/L16`, Coda, astra, 24 kHz) returned 200, 72,960 even-byte PCM bytes,
first audio at 1,471 ms and completion at 1,890 ms. The JSON WebSocket with `segment=never`
connected in 1,387 ms, then after complete text + flush returned first audio in 538 ms and a
`done` in 1,601 ms, with 69,120 even-byte PCM bytes. Neither script logged the key or audio;
both stayed in `/tmp`. These are single samples with different utterances and do not establish a
distribution. They do show the value of preparing a socket before a call needs its next TTS
utterance. The design now selects a prepared WebSocket and retires it upon cancellation unless
the protocol can prove output is fenced. An initial probe pattern mismatch printed credential
metadata, including a last-four hint, to the tool output; the script was corrected before either
network request. No secret or hint entered the repository.

Google's current dedicated TTS and live-transcription APIs use different transports. Live
transcription documents interim and final text and provider VAD, but does not document a separate
speech-start event. An isolated synthetic-audio probe is required before declaring conversational
STT because barge-in currently depends on prompt speech-start evidence.

Design decision and vertical acceptance gates are in
`docs/milestones/rime-and-google-speech-providers.md`. No runtime capability was declared yet.
