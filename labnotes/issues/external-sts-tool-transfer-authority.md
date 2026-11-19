# External STS tool-transfer authority

Status: reproduced, unresolved; found during participant VAD diagnostic acceptance
on 2026-11-19. This is an operational transfer issue, not a diagnostic ownership
requirement or permission to change turn-control behavior in that milestone.

## Evidence

A published call with Scribe human STT and Morse STS in external/hybrid control
accepts `TOOL transfer {"destination":"specialist"}`, then reports transfer
recovery/failure with `policy_changed` and may close with
`handoff_recovery_failed`. The destination is a configured fixture LLM agent.
The four external/hybrid × local-Silero off/on diagnostic attempt cases all failed
before a replacement Scribe session. Independent source review identified:

- Morse half-duplex stores the pending tool before returning from `push_text`.
  Its `input_quiescent?/1` requires no pending tools. The generic capability
  `SpeechToSpeech.Hold.hold/1` therefore closes with `unsafe_hold`.
- Independently, room `SpeechToSpeech.hold/2` stops external/hybrid capabilities.
  `ParticipantTransfer.prepared/3` revalidates through Authorizer, which requires
  the original selected capability. The cleared binding becomes
  `source_authority_changed`, publicly `policy_changed`.
- Existing successful native-transfer fixtures use Morse Duplex's mute hold.
  Duplex supports provider control only, so switching this fixture to Duplex
  would not verify external/hybrid behavior.

The VAD acceptance uses actual audio-policy route changes instead: these invoke
`SpeechToTextDemand.activity_authority_changed?/4`, replace the real STT allocation,
and prove diagnostic run boundaries. It does not claim this tool-transfer works.

## Focused reproduction

Use the existing fixtures in
`apps/vxpipe_console/test/integration/configured_latency_diagnostics_test.exs`.
Temporarily add the following before `Calls.save_call_spec` inside `call/3`:

```elixir
source =
  if scenario == {:sts_routing, "external"} do
    source
    |> put_in([:participants, "assistant", :transfers], ["specialist"])
    |> put_in([:participants, "specialist"], %{
      type: "agent", prompt: "Handle specialist requests.",
      first_message: %{mode: "wait_for_input"},
      capabilities: %{model_inference: %{provider: "fixture", model: "echo"}}
    })
  else
    source
  end
```

Add this temporary case in the same module:

```elixir
@tag matrix: true, mixed_sts: true, native_transfer_repro: true
test "external native tool transfer completes", c do
  {_call, _connection, attachment, _wire, _identity} =
    call(c.options, false, {:sts_routing, "external"})
  state = :sys.get_state(attachment.room_authority)
  assert :ok = CallEngine.Capability.SpeechToSpeech.push_text(
    state.speech_to_speech_capability.pid,
    ~s(TOOL transfer {"destination":"specialist"})
  )
  assert_receive {:vxpipe_event, %CallEngine.Event.ToolCallStarted{name: "transfer"}}, 2_000
  assert_receive {:vxpipe_event, %CallEngine.Event.ToolCallCompleted{name: "transfer"}}, 5_000
end
```

Run from the Console child:

```sh
mix test test/integration/configured_latency_diagnostics_test.exs --only native_transfer_repro
```

Independent review ran this exact recipe: the completion assertion failed (1/1);
transfer progress reported `policy_changed`, then recovery failed with
`speech_to_speech_unavailable` and `handoff_recovery_failed`. Use synthetic providers only. Remove the temporary fixture
edits after reproduction. A future fix needs an explicit safe hold/retirement and
transfer-authority contract with focused failure/recovery tests; do not bypass
source authorization or change operational turn acceptance to silence the test.
