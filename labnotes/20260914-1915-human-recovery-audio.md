# Human recovery audio

- Continued the human-web delivery slice after committing the verified stale-policy retry as
  `ab1d965`. The other agent's docs site and visual labnotes remain separate.
- Exercised the actual running `/pipecat-console` and `/transfer` in isolated headless Chrome
  sessions using agent-browser, at 1440×900 and 390×844. No development server restart, production
  configuration change, admission mock or provider mock was used. Live model and Deepgram services
  completed two accepted handoffs. The desktop stayed connected; the desk showed preparation,
  connection cue, release and activation, with readable controls and no horizontal overflow.
- For the second handoff, browser-only instrumentation supplied silence and then synthesized test
  speech through a real Web Audio microphone stream. It observed real RTCPeerConnection tracks and
  control messages. Both browsers decoded the 1 kHz cue. Support speech reached the caller's remote
  audio and appeared as live partial and final Deepgram transcription: “Hello. This is human support.
  Your transfer is connected. Can you hear me clearly?” A caller response produced audio on the
  desk and a final caller transcript. This verifies browser/media/provider integration, not physical
  phone audibility, custom live URL retrieval or complete model-history/recording isolation.
- Evidence retained locally: `vxpipe-human-live-{caller,desk}-probe.json`, the ready/active mobile
  screenshots and `vxpipe-human-live-transcript-desktop.png`. Screenshots were inspected visually.
  Probe files contain only controlled test speech, event categories, relative times and audio
  measurements; no admission tokens or provider credentials were collected in them.
- A third call exposed a real recovery defect. Reloading the desk after briefing but before acceptance
  produced the recovery cue and the assistant's failure response text. About nine seconds later the
  caller disconnected. Diagnostics recorded a Deepgram TTS output failure. This invalidates a claim
  that the rendered recovery passed; the retry could not proceed after that disconnect.
- The original automated recovery cases used `audio_response: false`. Strengthened their actual
  WebRTC path to request speech, feed the retained TTS transport audio and require decoded speech
  plus playback completion before another caller turn. All three cases failed at the audio output
  acknowledgement (`vxpipe-human-recovery-audio-red.log`). The source TTS request still stamped
  generation zero after the output had advanced its hold/recovery generation.
- Implemented fix: record the acknowledged release generation on affected engine connections,
  capture it in each new TTS request, and retain that value on its audio frames. Apply the same
  bookkeeping on successful transfer release. Do not relabel arbitrary arriving frames with the
  latest generation: old frames must remain stale. No output or provider needs a restart.
- Fixture correction after the first implementation run: a single 20 ms tone does not establish
  steady decoded Opus audio because of codec priming. Use 100 ms and issue provider completion
  before awaiting decoded audio. The initial generation failure had already been reproduced.
- Browser tooling detour: a DOM wait incorrectly assumed the voice kit used paragraph elements;
  waiting commands serialized subsequent commands. Inspected the existing browser through its
  CDP endpoint, confirmed the create-room screen, stopped only owned waiting CLI processes and
  closed all three owned browser sessions. The delayed disconnect is independently recorded in
  the retained peer events and diagnostics; it was not inferred from the failed DOM wait.

- All three strengthened recovery cases pass (`vxpipe-human-recovery-audio-green.log`): acknowledged
  TTS audio reaches the real WebRTC peer as a 1,500 Hz tone, finishes playback and permits the next
  caller turn. The same source TTS transport, caller output, room input and room output remain.
- Live browser recheck now receives both the spoken recovery response and a second requested
  response, “I am still here and ready to help.” The original WebRTC peer remains connected past
  the former failure point. `vxpipe-human-recovery-fixed-probe.json` records both speech start/stop
  sequences and remote audio; `vxpipe-human-recovery-fixed-desktop.png` captures the chat.
- Verification detour: starting the root development compile alongside a Phoenix browser request
  raced protocol consolidation in the shared `_build/dev/consolidated` directory. The root compile
  failed writing its beam files; this was not a compiler warning in the change. Finish browser work
  first, then rerun the required root gates sequentially without concurrent reload requests. No
  dependency cleaning, version change or running server restart is needed.

- Two subsequent transfer attempts in the recovered live call failed before desk media negotiation:
  `/sample/transfers` could not issue another admission. Inspection finds the exact restriction in
  `CallStore.admission_available/3`: any existing admission row for that call/participant prevents
  another token, backed by a unique call/participant index. No admission release lifecycle currently
  distinguishes a failed private connection. Preserve single-use tokens and concurrent exclusion
  when addressing this next; do not delete history or bypass the admission boundary in the UI.
- The recovery fix is kept as a separate usable checkpoint. The milestone records the admission
  defect and leaves the full human slice open. All owned browser sessions and waiting CLI processes
  were closed; no user browser or development server was restarted. No UI changes were required.
- `vxpipe-human-browser-evidence.json` validates retained probe files: caller/support each have one
  connected peer, both detect the 1 kHz cue, support receives caller speech after activation, and the
  caller receives the two final test transcripts. The fixed recovery has two completed speech
  windows with 146 and 48 non-silent audio measurements respectively on the same connected peer.

- Final verification passes formatting, warnings-as-errors compilation, strict Credo, all umbrella
  tests and unused dependencies. The final run has 1,295 tests, zero failures and 15 exclusions at
  concurrency four, seed 510739; logs and all-zero results are `vxpipe-human-recovery-audio-final-*`.
  This includes all 598 engine and 327 Gateway checks. Ninety-two local documentation link targets
  resolve. Only evidence/documentation edits followed the final code verification.
