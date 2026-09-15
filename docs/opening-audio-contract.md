# Opening audio contract

Status: fixed-text and HTTPS-file playback, bounded reusable-asset caching, and input gating are
implemented. Schema `20260915.01` gives text openings an independent inline TTS selection and
resolves its named credential from the tenant database. Opening preparation runs independently
of the initial agent and coordinates with the caller setup wait sound. The room-recording path
stays closed during opening playback, and all opening output is labeled private.

## Decision

Call-definition schema `20260915.01` supports one optional call-level `opening_audio` value.
Fixed text requires its own inline TTS selection:

```json
{
  "type": "text",
  "text": "This call may be recorded.",
  "text_to_speech": {
    "provider": "deepgram",
    "model": "flux-haley-en",
    "credential_name": "opening",
    "options": {"encoding": "linear16", "sample_rate": 48000}
  }
}
```

or a remotely fetched file:

```json
{"type": "file_url", "url": "https://assets.example.test/opening.wav"}
```

The selection owns its provider, model and public output settings. `credential_name` selects the
exact tenant/provider binding; omission selects `default`. It supplies no model or voice settings.
The compiler pins the public selection independently of participant capabilities and defaults.
Opening preparation resolves current credentials through the tenant source before starting its
TTS capability. It works with an initial human receiver and needs no agent activation or global
provider credentials. Missing opening credentials block definition save even when caller speech
is fully configured. A cached asset cannot bypass credential validation for a new activation.

The object is closed. A text source must contain a supported `text_to_speech` selection;
missing/null/unsupported selections and retired profile strings fail explicitly. File sources reject that field and
require no TTS. Text and URL cannot be mixed, unknown types and keys fail, text is a
non-empty UTF-8 value of at most 4096 bytes, and URLs are HTTPS values of at most 2048 bytes
with a host and without user information or fragments. Query strings remain syntactically
valid because ordinary asset CDNs use them, but operators must not put credentials or signed
URLs into definitions. The typed source is copied into the immutable resolved plan before a
room starts and its routine inspection exposes only the source type.

Omission means there is no opening-audio phase. Required call startup still waits for its
resource readiness; `wait_sounds.call_setup` controls private audio during that interval.
The runtime targets only the entry caller. Text uses a separate supervised TTS capability owned
by the opening lifecycle, attributed to the caller with no agent activation, and released after
opening completion. Its supervised preparation runs alongside initial agent construction. File
loading starts once caller output is usable. Agent greetings keep their own TTS capability.
Waiting continues while opening file loading or synthesis has not produced playable PCM. A
room-owned output gate holds the first frame, requests wait pause, and releases it after the
wait player acknowledges pause and the actual output clears its queued tail. It forwards the
real sink's correlated completion acknowledgements. This preserves streamed text playback and
bounded backpressure without pre-rendering a complete notice. After the notice, a still-pending
setup resumes the same wait player and cursor. Initial resource readiness is rechecked after opening
playout and acknowledged wait pause/clear; the earlier observation is not valid indefinitely.
The exact resource generations/configurations, current room binding and policy candidate must still
match. Pending or changed resources resume waiting and refresh preparation under the original
startup deadline, retaining unaffected capabilities. Only a fresh ready result releases conversation.
If startup initially skipped its wait player because the resource graph was already ready, a later
pending release check starts the selected setup wait at zero. Explicit nil remains silent; an
already paused player resumes its existing cursor.
Normal text and media input remain closed until the output sink reports actual playout completion;
preparation, synthesis completion, enqueueing, or provider readiness do not open the gate. Input received while the gate is closed is discarded rather
than buffered or replayed. A preparation or playback failure ends the room explicitly and
never silently opens normal conversation. A text source without a resolved TTS binding fails
validation before a room is registered; file playback is independent of TTS.

Room mixing and both full-mix and individual-track recording obey the same opening boundary.
The mixer starts closed for a pinned call; confirmed opening playout completion and complete
initial resource readiness open it before ordinary input/greeting admission. Frames timestamped
before that boundary are discarded even when decoding or delivery finishes afterward. Recording workers may initialize
earlier, but receive no held caller audio. Private opening output does not enter room recordings. The opening playback gate labels both
its first buffered frame and subsequent streamed frames `audio_scope: :private`, including file
and cached playback, so downstream recording acceptance can exclude them.
Opening completion does not revise privacy policy or restart warmed capabilities. The original
startup-readiness deadline includes this completion; idle and whole-call timers keep their existing
owners and activity rules. Readiness and maximum-duration expiry reject late readiness completion.
Expiry stops pending model preparation, opening fetch and wait playback. Removing the last attached
entry-caller connection before startup readiness cancels that startup even when waits are disabled;
removing a connection clears its own waiting output and cancels its exact output probe.
Silent startup survives when another connection still belongs to the entry caller.
Unexpected wait-player death is a startup failure. WebRTC startup failures send the existing
Small WebRTC peerLeft message once before the bounded connection teardown. A successful room-start
receipt does not imply conversational readiness.

## Migration

Earlier schemas introduced independent opening profiles after the initial inherited-agent voice.
Current schema `20260915.01` replaces those profiles with inline selections and tenant credential
names. Provision the selected tenant credential and supply `opening_audio.text_to_speech` for every
text opening. There is no fallback to participant capabilities, call defaults, another agent,
application provider settings or an invented voice.

Old profile-based definitions and prepared plans cannot run through the current parser/runtime.
The milestone's explicit stored-revision conversion and prepared-call drain remain a final-cutover
requirement before deployment over existing data. Historical revisions and completed-call plans
remain immutable. Omitted openings and file URLs need no TTS selection.

## File asset profile

The first file profile accepts only RIFF/WAVE with one PCM format chunk and one data chunk:
format code 1, mono, signed 16-bit little-endian samples at 48 kHz, with matching block-align and
byte-rate fields. The decoder permits well-formed unknown RIFF chunks but rejects truncated,
duplicate, malformed, empty, trailing, compressed, stereo, differently sampled, or oversized
audio. No transcoding, resampling, remote playlist, or content-sniffing fallback is performed.
The response Content-Type must be `audio/wav`, `audio/wave`, or `audio/x-wav`.

The default file limit is 6 MiB (`6291456` bytes), 60 seconds of decoded PCM, and a 5-second DNS,
connect, receive, and request deadline. Configuration may only select 44–16777216 bytes,
1–300000 milliseconds of audio, and 100–30000 milliseconds per fetch deadline. The HTTP client
does not decompress, retry, or follow redirects. It streams into a bounded accumulator instead
of first accepting an unbounded body and also rejects an oversized declared Content-Length.

Before connecting, literal or resolved addresses are checked and any non-global, loopback,
private, link-local, carrier-grade NAT, documentation, multicast, mapped-private, or otherwise
reserved address rejects the complete answer set. The request connects to one selected validated
address while retaining the original hostname for TLS verification and SNI, preventing a second
uncontrolled DNS resolution at connection time. There is no initial private-host exception.

Decoded assets are cached in bounded BEAM memory. The cache defaults to 128 entries and 64 MiB,
evicts least-recently-used entries, and is shared by the Call Engine application. Keys are SHA-256
digests over the public tenant key, exact URL, and fixed media-profile revision; neither URLs nor
credentials are retained in keys or routine inspection. A different tenant, URL, or profile
cannot reuse the entry. Download/preparation failures are not cached.

Fixed-text synthesis uses the same bounded cache and asset-size/duration limits. Its digest covers
the public tenant key, exact text, complete inline selection and non-secret credential binding,
provider identity, voice/model, encoding, sample rate, and a render-profile revision. Provider implementations expose only output-affecting identity; API keys
and transport credentials are excluded. On a miss, a temporary supervised sink forwards provider
PCM to the caller while collecting at most the configured bounds, then inserts only a complete,
supported linear16 asset. On a hit, the ordinary temporary playback worker supplies that asset to
the caller without another synthesis request. Cache insertion still does not open caller input;
only the destination sink's correlated playout-completion acknowledgement does that.

## Alternatives rejected

- A single untagged string is ambiguous between fixed text and a URL and cannot evolve safely.
- Accepting both text and URL and choosing one by precedence hides definition mistakes.
- LLM-generated notices are nondeterministic and can change the meaning of a fixed opening.
- Inheriting the initial agent's TTS couples call-level playback to an optional participant.
  Requiring an independent inline selection makes human entry work and prevents implicit voice selection.
- Releasing input on synthesis or enqueue completion is too early; the caller may still be
  hearing the opening.
- Buffering caller media during the opening would later submit speech uttered before consent
  or admission and would make the visible gate misleading.

## Implications

The definition parser owns syntax and source safety. The implemented asset layer separates DNS
resolution/address policy, bounded HTTP fetching, WAV decoding, and cache ownership. A temporary
worker under the room capability supervisor owns file preparation, bounded output, and playback
tracking. A separate text-preparation boundary owns rendered-asset lookup and synthesis submission,
while a temporary sink owns bounded collection. `RoomAuthority` owns only the opening gate and
correlated outcome decision; it does not fetch, decode, cache, synthesize, or push opening media.

## Verification

The tenant-opening checkpoint exercises real encrypted provisioning, save/publish/prepare/claim,
and in-process Deepgram speech adapters for a human-entry call. It checks the independent opening
key and caller STT key, exact private PCM on initial and subsequent frames, actual playout gating,
opening capability cleanup, cache reuse, tenant/binding cache isolation, and rejection of a revoked
opening credential even with a populated cache. Existing Engine tests cover synthesized, cached
and file openings while retaining conversation scope for the later agent greeting. See the
[tenant-opening labnotes](../labnotes/20260915-2039-tenant-opening-credentials.md) for results.

The following evidence predates the inline-schema migration and describes the earlier profile
representation; its lifecycle and privacy requirements still apply.

The independent-opening checkpoint adds native WebRTC regressions with model construction held:
a delayed file fetch and a separately prepared opening voice both produce decoded wait → notice →
wait audio before model construction is released. The engine-level PCM check proves the resumed
wait starts at its next segment in the same episode. Existing tests cover caller targeting, a
human entry receiver, separate voice profiles, cache reuse, recording and input isolation, required
opening failure, and exactly-once fixed greeting history. See the
[checkpoint labnote](../labnotes/20260914-2319-independent-opening-audio.md) for final checks and
fixture changes required by independent initialization.

The 2026-09-14 regressions prove explicit profile resolution for a human initial receiver,
rejection of absent/malformed/unknown/wrong-kind references, independent opening/greeting voices,
opening TTS cleanup, and cache isolation across configured profile references. The recording
regression initially delivered both full-mix and individual-track audio during the notice; it now
delivers neither, discards delayed held frames, and records subsequent audio normally. The
prepared-call persistence check reloads the pinned opening profile and options unchanged.
Commands and final gate results are in the [implementation labnote](../labnotes/20260913-2345-opening-tts-recording.md).

Earlier implementation evidence:

The compiler contract is covered by `opening_audio_compiler_test.exs`: missing runtime type and
schema-version assertions were observed red first, then 2 focused tests passed. The fixed-text
runtime is covered by `opening_audio_room_test.exs`: its first run failed because no synthesis was
started, then passed for real playout gating, required-playback failure, and pre-room rejection of
invalid text configuration. The file-room red run failed at the runtime's explicit file rejection;
the completed focused file passed 9 tests covering the supervised no-TTS file path, independence
from an unrelated TTS failure, caller input suppression through actual sink completion, and
controlled preparation failure. The asset-pipeline tests first failed because no typed asset
existed, then passed with 5 tests covering strict decode/
duration checks, public-address policy, bounded LRU/tenant keys, invalid cache limits, and fetch-
validate-cache reuse. Generated-text cache coverage first failed because a second call submitted
another TTS request. It now proves that the first call renders normally and a later same-tenant,
same-text, same-voice call reuses the bounded PCM asset, while digest tests distinguish tenant,
text, and output identity and retain none of their source values. The focused opening/asset files
passed 16 tests. A final caller-target test attaches the receiving agent first and observes no
opening output, then proves only the entry caller sink receives it. Runtime telemetry tests first
failed because no terminal opening observation existed; successful playout and controlled provider
failure now emit one payload-free duration/count event with only closed source/outcome metadata.
Console diagnostics projects that event into bounded source/outcome timings and counts without
retaining call identity or content. The complete Call Engine suite passed with 259 tests and one
integration exclusion; Console passed 57 tests. The production HTTPS fetch path has no live-network
assertion in the default suite; interoperability belongs in an explicitly tagged integration lane.
