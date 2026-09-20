defmodule Vxpipe.CallEngine.Capability.TextToSpeechSemanticTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.SpeechTTSAdmissionProbe
  alias Vxpipe.CallEngine.SpeechTTSUsageProbe
  alias Vxpipe.CallEngine.SpeechTTSCancellationProbe
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TextToSpeechRequest
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.Usage.ProviderContext
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession

  test "provider completion waits for sink acceptance and confirmed playout" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    :ok = TestAudioOutputSink.defer_finish(sink, true)
    capability = start_capability()

    assert {:ok, _resource, :ready} = await_ready(capability)

    request = request("turn-semantic", sink)
    assert :ok = TextToSpeech.synthesize(capability, request)
    assert_receive {:usage_probe_submitted, request_ref, _provider_request_id}
    assert is_reference(request_ref)
    assert_receive {:test_audio_output, ^sink, %{correlation_id: "turn-semantic"}}, 500

    provider = semantic_provider(capability)
    assert :ok = GenServer.call(provider, :complete)
    assert_receive {:test_audio_output_finish, ^sink, "turn-semantic"}
    refute_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}

    :ok = TestAudioOutputSink.complete_finish(sink)
    refute_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}
  end

  test "accepted cancellation retains its request identifier until the matching terminal" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    capability =
      start_capability(
        provider: SpeechTTSCancellationProbe,
        provider_private: [observer: self(), order: :callback_first]
      )

    assert {:ok, _resource, :ready} = await_ready(capability)
    first = request("turn-cancelled", sink)
    replacement = request("turn-replacement", sink)
    assert :ok = TextToSpeech.synthesize(capability, first)
    assert_receive {:probe_speak, first_reference}

    interruption = Task.async(fn -> TextToSpeech.interrupt(capability) end)
    assert_receive {:probe_cancel, ^first_reference, %{request_played_ms: 0}}
    assert Task.await(interruption, 500) == {:ok, [{first, 0}]}

    state = :sys.get_state(capability)
    assert is_reference(state.cancellation.request_id)
    assert state.cancellation.accepted?
    refute state.cancellation.terminal?

    assert :ok = TextToSpeech.synthesize(capability, replacement)
    refute_receive {:probe_speak, _replacement_before_terminal}

    provider = semantic_provider(capability)
    assert :ok = GenServer.call(provider, :emit_cancelled)
    assert_receive {:probe_speak, replacement_reference}
    refute replacement_reference == first_reference
  end

  test "interrupt after provider completion releases a queued replacement" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    :ok = TestAudioOutputSink.defer_finish(sink, true)
    capability = start_capability()
    assert {:ok, _resource, :ready} = await_ready(capability)

    first = request("turn-completed-interrupt", sink)
    replacement = request("turn-after-completed-interrupt", sink)
    assert :ok = TextToSpeech.synthesize(capability, first)
    assert_receive {:usage_probe_submitted, first_reference, _provider_request_id}
    assert_receive {:test_audio_output, ^sink, _frame}
    assert_receive {:usage_probe_audio_credited, ^first_reference, _credit}
    assert :ok = GenServer.call(semantic_provider(capability), :complete)
    assert_receive {:test_audio_output_finish, ^sink, "turn-completed-interrupt"}

    assert {:ok, [{^first, 0}]} = TextToSpeech.interrupt(capability)
    assert :ok = TextToSpeech.synthesize(capability, replacement)
    assert_receive {:usage_probe_submitted, _replacement_reference, _provider_request_id}
  end

  test "accepted cancellation drains held sink output before starting a replacement" do
    sink = start_supervised!({TestAudioOutputSink, observer: self(), block_output: true})
    capability = start_capability()
    assert {:ok, _resource, :ready} = await_ready(capability)

    first = request("turn-held-output", sink)
    replacement = request("turn-after-held-output", sink)
    assert :ok = TextToSpeech.synthesize(capability, first)
    assert_receive {:usage_probe_submitted, _first_reference, _provider_request_id}

    assert_receive {:test_audio_output, ^sink, %{correlation_id: "turn-held-output"}}

    interruption = Task.async(fn -> TextToSpeech.interrupt(capability) end)
    assert_receive {:test_audio_output_interrupt, ^sink, "turn-held-output", 0}
    assert Task.await(interruption, 500) == {:ok, [{first, 0}]}

    assert :ok = TextToSpeech.synthesize(capability, replacement)
    assert_receive {:usage_probe_submitted, _replacement_reference, _provider_request_id}
    assert_receive {:test_audio_output, ^sink, %{correlation_id: "turn-after-held-output"}}
    refute_receive {:test_audio_output, ^sink, %{correlation_id: "turn-held-output"}}
  end

  test "retains accepted usage when the speech allocation closes before acknowledgement" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    capability =
      start_capability(
        provider: SpeechTTSAdmissionProbe,
        provider_private: [observer: self(), admission_mode: :accept, emit_interval_ms: 0],
        usage: usage_context()
      )

    assert {:ok, _resource, :ready} = await_ready(capability)
    monitor = Process.monitor(capability)
    assert :ok = TextToSpeech.synthesize(capability, request("turn-usage-failure", sink))
    assert_receive {:tts_acceptance_held, _reference}

    %{session: session} = :sys.get_state(capability)
    provider = Session.provider(session)
    allocation_tree = Session.tree(session)
    allocation_monitor = Process.monitor(allocation_tree)

    :ok = :sys.suspend(capability)

    try do
      send(provider, :release_acceptance)
      _ = :sys.get_state(provider)
      Process.exit(allocation_tree, :kill)
      assert_receive {:DOWN, ^allocation_monitor, :process, ^allocation_tree, :killed}
    after
      :ok = :sys.resume(capability)
    end

    assert_receive {:vxpipe_usage_observations, ^capability, [observation]}
    assert observation.outcome == :failed
    assert observation.measurement.component == "input_characters"
    assert observation.measurement.quantity == 1
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}
  end

  test "room and capability supervisors never retain private provider initialization" do
    sentinel = "tts-tree-private-init-sentinel"
    incarnation_id = "incarnation-private-#{System.unique_integer([:positive])}"

    room_supervisor =
      start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation_id})

    assert {:ok, capability} =
             RoomCapabilitySupervisor.start_text_to_speech(
               incarnation_id,
               self(),
               "agent-private",
               {MorseSession, []},
               [secret: sentinel, emit_interval_ms: 0],
               1
             )

    tree = Tree.parent(capability)

    for process <- [room_supervisor, tree] do
      refute inspect(:sys.get_status(process), limit: :infinity, printable_limit: :infinity) =~
               sentinel
    end
  end

  defp start_capability(options \\ []) do
    provider = Keyword.get(options, :provider, SpeechTTSUsageProbe)
    provider_private = Keyword.get(options, :provider_private, observer: self())

    {:ok, private_init} = PrivateInit.open(provider_private, 5_000)

    tree =
      try do
        start_supervised!(
          {Tree,
           owner: self(),
           participant_id: "agent-semantic",
           provider: {provider, []},
           provider_private: private_init,
           maximum_requests: 1,
           usage: Keyword.get(options, :usage),
           name:
             {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, self(), make_ref()}}}}
        )
      after
        PrivateInit.close(private_init)
      end

    Tree.capability(tree)
  end

  defp semantic_provider(capability) do
    capability
    |> :sys.get_state()
    |> Map.fetch!(:session)
    |> Vxpipe.CallEngine.Speech.Session.provider()
  end

  defp await_ready(capability) do
    case TextToSpeech.readiness(capability) do
      {:ok, _resource, :preparing} ->
        _ = :sys.get_state(capability)
        await_ready(capability)

      result ->
        result
    end
  end

  defp request(correlation_id, sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-semantic",
      source_participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: correlation_id,
      output_id: "output-test",
      text: "E",
      output_sink: sink
    }
  end

  defp usage_context do
    {:ok, provider} =
      ProviderContext.new(
        name: "morse_code",
        integration_id: "semantic-test",
        model: "morse_code"
      )

    [call_id: "call-semantic", activation_id: "activation-semantic", provider: provider]
  end
end
