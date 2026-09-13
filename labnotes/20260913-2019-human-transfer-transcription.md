# Human transfer transcription

## Findings and decision

- Report: support audio reached the caller after transfer, but its transcription never appeared
  in `/pipecat-console`.
- The development definition already configured STT for the destination. Human preparation
  resolved its connection/briefing but omitted its STT runtime. Main promotion consequently
  enabled room mixing while leaving the destination's STT ingress nil.
- Room transcript routing already authorized recipient connections, but the Gateway discarded
  `ParticipantTranscription` events whose source connection differed from its own.
- Preserve destination STT configuration during preparation/commit. Start it after main admission
  from the owning web/phone connection, outside room authority and the policy barrier. Reuse the
  existing supervised provider startup, policy binding, usage attribution, and cleanup path.
  Repeated activation returns the existing ingress; private, forged, or foreign-owner calls reject.
- Forward room-authorized transcripts at main WebRTC connections, checking tenant, room, and
  incarnation identity. Preserve the source participant ID in RTVI. No SDK or UI change is needed.
- Refactored the shared STT startup helper to return only its ingress; unrelated audio input/output
  modes remain the attachment caller's responsibility.

## Red/green evidence

- The real two-peer Gateway transfer check failed red waiting for destination STT startup after
  `transfer.active`; private briefing and main audio already worked.
- The focused engine check failed red because post-admission STT activation did not exist. It
  now proves private preparation rejection, successful activation, instance reuse, and actor/process
  ownership. All six human web transfer room checks pass.
- An initial fixture run exposed incomplete test provider configuration; supplying the existing
  fake transport/provider options corrected the fixture without adding a production fallback.
- The Gateway check now passes with destination RTP reaching its configured STT transport and
  partial/final support transcripts arriving on the caller's actual WebRTC data channel with the
  destination `user_id`.

## Rendered browser evidence

- Used an isolated development VM on localhost port 4010; the user's running server was untouched.
  Live provider calls used the configured Gemini/Deepgram integrations.
- An initial attempt exceeded the unchanged 30-second transfer deadline while browser inspection
  delayed acceptance. A subsequent fast acceptance reached `Main room active`.
- Chrome's file-based fake microphone produced silence (confirmed using an audio analyser), so
  that run verified recognizer startup but could not verify recognition. Replaced only the browser
  fixture with a Web Audio microphone stream containing synthesized speech and silence.
- One fixture attempt disconnected shortly after promotion without a captured cause. The next
  instrumented attempt succeeded: support speech beginning “Hello. This is human support. I can
  help with your order.” appeared in the caller conversation after acceptance, and both peers
  stayed connected through the final inspection. No abnormal process exit was captured in that run.
- Inspected the rendered caller at 1280×720 and destination at 390×844. The caller shows recognized
  support speech using Pipecat's existing `user` label; destination shows `Main room active` and
  the completed control ledger. Browser artifacts remain in ignored diagnostic scratch storage.
- Closed both diagnostic browsers and stopped only the isolated VM after verification.

## Completion checks

- Two initial full-suite runs, concurrent with diagnostic Chrome/provider activity, failed only
  the existing asynchronous recording check: first its 100 ms policy call, then its 1-second mixer
  call. That check passed alone and in a later full run. Subsequent heavily loaded runs also hit
  MCP connection setup and billing fixture timing. A separate fixture checkpoint separates MCP
  setup from the 100 ms invocation assertion and aligns recording setup with the existing 1-second
  enforcement budget. It leaves production timing unchanged.
- The host reported a load average above 10, with substantial browser and filesystem activity.
  The final full run uses four concurrent test modules at the same seed, instead of the default 16.
- Final umbrella suite: 1,007 tests, zero failures, 15 integration cases excluded with
  `MIX_ENV=test mix test --seed 633343 --max-cases 4`. The focused checks and rendered browser
  evidence above also pass. Formatting, warnings-as-errors compilation, strict Credo, unused
  dependency checking, and changed-document link checks pass.
