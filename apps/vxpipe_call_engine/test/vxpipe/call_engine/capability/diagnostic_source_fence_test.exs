defmodule Vxpipe.CallEngine.Capability.DiagnosticSourceFenceTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Speech.CapabilityTree
  alias Vxpipe.CallEngine.SpeechSessionProbe
  @projection __MODULE__.Projection

  setup do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: @projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :loaded)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(@projection)
    :ok
  end

  test "source change fences reused inference before provider admission returns" do
    {capability, generation, frame} = capability()
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    observer = self()
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    caller =
      Task.Supervisor.async_nolink(tasks, fn ->
        result = SpeechToText.push_audio(capability, %{frame | source_epoch: make_ref()})
        send(observer, {:input_returned, result})
      end)

    assert_receive {:probe_input, recognizer}, 1_000
    :erlang.suspend_process(capability)

    try do
      send(recognizer, :release_input)
      assert_receive :classified, 1_000
      # The source is fenced while the caller is still suspended waiting for
      # admission, before any result can be accepted by the old observer.
      refute CaptureHandoff.current?(handoff)
    after
      :erlang.resume_process(capability)
    end

    assert_receive {:input_returned, :ok}
    Task.await(caller)
  end

  defp attach(capability, generation, frame, handoff),
    do:
      SpeechToText.attach_diagnostics(
        capability,
        generation,
        %{track_id: frame.track_id, source_epoch: frame.source_epoch},
        handoff
      )

  defp handoff(owner, options \\ []) do
    assert {:ok, handoff} =
             CaptureHandoff.new(
               self(),
               options |> Keyword.put(:projection, @projection) |> Keyword.put(:owner, owner)
             )

    handoff
  end

  defp capability(options \\ []) do
    parent = self()

    classify = fn _model, stream, audio ->
      if audio == :binary.copy(<<0>>, 1_024) do
        {:ok, stream, []}
      else
        send(parent, :classified)
        count = div(byte_size(audio), 1_024)
        {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.9, count)}
      end
    end

    initial = Keyword.get(options, :initial_policy, policy(0, ["human"]))
    incarnation = Keyword.get(options, :incarnation_id, "incarnation")
    tree = start_supervised!({CapabilityTree, owner: self()})

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: incarnation,
         participant_id: "human",
         connection_id: "connection",
         speech_scope: CapabilityTree.scope(tree),
         provider:
           {Vxpipe.CallEngine.Speech.ConversationalSTT,
            [provider: SpeechSessionProbe, options: [sample_rate: 16_000], vad: true]},
         provider_private: [
           recognizer: SpeechSessionProbe,
           recognizer_options: [sample_rate: 16_000],
           recognizer_private: [observer: self(), hold_input?: true, input_result: :ok],
           activity_options: [load: fn -> {:ok, :model} end, classify: classify]
         ],
         initial_policy: initial}
      )

    assert_receive {:probe_initializing, _, _}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert :ok = Enforcer.apply(capability, initial, 1_000)
    assert {:ok, %{allocation_generation: generation}} = SpeechToText.input_binding(capability)

    frame = %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: incarnation,
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      source_epoch: make_ref(),
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      payload: :binary.copy(<<1, 0>>, 2_048),
      received_at: System.monotonic_time(:millisecond)
    }

    {capability, generation, frame}
  end

  defp policy(revision, participants),
    do: %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(participants),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }
end
