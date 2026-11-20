defmodule Vxpipe.CallEngine.Capability.TextToSpeechDiagnosticsTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.{SpeechTTSUsageProbe, TestAudioOutputSink, TextToSpeechRequest}
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

  test "stop evidence belongs to the new human and precedes provider cancellation" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(provider_private: [observer: self(), hold_cancel?: true])
    assert {:ok, _, :ready} = await_ready(capability)
    old = request("old-human-turn", sink)
    assert :ok = TextToSpeech.synthesize(capability, old)
    assert_receive {:usage_probe_submitted, reference, _}
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:usage_probe_audio_credited, ^reference, _}
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
    assert {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)
    generation = make_ref()
    turn_ref = make_ref()
    context = {handoff, generation, turn_ref, "new-human-turn", "new-command"}
    parent = self()

    start_supervised!(
      {Task,
       fn ->
         send(parent, {:interrupted, TextToSpeech.interrupt_observed(capability, context)})
       end}
    )

    assert_receive {:usage_probe_cancel_held, provider, ^reference}, 500
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message

    assert {:ok,
            {:barge_in_playback, ^generation, ^turn_ref, "new-human-turn", "new-command",
             {"agent-semantic", "human-test", "connection-test", "old-human-turn", "command-test",
              "output-test"}, started, requested, stopped, nil}, charge} =
             CaptureHandoff.message(handoff, message)

    assert started <= requested
    assert requested <= stopped
    assert stopped <= System.monotonic_time(:microsecond)
    refute_receive {:interrupted, _}, 0
    :ok = CaptureHandoff.release(handoff, charge, :processed)
    send(provider, :release_usage_probe_cancel)
    assert_receive {:interrupted, {:ok, [{^old, 0}]}}, 500
  end

  for scenario <- [:unstarted, :wrong_turn, :revoked] do
    @tag scenario: scenario
    test "#{scenario} interruption does not fabricate available playback evidence", ctx do
      scenario = ctx.scenario
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      capability = start_capability(provider_private: [observer: self(), hold_cancel?: true])
      assert {:ok, _, :ready} = await_ready(capability)
      old = request("old-turn", sink)
      assert :ok = TextToSpeech.synthesize(capability, old)
      assert_receive {:usage_probe_submitted, reference, _}
      assert_receive {:test_audio_output, ^sink, _}
      assert_receive {:usage_probe_audio_credited, ^reference, _}

      if scenario != :unstarted do
        assert :ok = TestAudioOutputSink.playback_started(sink)
        assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
      end

      if scenario == :wrong_turn, do: TestAudioOutputSink.playback_completed(sink)
      assert {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)
      if scenario == :revoked, do: CaptureHandoff.close(handoff)
      context = {handoff, make_ref(), make_ref(), "new-turn", "new-command"}
      parent = self()

      start_supervised!(
        {Task,
         fn ->
           send(parent, {:interrupted, TextToSpeech.interrupt_observed(capability, context)})
         end}
      )

      assert_receive {:usage_probe_cancel_held, provider, ^reference}, 500

      if scenario == :revoked do
        refute_receive {:vxpipe_diagnostic_capture, _, _, _, _}, 0
      else
        assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
        assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)

        if scenario == :unstarted do
          assert elem(packet, 6) == nil
          assert elem(packet, 9) == :not_playing
        else
          assert elem(packet, 8) == nil
          assert elem(packet, 9) == :stop_unavailable
        end

        :ok = CaptureHandoff.release(handoff, charge, :processed)
      end

      send(provider, :release_usage_probe_cancel)
      assert_receive {:interrupted, {:ok, [{^old, 0}]}}, 500
    end
  end

  defp start_capability(options) do
    provider = Keyword.get(options, :provider, SpeechTTSUsageProbe)
    provider_private = Keyword.get(options, :provider_private, observer: self())

    {:ok, private_init} = PrivateInit.open(provider_private, 5_000)

    tree =
      try do
        tree_options =
          [
            owner: self(),
            participant_id: "agent-semantic",
            provider: {provider, []},
            provider_private: private_init,
            maximum_requests: Keyword.get(options, :maximum_requests, 1),
            usage: Keyword.get(options, :usage),
            name:
              {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, self(), make_ref()}}}
          ]
          |> maybe_put_output_request_timeout(options)

        start_supervised!({Tree, tree_options})
      after
        PrivateInit.close(private_init)
      end

    Tree.capability(tree)
  end

  defp maybe_put_output_request_timeout(tree_options, options) do
    case Keyword.fetch(options, :output_request_timeout) do
      {:ok, timeout} -> Keyword.put(tree_options, :output_request_timeout, timeout)
      :error -> tree_options
    end
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
end
