defmodule Vxpipe.Console.Integration.MorseCodeApiConfiguredRoomTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_morse_code_api
  @moduletag :capture_log
  @moduletag timeout: 60_000

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Diagnostics.{AgentRuntimeModelProvider, ModelFixture}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, AgentTurnInterrupted}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Test.{PCMOutput, SpeechConnection}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Providers.MorseCode.STTSession
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, TTSSession}

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    model = start_supervised!({ModelFixture, response: "TEST", delay_ms: 0})
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:finch, :request, :start],
        &__MODULE__.capture_request/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    settings =
      original
      |> Keyword.update!(
        :agent_runtime,
        &Keyword.put(&1, :fixture, {AgentRuntimeModelProvider, [fixture: model]})
      )
      |> Keyword.put(:text_to_speech,
        providers: %{TTSSession => [enabled: true, maximum_requests: 4]}
      )
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    %{
      options: [
        credential_repository: {CredentialStore, Repo},
        provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        call_spec_repository: {CallSpecStore, Repo}
      ]
    }
  end

  test "a saved service synthesizes opening and conversational audio and replaces blocked output",
       %{options: options} do
    {plan, room} = published_room(options)
    sink = start_supervised!({PCMOutput, observer: self()})
    {connection, identity} = attach(plan, room, sink)

    {opening, opening_turn} = collect_audio(sink)
    assert decoded(opening) == "SOS"
    assert :ok = PCMOutput.complete(sink)
    assert_receive {:configured_speech_ready, ^connection}, 10_000

    assert :ok = SpeechConnection.send_text(connection, command(identity, "first", "HELLO"))
    {audio, "first"} = collect_audio(sink)
    assert decoded(audio) == "TEST"
    refute_received {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first"}}
    assert :ok = PCMOutput.complete(sink)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first"}}, 5_000

    assert :ok = PCMOutput.block(sink)
    assert :ok = SpeechConnection.send_text(connection, command(identity, "blocked", "AGAIN"))
    assert_receive {:configured_pcm, ^sink, %{correlation_id: "blocked"}}, 10_000

    assert :ok =
             SpeechConnection.send_text(connection, command(identity, "replacement", "CHANGE"))

    assert_receive {:configured_pcm_interrupted, ^sink, "blocked"}, 5_000

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{
                      correlation_id: "blocked",
                      interruption_correlation_id: "replacement"
                    }},
                   5_000

    {replacement, "replacement"} = collect_audio(sink)
    assert decoded(replacement) == "TEST"
    assert :ok = PCMOutput.complete(sink)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "replacement"}}, 5_000
    refute_received {:configured_pcm, ^sink, %{correlation_id: "blocked"}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{correlation_id: "blocked"}}
    refute opening_turn in ["first", "blocked", "replacement"]

    assert {:ok, endpoint} = Endpoint.configured()
    origin = URI.new!(endpoint.http)
    requests = collect_observations(:configured_request)
    assert length(requests) == 4

    assert Enum.all?(
             requests,
             &(&1 == {origin.scheme, origin.host, origin.port, "/v1/text-to-speech/morse/stream"})
           )

    events = collect_observations(:configured_public_event)
    assert events != []
    refute :erlang.term_to_binary(events) =~ "configured room compatibility key"

    assert {:ok, monitor} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)

    attachment = SpeechConnection.attachment(connection)
    GenServer.stop(attachment.room_authority, :shutdown)
    assert_receive {:DOWN, ^monitor, :process, _room, _reason}, 5_000
  end

  defp published_room(options) do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("Morse configured room", [:admin], options)

    assert {:ok, _service} =
             ProviderCredentials.provision(
               :platform,
               "morse_code_api",
               "voice",
               "api_key",
               %{"api_key" => "configured room compatibility key"},
               options
             )

    assert {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source(), options)
    assert draft.validation_errors == []

    assert {:ok, publication} =
             Vxpipe.Calls.publish_call_spec(
               tenant.key,
               draft.call_spec_id,
               draft.revision,
               options
             )

    refute :erlang.term_to_binary(publication) =~ "configured room compatibility key"

    assert {:ok, spec} =
             CallSpec.new(publication.source,
               resource_id: publication.call_spec_id,
               revision: publication.revision
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: publication.call_spec_id, revision: publication.revision},
                 transport: %{type: "web"}
               },
               tenant_id: tenant.key,
               actor_id: "morse-room-test"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    assert {:ok, room} =
             CallEngine.start_call(plan, credential_source: {ProviderCredentialSource, options})

    {plan, room}
  end

  defp source do
    voice = %{
      provider: "morse_code_api",
      model: "morse_v1",
      credential_name: "voice",
      options: %{voice: "morse"}
    }

    %{
      schema_version: "20260915.01",
      name: "Morse configured room",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      opening_audio: %{type: "text", text: "SOS", text_to_speech: voice},
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          speech_to_text: %{provider: "morse", model: "morse"},
          text_to_speech: voice
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp attach(plan, room, sink) do
    participant = Map.fetch!(plan.participants, plan.entry_caller)

    identity = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: "morse-room-caller"
    ]

    assert {:ok, command} =
             AttachConnection.new(
               identity ++ [deadline: DateTime.add(DateTime.utc_now(), 20, :second)]
             )

    connection =
      start_supervised!(
        {SpeechConnection, command: command, observer: self(), output: sink, audit_events?: true}
      )

    assert {:ok, attachment} = SpeechConnection.attach(connection)

    on_exit(fn ->
      try do
        GenServer.stop(attachment.room_authority, :shutdown)
      catch
        :exit, {:noproc, _call} -> :ok
      end
    end)

    {connection, identity}
  end

  defp command(identity, correlation, text) do
    assert {:ok, command} =
             SendText.new(
               identity ++
                 [
                   correlation_id: correlation,
                   content: text,
                   audio_response: true,
                   deadline: DateTime.add(DateTime.utc_now(), 10, :second)
                 ]
             )

    command
  end

  defp collect_audio(sink),
    do: collect_audio(sink, [], nil, System.monotonic_time(:millisecond) + 15_000)

  defp collect_audio(sink, frames, turn, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "room audio exceeded its deadline"

    receive do
      {:configured_pcm, ^sink, frame} ->
        assert frame.codec == :linear16
        assert frame.sample_rate == 16_000
        assert frame.channels == 1
        assert turn == nil or turn == frame.correlation_id
        collect_audio(sink, [frame.payload | frames], frame.correlation_id, deadline)

      {:configured_pcm_finished, ^sink, finished} ->
        assert finished == turn
        {frames |> Enum.reverse() |> IO.iodata_to_binary(), finished}
    after
      remaining -> flunk("room audio did not finish")
    end
  end

  defp decoded(pcm) do
    assert {:ok, config} = Config.new(sample_rate: 16_000)
    assert {:ok, decoder} = Decoder.new(config)
    assert {:ok, decoder, events} = Decoder.push(decoder, pcm)
    assert {:ok, _decoder, final} = Decoder.flush(decoder)
    assert [text] = for({:final, text} <- events ++ final, do: text)
    text
  end

  def capture_request(_event, _measurements, %{request: request}, observer) do
    send(
      observer,
      {:configured_request, {to_string(request.scheme), request.host, request.port, request.path}}
    )
  end

  defp collect_observations(tag) do
    receive do
      {^tag, observation} -> [observation | collect_observations(tag)]
    after
      0 -> []
    end
  end
end
