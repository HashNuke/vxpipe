defmodule Vxpipe.CallEngine.Provider.MorseCode.RoomRoundTripTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    Diagnostics.ModelFixture
  }

  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Media.{AudioFrame, AudioOutputFrame}
  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Decoder, Encoder}
  alias Vxpipe.CallEngine.TestAudioOutputSink

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    fixture =
      start_supervised!(
        {ModelFixture, name: nil, default_scenario: :success, delay_ms: 0, response: "OK"}
      )

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:model_fixture, fixture)

    speech_to_text = [
      enabled: false,
      providers: %{
        MorseCodeSTT => [
          enabled: true,
          provider_options: [],
          transport: {MorseCodeSTT.Transport, []},
          media_ingress: media_ingress_options()
        ]
      }
    ]

    text_to_speech = [
      enabled: false,
      providers: %{
        MorseCodeTTS => [
          enabled: true,
          provider_options: [],
          transport: {MorseCodeTTS.Transport, [emit_interval_ms: 0]},
          maximum_requests: 2
        ]
      }
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "runs encoded caller audio through a local reply and real audio output" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, room} = CallEngine.start_call(plan)

    connection_id = unique_id("connection")

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, attachment} = CallEngine.attach_connection(command, sink)
    push_text(attachment, plan, room, caller, connection_id, "SOS", 1)

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{
                      participant_id: caller_id,
                      connection_id: ^connection_id,
                      modality: :audio,
                      correlation_id: correlation_id
                    }},
                   1_000

    assert caller_id == caller.participant_id

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: ^caller_id,
                      connection_id: ^connection_id,
                      correlation_id: ^correlation_id,
                      text: "SOS",
                      final: true,
                      provider_turn_index: 0
                    }},
                   1_000

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{
                      participant_id: ^caller_id,
                      correlation_id: ^correlation_id,
                      modality: :audio
                    }},
                   1_000

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: receiver_id,
                      source_participant_id: ^caller_id,
                      connection_id: ^connection_id,
                      correlation_id: ^correlation_id,
                      text: "OK",
                      will_be_spoken: true
                    }},
                   2_000

    assert receiver_id == receiver.participant_id

    frames = collect_output(sink, correlation_id, [])
    assert length(frames) > 10
    assert Enum.all?(frames, &(byte_size(&1.payload) <= 640))

    output_pcm = frames |> Enum.map(& &1.payload) |> IO.iodata_to_binary()
    assert {:ok, output_config} = MorseCodeTTS.new(sample_rate: 16_000, unit_duration_ms: 20)
    assert {:ok, output_decoder} = Decoder.new(output_config)
    assert {:ok, output_decoder, output_events} = Decoder.push(output_decoder, output_pcm)
    assert {:ok, _output_decoder, []} = Decoder.flush(output_decoder)
    assert List.last(output_events) == {:final, "OK"}

    :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{
                      participant_id: ^receiver_id,
                      source_participant_id: ^caller_id,
                      correlation_id: ^correlation_id
                    }},
                   1_000

    push_text(attachment, plan, room, caller, connection_id, "ET", 100)

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{
                      participant_id: ^caller_id,
                      connection_id: ^connection_id,
                      modality: :audio,
                      correlation_id: second_correlation_id
                    }},
                   1_000

    refute second_correlation_id == correlation_id

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: ^caller_id,
                      correlation_id: ^second_correlation_id,
                      text: "ET",
                      final: true,
                      provider_turn_index: 1
                    }},
                   1_000

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{
                      participant_id: ^caller_id,
                      correlation_id: ^second_correlation_id,
                      modality: :audio
                    }},
                   1_000

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^receiver_id,
                      source_participant_id: ^caller_id,
                      correlation_id: ^second_correlation_id,
                      text: "OK",
                      will_be_spoken: true
                    }},
                   2_000

    second_frames = collect_output(sink, second_correlation_id, [])
    assert_decodes_to(second_frames, "OK")
    :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{
                      participant_id: ^receiver_id,
                      source_participant_id: ^caller_id,
                      correlation_id: ^second_correlation_id
                    }},
                   1_000
  end

  defp compile_plan do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(),
               resource_id: "morse-round-trip",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "morse-round-trip", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-morse",
               actor_id: "actor-morse",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "fixture-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:fixture"}
        },
        "morse-stt" => %{
          kind: :speech_to_text,
          provider: MorseCodeSTT,
          options: %{sample_rate: 16_000, unit_duration_ms: 20}
        },
        "morse-tts" => %{
          kind: :text_to_speech,
          provider: MorseCodeTTS,
          options: %{sample_rate: 16_000, unit_duration_ms: 20}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp definition_input do
    %{
      schema_version: "20260906.02",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{
          speech_to_text: "morse-stt",
          model_inference: "fixture-model",
          text_to_speech: "morse-tts"
        }
      },
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Return the configured local response.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp collect_output(sink, correlation_id, frames) do
    receive do
      {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: ^correlation_id} = frame} ->
        collect_output(sink, correlation_id, [frame | frames])

      {:test_audio_output_finish, ^sink, ^correlation_id} ->
        Enum.reverse(frames)
    after
      3_000 -> flunk("timed out waiting for the complete Morse room output")
    end
  end

  defp push_text(attachment, plan, room, caller, connection_id, text, first_sequence) do
    assert {:ok, input_config} = MorseCodeSTT.new(sample_rate: 16_000, unit_duration_ms: 20)
    assert {:ok, input_pcm} = Encoder.encode(input_config, text)

    input_pcm
    |> split_repeatedly([2_001, 4_093, 811])
    |> Enum.with_index(first_sequence)
    |> Enum.each(fn {payload, sequence} ->
      frame = %AudioFrame{
        tenant_id: plan.tenant_id,
        room_id: plan.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: connection_id,
        track_id: "track-morse",
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1,
        sequence_number: sequence,
        timestamp: sequence * 320,
        payload: payload,
        received_at: System.monotonic_time(:millisecond)
      }

      assert :ok = CallEngine.push_audio(attachment, frame)
    end)
  end

  defp assert_decodes_to(frames, expected_text) do
    output_pcm = frames |> Enum.map(& &1.payload) |> IO.iodata_to_binary()
    assert {:ok, output_config} = MorseCodeTTS.new(sample_rate: 16_000, unit_duration_ms: 20)
    assert {:ok, output_decoder} = Decoder.new(output_config)
    assert {:ok, output_decoder, output_events} = Decoder.push(output_decoder, output_pcm)
    assert {:ok, _output_decoder, []} = Decoder.flush(output_decoder)
    assert List.last(output_events) == {:final, expected_text}
  end

  defp media_ingress_options do
    [
      maximum_frames: 100,
      maximum_bytes: 262_144,
      maximum_age_ms: 2_000,
      maximum_consecutive_overflows: 5
    ]
  end

  defp split_repeatedly(binary, sizes), do: split_repeatedly(binary, sizes, sizes, [])

  defp split_repeatedly(<<>>, _remaining_sizes, _all_sizes, chunks),
    do: Enum.reverse(chunks)

  defp split_repeatedly(binary, [], all_sizes, chunks),
    do: split_repeatedly(binary, all_sizes, all_sizes, chunks)

  defp split_repeatedly(binary, [size | sizes], all_sizes, chunks)
       when byte_size(binary) > size do
    <<chunk::binary-size(size), rest::binary>> = binary
    split_repeatedly(rest, sizes, all_sizes, [chunk | chunks])
  end

  defp split_repeatedly(binary, _sizes, _all_sizes, chunks),
    do: Enum.reverse([binary | chunks])

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
