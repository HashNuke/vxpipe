defmodule Vxpipe.CallEngine.TestVoiceToolRoom do
  @moduledoc "A compiled LLM room with a controlled model, TTS transport and playback sink."
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.AgentRuntime.ModelResponse
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.{
    TestAudioOutputSink,
    TestTextToSpeechTransport,
    TestTransferConnection,
    TestTurnCall
  }

  def configure do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      original
      |> Keyword.update!(
        :agent_runtime,
        &Keyword.put(&1, :fixture, {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]})
      )
      |> Keyword.put(:speech_to_text,
        providers: %{
          Vxpipe.Providers.Deepgram.STTSession => [
            enabled: true,
            wire_module: Vxpipe.CallEngine.TestSpeechToTextTransport,
            wire_options: [observer: self(), ready_on_start: true],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )
      |> Keyword.put(:text_to_speech,
        providers: %{
          Vxpipe.Providers.Deepgram.TTSSession => [
            enabled: true,
            wire_module: TestTextToSpeechTransport,
            wire_options: [observer: self(), ready_on_start: true],
            maximum_requests: 4
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    :ok
  end

  def start_call(options \\ []) do
    {:ok, protocol} = CallEngine.AgentProtocol.capture()
    protocol = Keyword.get(options, :agent_protocol, protocol)
    idle = if protocol, do: %{"idle" => %{type: "platform", tool: "idle"}}, else: %{}
    room_id = "native-idle-#{System.unique_integer([:positive])}"

    {plan, room, caller} =
      TestTurnCall.start(room_id,
        text_to_speech: true,
        call_variables: Keyword.get(options, :call_variables, %{}),
        variable_permissions: Keyword.get(options, :variable_permissions, %{}),
        speech_to_text: Keyword.get(options, :speech_to_text, false),
        agent_protocol: protocol,
        tools: Map.merge(idle, Keyword.get(options, :tools, %{})),
        host_tools: Keyword.get(options, :host_tools, %{})
      )

    assert_receive {:test_tts_transport_started, voice, _}
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    {:ok, attach} =
      AttachConnection.new(
        tenant_id: room.tenant_id,
        actor_id: "actor-demo",
        room_id: room.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "idle-human",
        deadline: deadline()
      )

    {:ok, _} = TestTransferConnection.attach(attach, sink)
    CallEngine.TestCallStartup.await_ready(room_id)
    {plan, room, caller, voice, sink}
  end

  def submit(room, caller, content, correlation) do
    {:ok, command} =
      SendText.new(
        tenant_id: room.tenant_id,
        actor_id: "actor-demo",
        room_id: room.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "idle-human",
        correlation_id: correlation,
        content: content,
        deadline: deadline()
      )

    assert :ok = TestTransferConnection.send_text(command)
    command
  end

  def reply(provider, mode, message) do
    {:ok, response} =
      ModelResponse.new(
        text:
          JSON.encode!(%{
            "type" => "participant_message",
            "participant_id" => "agent",
            "agent_mode" => Atom.to_string(mode),
            "message" => message
          })
      )

    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  def settle(voice, sink, speech_id, correlation) do
    assert_receive {:test_tts_control, ^voice, flush}
    assert JSON.decode!(flush)["type"] == "Flush"

    TestTextToSpeechTransport.deliver_control(
      voice,
      JSON.encode!(%{"type" => "SpeechStarted", "speech_id" => speech_id})
    )

    TestTextToSpeechTransport.deliver_audio(voice, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, %{correlation_id: ^correlation}}

    TestTextToSpeechTransport.deliver_control(
      voice,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => speech_id})
    )

    assert_receive {:test_audio_output_finish, ^sink, ^correlation}
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_completed(sink)
  end

  defp deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
