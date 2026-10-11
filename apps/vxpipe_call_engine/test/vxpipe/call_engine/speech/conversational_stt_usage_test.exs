defmodule Vxpipe.CallEngine.Speech.ConversationalSTTUsageTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event}
  alias Vxpipe.CallEngine.SpeechOnsetProbe
  alias Vxpipe.CallEngine.Usage.ProviderContext

  for vad <- [false, true] do
    @vad vad
    test "decoded PCM does not duplicate recognition or caller usage with VAD=#{vad}" do
      {capability, recognizer, _inner, identity, _policy} = start_capability(@vad)
      payload = <<1, 2, 3>>
      pcm = :binary.copy(<<3, 0>>, 960)

      for sequence <- 0..1 do
        timestamp = sequence * 960

        frame =
          struct!(
            AudioFrame,
            identity ++
              [
                track_id: "a",
                codec: :opus,
                sample_rate: 48_000,
                channels: 1,
                sequence_number: sequence,
                timestamp: timestamp,
                received_at: 1,
                payload: payload,
                activity_pcm: %{
                  payload: pcm,
                  sample_rate: 48_000,
                  channels: 1,
                  timestamp: timestamp
                }
              ]
          )

        assert :ok = SpeechToText.push_audio(capability, frame)
        assert_receive {:recognized_audio, ^payload}
      end

      assert_receive {:vxpipe_usage_observations, ^capability, [started]}
      assert started.outcome == :in_progress
      assert started.provider.name == "morse"

      assert :ok =
               GenServer.call(
                 recognizer,
                 {:emit, :turn_ended,
                  [
                    turn_ref: make_ref(),
                    text: "hello",
                    audio_duration_ms: 20,
                    endpointing: :provider_gap
                  ]}
               )

      assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :turn_ended}}
      assert_receive {:vxpipe_usage_observations, ^capability, measurements}
      assert [audio, text] = Enum.sort_by(measurements, & &1.measurement.component)
      assert audio.measurement.quantity == 20
      assert text.measurement.quantity == 5
      assert audio.attempt_id == started.attempt_id
      assert text.attempt_id == started.attempt_id
      refute_received {:recognized_audio, _duplicate}
      refute_received {:vxpipe_usage_observations, _owner, _duplicate}
    end
  end

  for vad <- [false, true] do
    @vad vad
    test "permission replacement retires old recognition and usage with VAD=#{vad}" do
      {capability, old_recognizer, old_inner, _identity, policy} = start_capability(@vad)
      native = make_ref()

      assert :ok =
               GenServer.call(
                 old_recognizer,
                 {:emit, :transcript, [turn_ref: native, text: "old"]}
               )

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :turn_started, provider_turn_index: old_index, policy_revision: 0}}

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :transcript_updated, text: "old"}}

      assert_receive {:vxpipe_usage_observations, ^capability, [old_attempt]}
      monitor = Process.monitor(old_recognizer)
      denied = %{policy | revision: 1, present_participant_ids: MapSet.new()}
      assert :ok = Enforcer.apply(capability, denied, 500)
      assert_receive {:DOWN, ^monitor, :process, ^old_recognizer, _reason}
      assert_receive {:vxpipe_usage_observations, ^capability, [cancelled]}
      assert cancelled.attempt_id == old_attempt.attempt_id
      assert cancelled.outcome == :cancelled

      assert :ok = Enforcer.apply(capability, %{policy | revision: 2}, 500)
      assert_receive {:recognizer, recognizer, inner}
      refute recognizer == old_recognizer
      assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}

      assert :ok =
               GenServer.call(recognizer, {:emit, :transcript, [turn_ref: native, text: "new"]})

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :turn_started, provider_turn_index: new_index, policy_revision: 2}}

      assert new_index == old_index
      refute inner.generation == old_inner.generation

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :transcript_updated, text: "new"}}

      assert_receive {:vxpipe_usage_observations, ^capability, [new_attempt]}
      refute new_attempt.attempt_id == old_attempt.attempt_id

      send(
        inner.owner,
        {:vxpipe_speech,
         %Event{
           session: old_inner,
           sequence: 99,
           kind: :turn_ended,
           turn_ref: native,
           text: "late old final",
           endpointing: :provider_gap
         }}
      )

      assert :ok = GenServer.call(inner.owner, :synchronize)
      refute_received {:vxpipe_stt_signal, ^capability, _, %{kind: :turn_ended}}

      assert :ok =
               GenServer.call(
                 recognizer,
                 {:emit, :turn_ended,
                  [
                    turn_ref: native,
                    text: "new final",
                    audio_duration_ms: 20,
                    endpointing: :provider_gap
                  ]}
               )

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :turn_ended, provider_turn_index: ^new_index, text: "new final"}}

      assert_receive {:vxpipe_usage_observations, ^capability, measurements}
      assert Enum.all?(measurements, &(&1.attempt_id == new_attempt.attempt_id))
      refute_received {:vxpipe_usage_observations, _owner, _duplicate}
    end
  end

  defp start_capability(vad) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, provider} = ProviderContext.new(name: "morse", model: "morse")
    options = [encoding: :opus, sample_rate: 48_000]

    identity = [
      tenant_id: "t",
      room_id: "r",
      incarnation_id: "i",
      participant_id: "p",
      connection_id: "c"
    ]

    policy = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["p"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             speech_scope: CapabilityTree.scope(tree),
             initial_policy: policy,
             provider:
               {ConversationalSTT, [provider: SpeechOnsetProbe, options: options, vad: vad]},
             provider_private: [
               recognizer: SpeechOnsetProbe,
               recognizer_options: options,
               recognizer_private: [observer: self()],
               activity_options: [
                 load: fn -> {:ok, :model} end,
                 classify: fn _model, stream, _pcm -> {:ok, stream, []} end
               ]
             ],
             usage: [
               call_id: "call",
               participant_id: "p",
               activation_id: nil,
               provider: provider
             ]
           ]}
      )

    assert_receive {:recognizer, recognizer, inner}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000
    assert :ok = Enforcer.apply(capability, policy, 500)
    {capability, recognizer, inner, identity, policy}
  end
end
