# Speech model catalog

## Decision

Each speech session implements required `models/0`, alongside pure `configure/1`.
The session delegates to its existing pure configuration module when it has one;
that module uses the same declarations for model validation. The Call Engine owns
`Speech.Model` because it owns these behaviors. Provider manifests retain only
capability ownership, so the provider registry needs no new dependency.

Descriptors contain `id`, `name`, `default`, and `voices`. Exactly one model is
recommended. A voice descriptor is either a known list with one recommended entry
or free text with an explicit default; its `parameter` names the source option.
This preserves provider-specific option names, including Rime's `speaker`, without
teaching the editor wire formats. STT and Morse models have no voice selector.
An optional public `options` map supplies required selection defaults. Deepgram STT
declares `encoding: "linear16"` and `sample_rate: 48000`, so selecting its model
produces a runnable portable selection without provider-specific frontend logic.
These recommendations do not change existing saved selections or runtime fallbacks.

Deepgram exposes the public pseudo-model `flux` and a separate voice, as requested
by the user. This is already supported by the portable selection contract; the
adapter owns construction of `flux-{voice}-en`. Existing concrete IDs remain
accepted for lossless source compatibility. New editor selections use the public
model. Unknown public models are rejected. This is not a schema-version migration.

## Defaults and alternatives

Recommendations preserve onboarding's existing model choices. Flux's former
`flux-hannah-en` recommendation becomes `flux` plus `hannah`. Legacy configure
fallbacks remain unchanged, including Deepgram's English STT and Haley TTS.
Morse has no onboarding entry: recommend `morse` for native STT/TTS/STS and
`morse-duplex` for the separate duplex implementation.

Voice defaults use existing runtime/example choices: Cartesia's existing UUID,
ElevenLabs' existing voice ID, Google `Kore`, OpenAI `marin`, Rime `astra` and
Deepgram `hannah`. These adapters currently validate voice formats rather than a
closed inventory, so their descriptors use free text. No online voice catalog or
new provider acceptance claim is introduced.

A frontend-only model list was rejected because it can drift from validation.
Enumerating every Flux voice as a model was rejected because voices are open and
would leak provider naming into authoring. Changing saved IDs automatically was
rejected because the editor must preserve source digests. A required callback
makes a missing declaration a compile-time warning, caught by warnings-as-errors.

## Verification

The registry-driven contract checks every installed STT/TTS/STS implementation,
all native Morse implementations and the duplex namespace wrapper. It checks
non-empty lists, unique IDs, exactly one default, voice metadata, acceptance of
each declared model with its default voice and rejection of an unknown model.
Focused cases pin onboarding recommendations and public/legacy Flux conversion.
Execution evidence is recorded in the milestone and implementation labnote.
