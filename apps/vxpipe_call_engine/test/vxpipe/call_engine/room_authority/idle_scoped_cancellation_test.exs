defmodule Vxpipe.CallEngine.RoomAuthority.IdleScopedCancellationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{AgentOutput, State, TurnState}
  alias Vxpipe.CallEngine.Speech.{PrivateInit, Session}
  alias Vxpipe.CallEngine.{SpeechTTSCancellationProbe, TestAudioOutputSink, TextToSpeechRequest}

  test "Room idle cancellation retires only old speech and preserves its queued acknowledgment" do
    {capability, state, old, origin, old_request, acknowledgment} = setup_output()
    assert {:ok, after_idle} = AgentOutput.interrupt_idle(origin, state)
    assert_receive {:probe_cancel, old_reference, _}
    refute TurnState.active?(after_idle, old)
    assert TurnState.speech_targets(after_idle, origin) == [acknowledgment]
    assert :sys.get_state(capability).current.request == old_request
    refute_receive {:probe_speak, _}
    assert :ok = GenServer.call(provider(capability), :emit_cancelled)
    assert_receive {:probe_speak, acknowledgment_reference}
    refute acknowledgment_reference == old_reference
    assert :sys.get_state(capability).current.request == acknowledgment
  end

  test "a newer Room turn rejects stale idle without cancelling current or queued TTS" do
    {capability, state, _old, origin, old_request, acknowledgment} = setup_output()
    newer = command("newer")
    state = %{state | next_sequence: 3} |> TurnState.put(newer)
    assert {:error, :stale} = AgentOutput.interrupt_idle(origin, state)
    refute_receive {:probe_cancel, _, _}
    assert :sys.get_state(capability).current.request == old_request
    assert :queue.to_list(:sys.get_state(capability).pending) == [acknowledgment]
    assert TurnState.active?(state, newer)
  end

  defp setup_output do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    {:ok, private} = PrivateInit.open([observer: self(), order: :callback_first], 5_000)

    tree =
      try do
        start_supervised!(
          {Tree,
           owner: self(),
           participant_id: "agent",
           provider: {SpeechTTSCancellationProbe, []},
           provider_private: private,
           maximum_requests: 2,
           name: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, self()}}}}
        )
      after
        PrivateInit.close(private)
      end

    capability = Tree.capability(tree)
    assert {:ok, _resource, :ready} = await_ready(capability)
    old = command("old")
    origin = command("idle")
    old_request = request(old, sink)
    acknowledgment = request(origin, sink)
    assert :ok = TextToSpeech.synthesize(capability, old_request)
    assert_receive {:probe_speak, _reference}
    assert :ok = TextToSpeech.synthesize(capability, acknowledgment)

    state =
      State.new(
        %Recorder{port: nil, participant_activations: %{}},
        %Snapshot{
          tenant_id: "tenant",
          room_id: "room",
          incarnation_id: "incarnation",
          lifecycle: :open,
          created_by_actor_id: "actor",
          created_by_command_id: "command"
        },
        %{}
      )

    state = %{
      state
      | text_capability: %{module: :fixture, participant_id: "agent"},
        text_to_speech_capability: %{pid: capability},
        connections: %{"connection" => %{participant_id: "human", pid: self()}}
    }

    state =
      state
      |> TurnState.put(old)
      |> TurnState.admit_output(old)
      |> TurnState.begin_speech(old_request)

    state = TurnState.update(state, old, &%{&1 | generation_complete?: true})

    state =
      %{state | next_sequence: 2}
      |> TurnState.put(origin)
      |> TurnState.begin_speech(acknowledgment)

    {capability, state, old, origin, old_request, acknowledgment}
  end

  defp command(correlation) do
    {:ok, command} =
      SendText.new(
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        actor_id: "actor",
        participant_id: "human",
        connection_id: "connection",
        correlation_id: correlation,
        content: correlation,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    command
  end

  defp request(command, sink) do
    %TextToSpeechRequest{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: "agent",
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      output_id: command.correlation_id,
      text: "E",
      output_sink: sink
    }
  end

  defp provider(capability),
    do: capability |> :sys.get_state() |> Map.fetch!(:session) |> Session.provider()

  defp await_ready(capability) do
    case TextToSpeech.readiness(capability) do
      {:ok, _, :preparing} ->
        _ = :sys.get_state(capability)
        await_ready(capability)

      result ->
        result
    end
  end
end
