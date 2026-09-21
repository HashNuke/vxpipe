# Deepgram capability names and TTS voice selection

Deepgram's registered speech APIs are `Vxpipe.Providers.Deepgram.STTSession` and
`Vxpipe.Providers.Deepgram.TTSSession`. Their identity is the capability, not the currently
supported Flux model family. The private Flux decoders still describe the actual `/v2/listen`
and `/v2/speak` wire protocols; this change does not claim Nova or Aura support.

For Flux TTS, a call spec can select a voice without assembling Deepgram's model ID:

```elixir
%{
  provider: "deepgram",
  model: "flux",
  options: %{voice: "haley"}
}
```

The Deepgram provider validates the voice token and builds `flux-haley-en` for the `/v2/speak`
connection. Its descriptor, usage model and audio cache identity continue to use that resolved
model, so changing the voice changes the correct output identity. The adapter defaults to 48 kHz
mono linear16; a call spec can still select a supported output rate. The [Deepgram Flux TTS voice
catalog](https://developers.deepgram.com/docs/flux-tts/voices) defines the current
`flux-{voice}-en` wire format. This adapter currently supports Flux English voices only; a
well-formed voice name is not proof that Deepgram offers that voice to the account.

Explicit full model selectors remain valid as a first-class call-spec form. Published call-spec
revisions are immutable and may already contain `model: "flux-haley-en"`; rejecting that form
would break historical revisions. A selection must use either the family plus `voice` or a full
model ID without `voice`, so there is no ambiguous override. Both resolve through the same
Deepgram semantic session and socket. No older execution path or provider fallback exists.

We rejected model-family names in the registered session modules because each new model would
force a call-engine API change. We also rejected rewriting stored call-spec revisions to the new
form because that would alter published source history without improving running calls. Voice
selection is an additive call-spec contract with one provider-owned model construction rule.

Verification: the voice-selection test first failed on the unsupported call spec, then passed
after provider translation. It checks `flux` plus `haley` resolves to `flux-haley-en`, invalid
voice input fails, and the WebSocket URL uses the derived model. The inline activation test
passes the voice selection through credential resolution and retains the same public descriptor.
The demo sample test similarly went red, then green when its specs used the new selection. The
existing explicit-model tests continue to pass. The [speech provider milestone](milestones/rime-and-google-speech-providers.md)
tracks remaining umbrella and bounded-load acceptance.
