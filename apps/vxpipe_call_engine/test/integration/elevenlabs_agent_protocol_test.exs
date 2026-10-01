defmodule Vxpipe.CallEngine.Integration.ElevenLabsAgentProtocolTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag skip: "Hosted-agent STS is deferred; current ElevenLabs acceptance is STT/TTS."
  @moduletag :capture_log
  @moduletag timeout: 90_000

  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{AgentAPI, AgentSocket}
  alias Vxpipe.Providers.LiveModels

  test "selected inexpensive backend appears in the hosted-agent model catalog" do
    assert {:ok, client} = AgentAPI.new(System.fetch_env!("ELEVENLABS_API_KEY"))
    assert {:ok, models} = AgentAPI.available_models(client)
    selected = LiveModels.speech("elevenlabs", :sts_backend)

    assert selected in models,
           "Fixed backend is unavailable; listed Gemini aliases: #{inspect(Enum.filter(models, &String.starts_with?(&1, "gemini-")))}"

    case Req.get(client.request, url: "/v1/convai/llm/list") do
      {:ok, %Req.Response{status: 200, body: %{"llms" => entries}}} when is_list(entries) ->
        entry = Enum.find(entries, &(&1["llm"] == selected))
        efforts = Map.get(entry, "available_reasoning_efforts")

        efforts =
          if is_list(efforts),
            do: Enum.filter(efforts, &(&1 in ~w(none minimal low medium high xhigh max))),
            else: nil

        IO.puts("ElevenLabs selected backend reasoning efforts: #{inspect(efforts)}")

      _failure ->
        flunk("Backend constraints are unavailable")
    end

    case Req.get(client.request, url: "/v1/models") do
      {:ok, %Req.Response{status: 200, body: synthesis_models}} when is_list(synthesis_models) ->
        candidates =
          ~w(eleven_flash_v2 eleven_flash_v2_5 eleven_v3_conversational eleven_v4 eleven_v4_turbo)

        Enum.each(synthesis_models, fn model ->
          if model["model_id"] in candidates do
            factor = model["token_cost_factor"]
            factor = if is_number(factor), do: factor, else: :unreported
            IO.puts("ElevenLabs synthesis catalog: #{model["model_id"]}, cost_factor=#{factor}")
          end
        end)

      _failure ->
        flunk("Synthesis model catalog is unavailable")
    end
  end

  test "validates the bounded private definition without opening a speech connection" do
    assert {:ok, client} = AgentAPI.new(System.fetch_env!("ELEVENLABS_API_KEY"))

    assert {:ok, :validated} =
             AgentAPI.with_agent(client, definition(), fn connection ->
               uri = URI.parse(connection.url)
               id = URI.decode_query(uri.query)["agent_id"]

               case Req.get(client.request, url: "/v1/convai/agents/" <> id) do
                 {:ok, %Req.Response{status: 200, body: %{"conversation_config" => saved}}} ->
                   events = get_in(saved, ["conversation", "client_events"])
                   assert is_list(events) and "agent_response_complete" in events
                   assert get_in(saved, ["agent", "prompt", "reasoning_effort"]) == "minimal"
                   :validated

                 _failure ->
                   flunk("Saved agent configuration is unavailable")
               end
             end)
  end

  test "one private hosted conversation transcribes PCM and completes a bounded spoken response" do
    pcm = File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0, 0>>, 16_000 * 5)
    assert rem(byte_size(pcm), 2) == 0
    assert byte_size(pcm) <= 16_000 * 2 * 10
    assert {:ok, client} = AgentAPI.new(System.fetch_env!("ELEVENLABS_API_KEY"))

    # This proves hosted wire behavior, not room/history/tool acceptance. The API
    # deletes this agent after the callback, including safe callback failure.
    assert {:ok, evidence} =
             AgentAPI.with_agent(client, definition(), fn connection ->
               observe_conversation(connection, pcm)
             end)

    IO.puts(
      "ElevenLabs agent observation: user_bytes=#{byte_size(evidence.user_text)}, response_bytes=#{byte_size(evidence.response_text)}, audio_bytes=#{evidence.audio_bytes}, completed=#{is_integer(evidence.completion_id)}"
    )

    assert evidence.failure == nil,
           "Hosted conversation did not complete: #{inspect(evidence.failure)}"

    assert String.downcase(evidence.user_text) =~ "telescope"
    assert String.downcase(evidence.response_text) =~ "hello from vxpipe"
    assert is_binary(evidence.response_id)
    assert evidence.audio_bytes > 0
    assert evidence.audio_bytes <= 16_000 * 2 * 10
    assert is_integer(evidence.completion_id)

    IO.puts(
      "ElevenLabs agent protocol: audio_bytes=#{evidence.audio_bytes}, final_audio_marker=#{evidence.audio_final?}, " <>
        "audio_matches_response=#{MapSet.equal?(evidence.audio_ids, MapSet.new([evidence.response_event_id]))}, " <>
        "completion_matches_response=#{evidence.completion_id == evidence.response_event_id}"
    )
  end

  defp definition do
    %{
      "name" => "Vxpipe bounded live protocol",
      "conversation_config" => %{
        "asr" => %{"provider" => "scribe_realtime", "user_input_audio_format" => "pcm_16000"},
        "turn" => %{
          "turn_timeout" => 30,
          "initial_wait_time" => 30,
          "speculative_turn" => false
        },
        "tts" => %{
          "model_id" => LiveModels.speech("elevenlabs", :sts_tts),
          "voice_id" => LiveModels.speech("elevenlabs", :tts_voice),
          "agent_output_audio_format" => "pcm_16000"
        },
        "conversation" => %{
          "text_only" => false,
          "max_duration_seconds" => 60,
          "client_events" => [
            "conversation_initiation_metadata",
            "ping",
            "audio",
            "interruption",
            "user_transcript",
            "agent_response",
            "agent_response_correction",
            "vad_score",
            "agent_response_complete",
            "client_error"
          ]
        },
        "agent" => %{
          "first_message" => "",
          "language" => "en",
          "prompt" => %{
            "prompt" =>
              "Respond to the user's speech with exactly: Hello from Vxpipe. Say nothing else.",
            "llm" => LiveModels.speech("elevenlabs", :sts_backend),
            "max_tokens" => 128,
            "reasoning_effort" => "minimal",
            "backup_llm_config" => %{"preference" => "disabled"}
          }
        }
      },
      "platform_settings" => %{
        "auth" => %{"enable_auth" => true},
        "call_limits" => %{
          "bursting_enabled" => false
        },
        "privacy" => %{
          "record_voice" => false
        }
      }
    }
  end

  defp observe_conversation(connection, pcm) do
    id = make_ref()

    socket =
      start_supervised!(%{
        id: id,
        restart: :temporary,
        start:
          {AgentSocket, :start_link,
           [[owner: self(), connection: connection, transport_options: []]]}
      })

    try do
      receive do
        {:vxpipe_socket_connected, ^socket} ->
          :ok = AgentSocket.initiate(socket)

          receive do
            {:vxpipe_elevenlabs_agent_transport, ^socket, {:event, {:ready, _}}} ->
              initial = %{
                failure: nil,
                user_text: "",
                response_text: "",
                response_id: nil,
                response_event_id: nil,
                audio_bytes: 0,
                audio_ids: MapSet.new(),
                audio_final?: false,
                completion_id: nil
              }

              state = stream(socket, pcm, initial)
              await_completion(socket, state, System.monotonic_time(:millisecond) + 15_000)
          after
            5_000 -> %{failure: :readiness_timeout}
          end
      after
        15_000 -> %{failure: :connection_timeout}
      end
    after
      stop_supervised(id)
    end
  end

  defp stream(_socket, "", state), do: state
  defp stream(_socket, _pcm, %{failure: failure} = state) when not is_nil(failure), do: state
  defp stream(_socket, _pcm, %{completion_id: id} = state) when is_integer(id), do: state

  defp stream(socket, pcm, state) do
    size = min(byte_size(pcm), 3_200)
    <<chunk::binary-size(size), rest::binary>> = pcm
    :ok = AgentSocket.send_audio(socket, chunk)
    reference = make_ref()
    Process.send_after(self(), {:agent_audio_pace, reference}, div(size, 32))
    state = await_pace(socket, reference, state)
    stream(socket, rest, state)
  end

  defp await_pace(socket, reference, state) do
    receive do
      {:agent_audio_pace, ^reference} ->
        state

      {:vxpipe_elevenlabs_agent_transport, ^socket, event} ->
        await_pace(socket, reference, observe(socket, event, state))
    after
      1_000 -> %{state | failure: :pacing_timeout}
    end
  end

  defp await_completion(_socket, %{failure: failure} = state, _deadline) when not is_nil(failure),
    do: state

  defp await_completion(_socket, %{completion_id: id} = state, _deadline)
       when is_integer(id), do: state

  defp await_completion(socket, state, deadline) do
    receive do
      {:vxpipe_elevenlabs_agent_transport, ^socket, event} ->
        await_completion(socket, observe(socket, event, state), deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        %{state | failure: :completion_timeout}
    end
  end

  defp observe(socket, {:event, {:ping, id}}, state) do
    :ok = AgentSocket.pong(socket, id)
    state
  end

  defp observe(_socket, {:event, {:user_transcript, _id, text}}, state),
    do: %{state | user_text: text}

  defp observe(_socket, {:event, {:agent_response, id, response_id, text}}, state),
    do: %{state | response_event_id: id, response_id: response_id, response_text: text}

  defp observe(_socket, {:event, {:audio, id, pcm, final?, _alignment}}, state),
    do: %{
      state
      | audio_bytes: state.audio_bytes + byte_size(pcm),
        audio_ids: MapSet.put(state.audio_ids, id),
        audio_final?: state.audio_final? or final?
    }

  defp observe(_socket, {:event, {:response_complete, id}}, state),
    do: %{state | completion_id: id}

  defp observe(_socket, {:event, {:vad, _score}}, state), do: state

  defp observe(_socket, {:event, {:provider_error, code}}, state),
    do: %{state | failure: {:provider_error, code}}

  defp observe(_socket, {:event, {:interrupted, _id}}, state), do: state

  defp observe(_socket, {:event, {:queue_status, status}}, state)
       when status in ["waiting", "admitted"], do: state

  defp observe(_socket, {:closed, reason}, state),
    do: %{state | failure: {:transport_closed, reason}}

  defp observe(_socket, {:peer_closed, status}, state),
    do: %{state | failure: {:peer_closed, status}}

  defp observe(_socket, {:event, event}, state) when is_tuple(event),
    do: %{state | failure: {:unexpected_event, elem(event, 0)}}
end
