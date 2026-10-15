defmodule Vxpipe.Console.Test.MorseRestartProbe do
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Diagnostics.{AgentRuntimeModelProvider, ModelFixture}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ParticipantTranscription}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Speech.SocketConnection
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Test.{PCMOutput, SpeechConnection}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Providers.MorseCodeApi.{CredentialValidation, STT, STTSession, TTSSession}

  @key "synthetic persisted restart key"

  def run("seed", path, _ca) do
    options = repositories()
    {:ok, tenant, _} = Administration.bootstrap_tenant("Morse restart fixture", [:admin], options)

    {:ok, service} =
      ProviderCredentials.provision(
        :platform,
        "morse_code_api",
        "voice",
        "api_key",
        %{"api_key" => @key},
        options
      )

    {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source(), options)
    [] = draft.validation_errors

    {:ok, publication} =
      Vxpipe.Calls.publish_call_spec(tenant.key, draft.call_spec_id, draft.revision, options)

    File.write!(
      path,
      Jason.encode!(%{
        tenant: tenant.key,
        id: publication.call_spec_id,
        revision: publication.revision,
        service: service.id,
        version: service.version,
        digest: digest(publication.source)
      })
    )

    IO.puts("Morse restart fixture persisted")
  end

  def run("reject_tls", _path, _ca) do
    origin = System.fetch_env!("MORSE_CODE_API_BASE_URL")
    {:error, error} = Req.get(origin <> "/v1/models", retry: false, max_redirects: 0)
    true = String.contains?(inspect(error), ["unknown_ca", "selfsigned_peer"])
    {:ok, config} = STT.new(api_key: @key)

    {:error, :connection_unavailable} =
      SocketConnection.open(STT.connection_options(config),
        connect_timeout: 1_000,
        receive_timeout: 1_000
      )

    IO.puts("Morse untrusted HTTPS and WSS rejected")
  end

  def run("room", path, ca) do
    if ca != "none", do: :ok = :public_key.cacerts_load(String.to_charlist(ca))
    options = repositories()
    pin = path |> File.read!() |> Jason.decode!()

    {:ok, service} =
      ProviderCredentialSource.resolve(options, pin["tenant"], "morse_code_api", "voice")

    true = service.id == pin["service"] and service.version == pin["version"]

    {:ok, publication} =
      Vxpipe.Calls.fetch_call_spec(pin["tenant"], pin["id"], pin["revision"], options)

    true = digest(publication.source) == pin["digest"]
    {:ok, probe} = CredentialValidation.request(service.auth_kind, service.payload)
    {:ok, %{status: 200}} = Req.get(probe ++ [retry: false, max_redirects: 0])

    {:ok, %{status: 200}} =
      Req.get(System.fetch_env!("MORSE_CODE_API_BASE_URL") <> "/v1/voices",
        headers: [{"xi-api-key", Map.fetch!(service.payload, "api_key")}],
        retry: false,
        max_redirects: 0
      )

    {:ok, supervisor} =
      DynamicSupervisor.start_link(strategy: :one_for_one, name: __MODULE__.Supervisor)

    try do
      {:ok, model} =
        DynamicSupervisor.start_child(supervisor, {ModelFixture, response: "TEST", delay_ms: 0})

      {:ok, sink} = DynamicSupervisor.start_child(supervisor, {PCMOutput, observer: self()})

      settings =
        Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
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

      {:ok, spec} =
        CallSpec.new(publication.source,
          resource_id: publication.call_spec_id,
          revision: publication.revision
        )

      {:ok, invocation} =
        CallInvocation.new(
          %{
            call_spec: %{id: publication.call_spec_id, revision: publication.revision},
            transport: %{type: "web"}
          },
          tenant_id: pin["tenant"],
          actor_id: "restart-fixture"
        )

      {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

      {:ok, room} =
        CallEngine.start_call(plan, credential_source: {ProviderCredentialSource, options})

      {:ok, monitor} = CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)
      caller = Map.fetch!(plan.participants, plan.entry_caller)

      identity = [
        tenant_id: plan.tenant_id,
        actor_id: plan.actor_id,
        room_id: plan.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "morse-restart-caller"
      ]

      {:ok, command} =
        AttachConnection.new(
          identity ++ [deadline: DateTime.add(DateTime.utc_now(), 20, :second)]
        )

      {:ok, connection} =
        DynamicSupervisor.start_child(
          supervisor,
          {SpeechConnection, command: command, observer: self(), output: sink}
        )

      {:ok, attachment} = SpeechConnection.attach(connection)

      try do
        receive do
          {:configured_speech_ready, ^connection} -> :ok
        after
          15_000 -> raise "Morse restart room did not become ready"
        end

        {:ok, profile} = Config.new()
        {:ok, pcm} = Encoder.encode(profile, "E E")
        stream(connection, identity, pcm, 0)

        turn =
          receive do
            {:vxpipe_event,
             %ParticipantTranscription{final: true, text: "E E", correlation_id: turn}} ->
              turn
          after
            10_000 -> raise "Morse restart transcript missing"
          end

        audio = audio(sink, turn, [])
        {:ok, decoder} = Decoder.new(profile)
        {:ok, decoder, events} = Decoder.push(decoder, audio)
        {:ok, _decoder, tail} = Decoder.flush(decoder)
        ["TEST"] = for {:final, text} <- events ++ tail, do: text
        :ok = PCMOutput.complete(sink)

        receive do
          {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^turn}} -> :ok
        after
          5_000 -> raise "Morse restart reply did not complete"
        end
      after
        GenServer.stop(attachment.room_authority, :shutdown)
      end

      receive do
        {:DOWN, ^monitor, :process, _, _} -> :ok
      after
        5_000 -> raise "Morse restart room did not retire"
      end
    after
      Supervisor.stop(supervisor)
    end

    IO.puts("Morse persisted service and room verified: " <> pin["digest"])
  end

  defp repositories do
    if Process.whereis(Repo) == nil, do: {:ok, _} = Repo.start_link()
    :ok = Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    {:ok, keyring} = CredentialKeyring.new("fixture", %{"fixture" => :binary.copy(<<42>>, 32)})

    [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo}
    ]
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Morse persisted restart",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          speech_to_text: %{
            provider: "morse_code_api",
            model: "morse_stt_v1",
            credential_name: "voice"
          },
          text_to_speech: %{
            provider: "morse_code_api",
            model: "morse_v1",
            credential_name: "voice",
            options: %{voice: "morse"}
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Reply briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp digest(source),
    do: Base.encode16(:crypto.hash(:sha256, Jason.encode!(source)), case: :lower)

  defp stream(_connection, _identity, "", _position), do: :ok

  defp stream(connection, identity, pcm, position) do
    size = min(byte_size(pcm), 640)
    <<chunk::binary-size(size), rest::binary>> = pcm

    frame =
      struct!(
        AudioFrame,
        Keyword.take(identity, [
          :tenant_id,
          :room_id,
          :incarnation_id,
          :participant_id,
          :connection_id
        ]) ++
          [
            track_id: "configured-speech",
            codec: :linear16,
            sample_rate: 16_000,
            channels: 1,
            sequence_number: div(position, 640),
            timestamp: div(position, 2),
            payload: chunk,
            received_at: System.monotonic_time(:millisecond)
          ]
      )

    :ok = CallEngine.push_audio(SpeechConnection.attachment(connection), frame)
    token = make_ref()
    Process.send_after(self(), {:pace, token}, div(size, 32))

    receive do
      {:pace, ^token} -> :ok
    after
      2_000 -> raise "Morse restart media pacing deadline"
    end

    stream(connection, identity, rest, position + size)
  end

  defp audio(sink, turn, frames) do
    receive do
      {:configured_pcm, ^sink, %{correlation_id: ^turn, payload: pcm}} ->
        audio(sink, turn, [pcm | frames])

      {:configured_pcm_finished, ^sink, ^turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      10_000 -> raise "Morse restart PCM missing"
    end
  end
end

[mode, path, ca] = System.argv()
Vxpipe.Console.Test.MorseRestartProbe.run(mode, path, ca)
