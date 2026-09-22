# STS Google wire audit

## Scope

Read-only parent review of the private Google setup checkpoint `dd501d39` while
the main `4f5d2fb1` root gate runs. The reviewed setup uses text Content parts,
JSON-schema function declarations and nested realtime input configuration, in
agreement with the current official references. Initial and resumed fake-socket
tests preserve exactly the same private configuration. Shared MCP execution and
nonblocking tool continuation remain separate milestone work.

## Additional provider-controller finding

The existing decoder consumes boolean `serverContent.activityStart` and
`activityEnd`; `STSSession` ignores input/output transcripts and audio until an
input turn exists. The official SDK's server message instead exposes top-level
`voiceActivity`, whose `voiceActivityType` is `ACTIVITY_START` or `ACTIVITY_END`.
Added a specific subtask beneath the already-open Google controller-ordering gate
before probing or implementation. Existing manually injected onset fixtures are
not evidence that real provider-controlled calls work.

Primary sources checked on 2026-09-22:

- [Live WebSocket reference](https://ai.google.dev/api/live): input activity signals
  are client `realtimeInput` messages; server model `turnComplete` finishes the
  model response, not the caller turn. Output transcription precedes generation
  completion/interruption but is not strictly ordered against audio chunks.
- [Function declarations](https://ai.google.dev/api/generate-content#FunctionDeclaration):
  object JSON Schema is supported in `parametersJsonSchema`.
- [Official SDK server message](https://googleapis.github.io/js-genai/release_docs/classes/types.LiveServerMessage.html),
  [voice activity fields](https://googleapis.github.io/js-genai/release_docs/interfaces/types.VoiceActivity.html),
  and [activity types](https://googleapis.github.io/js-genai/release_docs/enums/types.VoiceActivityType.html).

This is a wire-contract audit, not hosted protocol availability evidence. The
SDK separately labels `voiceActivityDetectionSignal` allowlisted-only; do not
assume its availability or conflate it with `voiceActivity`. Verify actual
supported profile, ordering and duplicate handling before enabling Google STS.

## Reproduction

Against the existing compiled `4f5d2fb1` test artifacts, both supported enum
values in the documented envelope decode to `{:ok, []}`. No socket, credential,
Mix compilation or external call was involved:

```sh
ERL_FLAGS='+S 2:2' elixir -e '
Code.prepend_paths(Path.wildcard("_build/test/lib/*/ebin"))
for signal <- ["ACTIVITY_START", "ACTIVITY_END"] do
  payload = JSON.encode!(%{"voiceActivity" => %{
    "voiceActivityType" => signal, "audioOffset" => "0.100s"
  }})
  IO.inspect({signal, Vxpipe.Providers.Google.STS.decode(payload)})
end'
```

Permanent decoder/session/controller regressions and repair remain the explicit
next controller checkpoint. Do not claim that this probe verifies a live model,
or change caller speech semantics merely to make existing fake fixtures pass.
