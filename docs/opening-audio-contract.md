# Opening audio contract

Status: fixed-text playback and input gate implemented; file playback remains in progress.

## Decision

Call-definition schema `20260910.02` adds one optional call-level `opening_audio` value. It is
either fixed text:

```json
{"type": "text", "text": "This call may be recorded."}
```

or a remotely fetched file:

```json
{"type": "file_url", "url": "https://assets.example.test/opening.wav"}
```

The object is closed. Text and URL cannot be mixed, unknown types and keys fail, text is a
non-empty UTF-8 value of at most 4096 bytes, and URLs are HTTPS values of at most 2048 bytes
with a host and without user information or fragments. Query strings remain syntactically
valid because ordinary asset CDNs use them, but operators must not put credentials or signed
URLs into definitions. The typed source is copied into the immutable resolved plan before a
room starts and its routine inspection exposes only the source type.

Omission means there is no opening-audio phase. It does not insert silence or delay startup.
The runtime targets only the entry caller. Text uses the initially resolved receiving
agent's TTS binding. Normal text and media input remain closed until the output sink reports
actual playout completion; preparation, synthesis completion, enqueueing, or provider
readiness do not open the gate. Input received while the gate is closed is discarded rather
than buffered or replayed. A preparation or playback failure ends the room explicitly and
never silently opens normal conversation. A text source without a resolved TTS binding and
the not-yet-supported file source fail validation before a room is registered.

## Remaining runtime choices

Before file playback is implemented, the implementation must pin a bounded download policy,
redirect and network-address policy, accepted audio container/codec, duration and byte limits,
and cache ownership. The first implementation should accept one exactly validated format that
the existing output sink can consume without implicit transcoding. Broader media support can
be a later schema-compatible expansion only if it preserves deterministic validation.

## Alternatives rejected

- A single untagged string is ambiguous between fixed text and a URL and cannot evolve safely.
- Accepting both text and URL and choosing one by precedence hides definition mistakes.
- LLM-generated notices are nondeterministic and can change the meaning of a fixed opening.
- Releasing input on synthesis or enqueue completion is too early; the caller may still be
  hearing the opening.
- Buffering caller media during the opening would later submit speech uttered before consent
  or admission and would make the visible gate misleading.

## Implications

The definition parser owns syntax and source safety, while a separate runtime coordinator
must own preparation and gate progression. `RoomAuthority` remains the room decision owner;
it must not absorb fetching, decoding, caching, or lifecycle timer callback families.

## Verification

The compiler contract is covered by `opening_audio_compiler_test.exs`: missing runtime type and
schema-version assertions were observed red first, then 2 focused tests passed. The fixed-text
runtime is covered by `opening_audio_room_test.exs`: its first run failed because no synthesis was
started, then 3 tests passed for real playout gating, required-playback failure, and pre-room
rejection of unsupported sources/configuration. File playback and lifecycle evidence remain
pending.
