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
