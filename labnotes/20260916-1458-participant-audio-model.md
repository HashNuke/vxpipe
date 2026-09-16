# Participant audio model

## Question

Should browser or phone audio input appear as an `AudioInput`/`Voice` participant capability in the console?

## Findings

- `CallDefinition.Capabilities` currently accepts only `speech_to_text`, `model_inference`, and `text_to_speech`.
- A human participant owns a separate `ConnectionIntent` whose service and mode describe WebRTC or telephony admission.
- `Readiness.Inventory.connection_demands/4` derives `audio_input?` and `room_output?` from the connected human role, effective media policy, routes, and recording targets. It derives `speech_to_text?` independently and only when that participant selected STT and policy requires it.
- WebRTC and telephony readiness tests demand audio input and room output with STT either true or false. Transferred human tests use the same separation.

## Decision

- Do not invent an `AudioInput` or `Voice` capability in the client projection.
- Display WebRTC or the E.164 number as connection information in the participant rail.
- Display STT only when it is configured for that human participant. The prototype's transferred support participant uses the same configured Deepgram STT selection as the representative backend transfer definition.

## Red/green evidence

- Red: the focused React test found `Voice / Browser / WebRTC` in support's capability details and could not find `Speech to text`.
- Green: the focused contract test passed, followed by all 23 frontend tests and `npm run check`.
- Browser: inspected the human-handoff story at 1280×900. The support rail row shows `WebRTC`; its participant details show only `Speech to text / Deepgram / flux-general-en` under Capabilities.
