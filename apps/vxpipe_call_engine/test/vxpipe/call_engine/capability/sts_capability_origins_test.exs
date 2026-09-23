defmodule Vxpipe.CallEngine.Capability.STSCapabilityOriginsTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Speech.{PrivateInit, Session}
  alias Vxpipe.CallEngine.{SpeechContextProbe, TestAudioOutputSink}

  test "opted-in audio, typed text and activity share a pre-input origin until epoch changes" do
    capability = capability()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, first, {:audio, <<0, 0>>}, _}
    assert is_reference(first)

    assert :ok = SpeechToSpeech.push_text(capability, "hello")
    assert_receive {:context_input, ^first, {:text, text_ref, "hello"}, _}
    assert is_reference(text_ref)

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, ^first, {:activity, :started}, _}
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:context_input, ^first, {:activity, :ended}, _}

    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, second, {:audio, <<0, 0>>}, _}
    assert second != first
  end

  test "rejected first use retains no capability origin" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    assert :ok = GenServer.call(provider, {:configure_result, {:error, :busy}, false})
    assert {:error, :busy} = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, rejected, {:audio, <<0, 0>>}, _}
    assert :sys.get_state(capability).response_origins.accepted == %{}

    assert :ok = GenServer.call(provider, {:configure_result, :ok, false})
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, accepted, {:audio, <<0, 0>>}, _}
    assert accepted != rejected
    assert map_size(:sys.get_state(capability).response_origins.accepted) == 1
  end

  test "output-route revoke denies opted-in input and regrant creates a new origin" do
    capability = capability()
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, first, {:audio, <<0, 0>>}, _}

    base = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: unrestricted()
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, base})
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, ^first, {:audio, <<0, 0>>}, _}

    denied = %{base | revision: 1, effective: deny_output()}
    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, denied})
    assert {:error, :policy_denied} = SpeechToSpeech.push_text(capability, "denied")
    refute_received {:context_input, _, {:text, _, "denied"}, _}

    assert :ok =
             GenServer.call(capability, {:vxpipe_apply_media_policy, %{base | revision: 2}})

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, second, {:audio, <<0, 0>>}, _}
    assert second != first
  end

  test "interim origin retention is bounded without changing legacy input" do
    capability = capability()

    contexts =
      Enum.map(1..16, fn _index ->
        assert :ok = SpeechToSpeech.release(capability, make_ref())
        assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
        assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
        context
      end)

    assert length(Enum.uniq(contexts)) == 16
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert {:error, :busy} = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    refute_received {:context_input, _, {:audio, <<0, 0>>}, _}
  end

  test "a direct policy revoke and regrant cannot reuse an earlier snapshot origin" do
    capability = capability()

    snapshot = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: unrestricted()
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, snapshot})
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, first, {:audio, <<0, 0>>}, _}

    assert :ok = SpeechToSpeech.apply_policy(capability, deny_output())
    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, second, {:audio, <<0, 0>>}, _}
    assert second != first
  end

  test "output-only snapshot revoke and regrant changes the receiving human's origin interval" do
    capability = capability()

    base = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: restricted_both()
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, base})
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, first, {:audio, <<0, 0>>}, _}

    assert :ok =
             GenServer.call(
               capability,
               {:vxpipe_apply_media_policy, %{base | revision: 1, effective: deny_output()}}
             )

    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)

    assert :ok =
             GenServer.call(capability, {:vxpipe_apply_media_policy, %{base | revision: 2}})

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, second, {:audio, <<0, 0>>}, _}
    assert second != first
  end

  test "held direct opted-in activity cannot create an accepted origin" do
    capability = capability()
    assert :ok = SpeechToSpeech.hold(capability)
    assert {:error, :held} = SpeechToSpeech.input_activity(capability, :started)
    assert {:error, :held} = SpeechToSpeech.input_activity(capability, :ended)
    refute_received {:context_input, _, {:activity, _}, _}
    assert :sys.get_state(capability).response_origins.accepted == %{}
  end

  test "an acknowledged response start, not caller turn end, grants opted-in output" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    caller_turn = make_ref()

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended,
                turn_ref: caller_turn, text: "hello", endpointing: :provider_gap}
             )

    _ = :sys.get_state(capability)
    refute_received {:context_output_granted, ^caller_turn, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    assert_receive {:context_output_granted, ^turn, output_ref}
    assert is_reference(output_ref)
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^turn, _}
  end

  test "a response from a held origin is discarded by its exact reference" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    assert_receive {:context_response_discarded, ^turn}
    refute_received {:context_output_granted, ^turn, _}
  end

  test "late old-origin tool calls cannot inherit a new capability origin" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, old_context, {:audio, <<0, 0>>}, _}
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, current_context, {:audio, <<0, 0>>}, _}
    assert current_context != old_context

    current_call = make_ref()
    current_turn = make_ref()

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :tool_call,
                call_ref: current_call,
                turn_ref: current_turn,
                tool_name: "echo",
                arguments: %{},
                response_context: current_context}
             )

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent",
                    %{event: %{call_ref: ^current_call}}}

    old_call = make_ref()
    old_turn = make_ref()
    monitor = Process.monitor(capability)

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :tool_call,
                call_ref: old_call,
                turn_ref: old_turn,
                tool_name: "echo",
                arguments: %{},
                response_context: old_context}
             )

    assert_receive {:vxpipe_sts_unavailable, ^capability, :stale_tool_origin}, 1_000

    refute_received {:vxpipe_sts_tool_event, ^capability, "agent",
                     %{event: %{call_ref: ^old_call}}}

    assert_receive {:DOWN, ^monitor, :process, ^capability, :stale_tool_origin}, 1_000
  end

  test "external caller activity gates an opted-in response until accepted end" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, context, {:activity, :started}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    refute_receive {:context_output_granted, ^turn, _}, 50

    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:context_input, ^context, {:activity, :ended}, _}
    assert_receive {:context_output_granted, ^turn, _}
  end

  test "hold retires a queued response even while external activity remains unresolved" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, context, {:activity, :started}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    _ = :sys.get_state(capability)
    assert :ok = SpeechToSpeech.hold(capability)
    assert_receive {:context_response_discarded, ^turn}
    refute_received {:context_output_granted, ^turn, _}
  end

  test "a busy-slot response is discarded after hold and cannot replay on release" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    first = make_ref()
    second = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, first, 1})
    assert_receive {:context_output_granted, ^first, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, second, 2})
    _ = :sys.get_state(capability)
    refute_received {:context_output_granted, ^second, _}

    assert :ok = SpeechToSpeech.hold(capability)
    assert_receive {:context_response_discarded, ^second}
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    refute_received {:context_output_granted, ^second, _}
  end

  test "a queued response is discarded when output policy is revoked, not replayed on regrant" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, context, {:activity, :started}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    _ = :sys.get_state(capability)

    assert :ok = SpeechToSpeech.apply_policy(capability, deny_output())
    assert_receive {:context_response_discarded, ^turn}
    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    refute_received {:context_output_granted, ^turn, _}
  end

  test "a busy queued response retires when its direct policy revision changes" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    first = make_ref()
    second = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, first, 1})
    assert_receive {:context_output_granted, ^first, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, second, 2})
    _ = :sys.get_state(capability)

    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    assert_receive {:context_response_discarded, ^second}
    refute_received {:context_output_granted, ^second, _}
  end

  test "a queued response retries after the credited output settles" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    sink = :sys.get_state(capability).sink
    first = make_ref()
    second = make_ref()
    third = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, first, 1})
    assert_receive {:context_output_granted, ^first, output_ref}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^first, first_sequence}
    assert :ok = GenServer.call(provider, {:emit_response, context, second, 2})
    assert :ok = GenServer.call(provider, {:emit_response, context, third, 3})
    pending = :sys.get_state(capability).pending_turns

    assert [
             {:response, ^second, ^context, _, second_sequence},
             {:response, ^third, ^context, _, third_sequence}
           ] = pending

    assert first_sequence < second_sequence and second_sequence < third_sequence
    refute_received {:context_output_granted, ^second, _}
    refute_received {:context_output_granted, ^third, _}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_transcript, turn_ref: first, text: "first", final: true}
             )

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_completed, turn_ref: first, request_ref: output_ref}
             )

    assert_receive {:test_audio_output_finish, ^sink, _}
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:context_output_granted, ^second, second_output_ref}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^second, ^second_sequence}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^first, ^first_sequence}
    refute_received {:context_output_granted, ^third, _}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_transcript, turn_ref: second, text: "second", final: true}
             )

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_completed, turn_ref: second, request_ref: second_output_ref}
             )

    assert_receive {:test_audio_output_finish, ^sink, _}
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:context_output_granted, ^third, _}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^third, ^third_sequence}
  end

  test "replacing an input epoch retires its queued response" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, context, {:activity, :started}, _}
    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    _ = :sys.get_state(capability)

    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert_receive {:context_response_discarded, ^turn}
    refute_received {:context_output_granted, ^turn, _}
  end

  test "the bounded response queue recovers capacity after origin retirement" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, context, {:activity, :started}, _}

    turns =
      Enum.map(1..16, fn index ->
        turn = make_ref()
        assert :ok = GenServer.call(provider, {:emit_response, context, turn, index})
        turn
      end)

    assert :ok = SpeechToSpeech.hold(capability)

    Enum.each(turns, fn turn ->
      assert_receive {:context_response_discarded, ^turn}
    end)

    assert :sys.get_state(capability).pending_turns == []
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, fresh_context, {:audio, <<0, 0>>}, _}
    assert fresh_context != context
    fresh_turn = make_ref()
    assert :ok = GenServer.call(provider, {:emit_response, fresh_context, fresh_turn, 17})
    assert_receive {:context_output_granted, ^fresh_turn, _}
  end

  test "replacing an activity epoch does not gate a fresh response" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:context_input, old_context, {:activity, :started}, _}
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, fresh_context, {:audio, <<0, 0>>}, _}
    assert fresh_context != old_context

    assert :ok = GenServer.call(provider, {:emit_response, fresh_context, turn, 1})
    assert_receive {:context_output_granted, ^turn, _}
  end

  test "a reused supplied epoch after hold cannot revive an old response origin" do
    capability = capability()
    session = :sys.get_state(capability).session
    provider = Session.provider(session)
    epoch = session.generation
    turn = make_ref()

    assert :ok = SpeechToSpeech.release(capability, epoch)
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, epoch)

    assert :ok = GenServer.call(provider, {:emit_response, context, turn, 1})
    assert_receive {:context_response_discarded, ^turn}
    refute_received {:context_output_granted, ^turn, _}
  end

  test "provider-detected caller speech gates a same-origin response until its exact end" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    caller_turn = make_ref()
    other_turn = make_ref()
    response = make_ref()

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<0, 0>>)
    assert_receive {:context_input, context, {:audio, <<0, 0>>}, _}
    assert :ok = GenServer.call(provider, {:emit, :speech_started, turn_ref: caller_turn})
    _ = :sys.get_state(capability)
    assert :ok = GenServer.call(provider, {:emit_response, context, response, 1})
    _ = :sys.get_state(capability)
    refute_received {:context_output_granted, ^response, _}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended,
                turn_ref: other_turn, text: "other", endpointing: :provider_gap}
             )

    _ = :sys.get_state(capability)
    refute_received {:context_output_granted, ^response, _}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended,
                turn_ref: caller_turn, text: "caller", endpointing: :provider_gap}
             )

    assert_receive {:context_output_granted, ^response, _}
  end

  test "unresolved provider speech remains bounded when caller forwarding is suppressed" do
    capability = capability(caller_source: :human_stt)
    provider = Session.provider(:sys.get_state(capability).session)
    monitor = Process.monitor(capability)

    Enum.each(1..16, fn _index ->
      turn = make_ref()
      assert :ok = GenServer.call(provider, {:emit, :speech_started, turn_ref: turn})
      assert_receive {:vxpipe_sts_speech_started, ^capability, "agent", ^turn}, 1_000
    end)

    assert MapSet.size(:sys.get_state(capability).input_turns) == 16
    assert :ok = GenServer.call(provider, {:emit, :speech_started, turn_ref: make_ref()})
    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_caller_overflow}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :pending_caller_overflow}, 1_000
  end

  test "speech overflow cannot forward the rejected caller start to the room owner" do
    capability = capability()
    provider = Session.provider(:sys.get_state(capability).session)
    monitor = Process.monitor(capability)

    turns =
      Enum.map(1..16, fn _index ->
        turn = make_ref()
        assert :ok = GenServer.call(provider, {:emit, :speech_started, turn_ref: turn})
        assert_receive {:vxpipe_sts_input_event, ^capability, %{event: %{turn_ref: ^turn}}}, 1_000
        assert_receive {:vxpipe_sts_speech_started, ^capability, "agent", ^turn}, 1_000
        turn
      end)

    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    first = List.first(turns)

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :input_transcript, turn_ref: first, text: "stale", final: true}
             )

    rejected = make_ref()
    assert :ok = GenServer.call(provider, {:emit, :speech_started, turn_ref: rejected})
    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_caller_overflow}, 1_000
    refute_received {:vxpipe_sts_input_event, ^capability, %{event: %{turn_ref: ^rejected}}}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :pending_caller_overflow}, 1_000
  end

  test "framed input carries the accepted epoch's origin through the ingress boundary" do
    identity = %{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller",
      connection_id: "connection"
    }

    capability = capability(input_required?: true, frame_identity: identity)
    track = %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

    ingress =
      start_supervised!(
        {STSIngress,
         capability: capability,
         source_connection: self(),
         identity: identity,
         agent_id: "agent",
         format: Map.drop(track, [:track_id])},
        id: make_ref()
      )

    assert :ok = SpeechToSpeech.bind_input(capability, ingress)

    snapshot = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: unrestricted()
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, snapshot})
    assert :ok = GenServer.call(ingress, {:vxpipe_apply_media_policy, snapshot})
    assert :ok = STSIngress.prepare_track(ingress, track)
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = STSIngress.push(ingress, frame(identity, track, 1))
    assert_receive {:context_input, first, {:audio, <<0, 0>>}, _}, 1_000
    assert is_reference(first)

    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = STSIngress.push(ingress, frame(identity, track, 2))
    assert_receive {:context_input, second, {:audio, <<0, 0>>}, _}, 1_000
    assert second != first
  end

  defp frame(identity, track, sequence) do
    struct!(
      AudioFrame,
      Map.merge(
        identity,
        Map.merge(track, %{
          sequence_number: sequence,
          timestamp: sequence * 320,
          payload: <<0, 0>>,
          received_at: System.monotonic_time(:millisecond)
        })
      )
    )
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp deny_output do
    %{unrestricted() | audio_routes: %{"caller" => MapSet.new(["agent"])}}
  end

  defp restricted_both do
    %{
      unrestricted()
      | audio_routes: %{
          "caller" => MapSet.new(["agent"]),
          "agent" => MapSet.new(["caller"])
        }
    }
  end

  defp capability(options \\ []) do
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
    {:ok, private} = PrivateInit.open([observer: self()], 5_000)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           Keyword.merge(
             [
               owner: self(),
               agent_id: "agent",
               human_id: "caller",
               provider: {SpeechContextProbe, [turn_control: "hybrid"]},
               provider_private: private,
               sink: sink,
               frame_identity: %{}
             ],
             options
           )},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:vxpipe_sts_ready, ^capability}, 1_000
    capability
  end
end
