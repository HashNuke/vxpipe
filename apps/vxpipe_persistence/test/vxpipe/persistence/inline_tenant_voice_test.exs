defmodule Vxpipe.Persistence.InlineTenantVoiceTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CallStore, CredentialKeyring, CredentialStore, CallSpecStore}
  alias Vxpipe.Persistence.ProviderCredentialStore
  alias Vxpipe.Persistence.Schema.{CallSpec, CallSpecRevision, ParticipantRoute}

  setup do
    {:ok, keyring} =
      CredentialKeyring.new("inline-v1", %{"inline-v1" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Inline voice tenant", [:calls], options)

    {:ok, other, _} = Administration.bootstrap_tenant("Unprovisioned tenant", [:calls], options)
    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

    for provider <- ["google", "deepgram"] do
      assert {:ok, _} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 "default",
                 "api_key",
                 %{"api_key" => provider <> "-inline-private-marker"},
                 options
               )
    end

    [tenant: tenant, other: other, principal: principal, options: options]
  end

  test "provisions, saves, publishes and prepares a tenant voice plan without storing secrets",
       ctx do
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(
               ctx.tenant.key,
               draft.call_spec_id,
               draft.revision,
               ctx.options
             )

    assert [route] = published.routes

    assert {:ok, call, token} =
             Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)

    assert call.plan.participants["assistant"].capabilities.model_inference.provider == "google"
    assert call.plan.participants["caller"].capabilities.speech_to_text.provider == "deepgram"
    refute :erlang.term_to_binary(call) =~ "inline-private-marker"
    refute JSON.encode!(draft.source) =~ "inline-private-marker"

    assert {:ok, claim} =
             Calls.claim_join_token(
               token.secret,
               %{tenant_key: ctx.tenant.key, call_id: call.id, participant_key: route.key},
               ctx.options
             )

    assert claim.call.id == call.id
    assert claim.call.tenant_key == ctx.tenant.key
  end

  test "persists the existing Zenmux selection and resolves only its named tenant credential",
       ctx do
    selection = %{
      provider: "zenmux",
      model: "openai/gpt-5",
      credential_name: "router",
      options: %{temperature: 0.2},
      provider_options: %{
        provider: %{fallback: "anthropic", routing: %{providers: ["openai", "anthropic"]}}
      }
    }

    source = put_in(source(), [:defaults, :capabilities, :model_inference], selection)
    before = row_counts()

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_call_spec(ctx.tenant.key, source, ctx.options)

    assert row_counts() == before

    for tenant <- [ctx.tenant, ctx.other] do
      assert {:ok, _credential} =
               ProviderCredentials.provision(
                 tenant.key,
                 "zenmux",
                 "router",
                 "api_key",
                 %{"api_key" => "zenmux-#{tenant.key}-private-marker"},
                 ctx.options
               )
    end

    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source, ctx.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(ctx.tenant.key, draft.call_spec_id, 1, ctx.options)

    assert [route] = published.routes
    assert {:ok, prepared, token} = Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)

    assert {:ok, claim} =
             Calls.claim_join_token(
               token.secret,
               %{tenant_key: ctx.tenant.key, call_id: prepared.id, participant_key: route.key},
               ctx.options
             )

    restored = claim.call.plan.participants["assistant"].capabilities.model_inference
    assert restored.provider == "zenmux"
    assert restored.model == "openai/gpt-5"
    assert restored.credential_name == "router"
    assert restored.options == %{"temperature" => 0.2}
    assert restored.provider_options == JSON.decode!(JSON.encode!(selection.provider_options))
    refute :erlang.term_to_binary(claim.call) =~ "private-marker"

    runtime = [credential_source: {Vxpipe.Calls.ProviderCredentialSource, ctx.options}]

    for tenant <- [ctx.tenant, ctx.other] do
      assert {:ok, resolved} =
               Vxpipe.CallEngine.CredentialSource.resolve(tenant.key, restored, runtime)

      assert resolved.payload == %{"api_key" => "zenmux-#{tenant.key}-private-marker"}
      refute inspect(resolved) =~ "private-marker"
    end

    assert {:ok, credential} =
             ProviderCredentials.resolve(ctx.tenant.key, "zenmux", "router", ctx.options)

    assert {1, _} =
             Repo.update_all(
               from(c in Vxpipe.Persistence.Schema.ProviderCredential,
                 where: c.public_id == ^credential.credential.id
               ),
               set: [status: "revoked"]
             )

    assert {:error, :provider_credential_unavailable} =
             Vxpipe.CallEngine.CredentialSource.resolve(ctx.tenant.key, restored, runtime)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)
  end

  test "another tenant cannot save the same provider selections or create any rows", ctx do
    before = row_counts()
    assert {:error, error} = Calls.save_call_spec(ctx.other.key, source(), ctx.options)
    assert error.code == :provider_credential_unavailable

    assert error.details["path"] in [
             ["defaults", "capabilities", "speech_to_text"],
             ["defaults", "capabilities", "model_inference"],
             ["defaults", "capabilities", "text_to_speech"]
           ]

    assert row_counts() == before
    refute inspect(error) =~ "inline-private-marker"
  end

  for {kind, provider} <- [
        model_inference: "google",
        text_to_speech: "deepgram",
        speech_to_text: "deepgram"
      ],
      unavailable <- [:missing, :other_tenant, :inactive] do
    @destination_kind kind
    @destination_provider provider
    @unavailable unavailable

    test "rejects #{@unavailable} destination-only #{@destination_kind} binding before saving rows",
         ctx do
      if @unavailable != :missing do
        tenant = if @unavailable == :other_tenant, do: ctx.other, else: ctx.tenant

        assert {:ok, credential} =
                 ProviderCredentials.provision(
                   tenant.key,
                   @destination_provider,
                   "destination",
                   "api_key",
                   %{"api_key" => "destination-private-marker"},
                   ctx.options
                 )

        if @unavailable == :inactive do
          assert {1, _} =
                   Repo.update_all(
                     from(c in Vxpipe.Persistence.Schema.ProviderCredential,
                       where: c.public_id == ^credential.id
                     ),
                     set: [status: "revoked"]
                   )
        end
      end

      before = row_counts()

      assert {:error, error} =
               Calls.save_call_spec(
                 ctx.tenant.key,
                 destination_source(@destination_kind),
                 ctx.options
               )

      assert error.code == :provider_credential_unavailable

      assert error.details["path"] ==
               ["participants", "destination", "capabilities", Atom.to_string(@destination_kind)]

      assert row_counts() == before
      refute JSON.encode!(Vxpipe.CallEngine.Error.to_public(error)) =~ "private-marker"
    end
  end

  test "saves a whole-selection override without requiring the unused default binding", ctx do
    input =
      source()
      |> put_in([:defaults, :capabilities, :model_inference, :credential_name], "unused")
      |> put_in([:participants, "assistant", :capabilities], %{
        model_inference: %{provider: "fixture", model: "local"}
      })

    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, input, ctx.options)
    assert draft.validation_errors == []
    refute :erlang.term_to_binary(draft) =~ "private-marker"
  end

  test "a credential revoked after preflight cannot authorize a revision write", ctx do
    {ProviderCredentialStore, context} =
      Keyword.fetch!(ctx.options, :provider_credential_repository)

    switch = start_supervised!({Agent, fn -> true end})

    options =
      Keyword.put(
        ctx.options,
        :provider_credential_repository,
        {Vxpipe.Persistence.TestRevokingProviderCredentialRepository,
         Keyword.put(context, :revocation_switch, switch)}
      )

    before = row_counts()

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_call_spec(ctx.tenant.key, source(), options)

    assert row_counts() == before
  end

  test "a credential revoked during preparation cannot authorize a prepared call write", ctx do
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)

    assert {:ok, published} =
             Calls.publish_call_spec(ctx.tenant.key, draft.call_spec_id, 1, ctx.options)

    assert [route] = published.routes

    {ProviderCredentialStore, context} =
      Keyword.fetch!(ctx.options, :provider_credential_repository)

    switch = start_supervised!({Agent, fn -> true end})

    options =
      Keyword.put(
        ctx.options,
        :provider_credential_repository,
        {Vxpipe.Persistence.TestRevokingProviderCredentialRepository,
         Keyword.put(context, :revocation_switch, switch)}
      )

    before = Repo.aggregate(Vxpipe.Persistence.Schema.Call, :count)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.prepare_call(ctx.principal, route.key, %{}, options)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.Call, :count) == before
  end

  test "credential validation and its authorized write share a transaction", ctx do
    {ProviderCredentialStore, context} =
      Keyword.fetch!(ctx.options, :provider_credential_repository)

    requirements = [%{provider: "google", name: "default", path: ["model_inference"]}]
    before = Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count)

    result =
      ProviderCredentialStore.with_active(context, ctx.tenant.key, requirements, fn ->
        assert Repo.in_transaction?()
        {:ok, _, _} = Administration.bootstrap_tenant("Rolled back tenant", [:calls], ctx.options)
        {:error, :controlled_write_failure}
      end)

    assert result == {:error, :controlled_write_failure}
    assert Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count) == before
  end

  test "publication rechecks a credential revoked after save", ctx do
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)
    revoke_google(ctx)

    assert {:error, error} =
             Calls.publish_call_spec(
               ctx.tenant.key,
               draft.call_spec_id,
               draft.revision,
               ctx.options
             )

    assert error.code == :provider_credential_unavailable
    assert [route] = draft.routes

    assert {:error, :route_unavailable} =
             Calls.resolve_participant_route(ctx.tenant.key, route.key, ctx.options)
  end

  test "preparation rechecks current credentials and stores no call after revocation", ctx do
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)

    assert {:ok, published} =
             Calls.publish_call_spec(
               ctx.tenant.key,
               draft.call_spec_id,
               draft.revision,
               ctx.options
             )

    assert [route] = published.routes
    revoke_google(ctx)
    before = Repo.aggregate(Vxpipe.Persistence.Schema.Call, :count)

    assert {:error, error} = Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)
    assert error.code == :provider_credential_unavailable
    assert Repo.aggregate(Vxpipe.Persistence.Schema.Call, :count) == before
  end

  test "runtime source resolves exact tenant bindings and checks revocation on every activation",
       ctx do
    {:ok, call_spec} =
      Vxpipe.CallEngine.CallSpec.new(source(), resource_id: "source-test", revision: 1)

    selection = call_spec.default_capabilities.model_inference
    options = [credential_source: {Vxpipe.Calls.ProviderCredentialSource, ctx.options}]

    assert {:ok, credential} =
             Vxpipe.CallEngine.CredentialSource.resolve(ctx.tenant.key, selection, options)

    assert credential.tenant_id == ctx.tenant.key
    assert credential.provider == "google"
    assert credential.name == "default"
    assert credential.payload == %{"api_key" => "google-inline-private-marker"}
    refute inspect(credential) =~ "inline-private-marker"

    assert {:error, :provider_credential_unavailable} =
             Vxpipe.CallEngine.CredentialSource.resolve(ctx.other.key, selection, options)

    revoke_google(ctx)

    assert {:error, :provider_credential_unavailable} =
             Vxpipe.CallEngine.CredentialSource.resolve(ctx.tenant.key, selection, options)
  end

  @tag :integration
  @tag timeout: 20_000
  test "runs a synthetic Google and Deepgram voice turn from the persisted tenant plan", ctx do
    configure_voice_transports()
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)

    assert {:ok, published} =
             Calls.publish_call_spec(ctx.tenant.key, draft.call_spec_id, 1, ctx.options)

    assert [route] = published.routes
    assert {:ok, prepared, token} = Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)

    assert {:ok, claim} =
             Calls.claim_join_token(
               token.secret,
               %{tenant_key: ctx.tenant.key, call_id: prepared.id, participant_key: route.key},
               ctx.options
             )

    plan = claim.call.plan

    before = room_supervisors()

    on_exit(fn ->
      for supervisor <- MapSet.difference(room_supervisors(), before) do
        DynamicSupervisor.terminate_child(Vxpipe.CallEngine.RoomSupervisor, supervisor)
      end
    end)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               credential_source: {Vxpipe.Calls.ProviderCredentialSource, ctx.options}
             )

    assert_receive {:test_tts_transport_started, tts, tts_connection}, 2_000
    assert tts_connection.headers == [{"Authorization", "Token deepgram-inline-private-marker"}]

    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})
    caller = plan.participants["caller"]

    assert {:ok, command} =
             Vxpipe.CallEngine.Command.AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "inline-voice-connection",
               deadline: DateTime.add(DateTime.utc_now(), 10, :second)
             )

    assert {:ok, _attachment} = Vxpipe.CallEngine.TestTransferConnection.attach(command, sink)
    Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)
    assert_receive {:test_stt_transport_started, stt, stt_connection}, 2_000
    assert stt_connection.headers == [{"Authorization", "Token deepgram-inline-private-marker"}]

    Vxpipe.CallEngine.TestSpeechToTextTransport.deliver(stt, speech_message("StartOfTurn", 1))
    Vxpipe.CallEngine.TestSpeechToTextTransport.deliver(stt, speech_message("EndOfTurn", 2))
    assert_receive {:tenant_google_request, request}, 5_000
    assert request.scheme == :https
    assert request.host == "generativelanguage.googleapis.com"
    assert {"x-goog-api-key", "google-inline-private-marker"} in request.headers
    refute request.query =~ "inline-private-marker"
    assert_receive {:test_tts_control, ^tts, speak}, 5_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Hello back."}
    assert_receive {:test_tts_control, ^tts, _flush}, 2_000

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts,
      ~s({"type":"SpeechStarted","request_id":"inline","speech_id":"voice"})
    )

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_audio(tts, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, frame}, 2_000
    assert frame.payload == <<1, 0, 2, 0>>

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts,
      ~s({"type":"SpeechMetadata","request_id":"inline","speech_id":"voice"})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn}, 2_000
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_started(sink)
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_progress(sink, 20, 20)
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_completed(sink)
  end

  @tag :integration
  test "new caller speech startup rechecks credentials after initial room preparation", ctx do
    configure_voice_transports()
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)

    assert {:ok, published} =
             Calls.publish_call_spec(ctx.tenant.key, draft.call_spec_id, 1, ctx.options)

    assert [route] = published.routes

    assert {:ok, prepared, _token} =
             Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)

    plan = prepared.plan
    before = room_supervisors()

    on_exit(fn ->
      for supervisor <- MapSet.difference(room_supervisors(), before) do
        DynamicSupervisor.terminate_child(Vxpipe.CallEngine.RoomSupervisor, supervisor)
      end
    end)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               credential_source: {Vxpipe.Calls.ProviderCredentialSource, ctx.options}
             )

    assert_receive {:test_tts_transport_started, _tts, _connection}, 2_000

    revoke_query =
      from(credential in Vxpipe.Persistence.Schema.ProviderCredential,
        join: tenant in assoc(credential, :tenant),
        where: tenant.key == ^ctx.tenant.key and credential.provider == "deepgram"
      )

    assert {1, _} = Repo.update_all(revoke_query, set: [status: "revoked"])
    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})

    assert {:ok, command} =
             Vxpipe.CallEngine.Command.AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: plan.participants["caller"].participant_id,
               connection_id: "revoked-inline-connection",
               deadline: DateTime.add(DateTime.utc_now(), 10, :second)
             )

    assert {:error, %{code: :speech_to_text_unavailable}} =
             Vxpipe.CallEngine.TestTransferConnection.attach(command, sink)

    refute_receive {:test_stt_transport_started, _stt, _connection}
  end

  defp room_supervisors do
    Vxpipe.CallEngine.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> MapSet.new()
  end

  defp configure_voice_transports do
    {:ok, options} =
      Vxpipe.AgentRuntime.ProviderSelection.translate(
        "google",
        "gemini-3.5-flash-lite",
        %{},
        %{}
      )

    assert Keyword.fetch!(options, :streaming),
           "the synthetic request adapter requires the streaming provider path"

    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    previous_adapter = Application.fetch_env(:req_llm, :finch_request_adapter)
    previous_google = Application.fetch_env(:req_llm, :google)
    previous_target = Application.fetch_env(:vxpipe_persistence, :tenant_google_stream)
    server = start_supervised!(Vxpipe.Persistence.TestTenantGoogleStream)
    port = Vxpipe.Persistence.TestTenantGoogleStream.port(server)

    Application.put_env(
      :req_llm,
      :finch_request_adapter,
      Vxpipe.Persistence.TestTenantGoogleStream
    )

    Application.put_env(:req_llm, :google,
      base_url: "https://retired-endpoint.example.test",
      api_key: "retired-private-marker"
    )

    Application.put_env(:vxpipe_persistence, :tenant_google_stream, {self(), port})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      settings
      |> Keyword.put(:speech_to_text,
        enabled: true,
        provider: Vxpipe.CallEngine.Provider.Deepgram.Flux,
        transport:
          {Vxpipe.CallEngine.TestSpeechToTextTransport, [observer: self(), ready_on_start: true]},
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      )
      |> Keyword.put(:text_to_speech,
        enabled: true,
        provider: Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech,
        transport:
          {Vxpipe.CallEngine.TestTextToSpeechTransport, [observer: self(), ready_on_start: true]},
        maximum_requests: 4
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

      for {app, key, value} <- [
            {:req_llm, :finch_request_adapter, previous_adapter},
            {:req_llm, :google, previous_google},
            {:vxpipe_persistence, :tenant_google_stream, previous_target}
          ] do
        case value do
          {:ok, previous} -> Application.put_env(app, key, previous)
          :error -> Application.delete_env(app, key)
        end
      end
    end)
  end

  defp speech_message(event, sequence) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "inline",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => "Hello there",
      "words" => [],
      "end_of_turn_confidence" => 0.8,
      "trigger" => "model"
    })
  end

  defp revoke_google(ctx) do
    {:ok, credentials} = ProviderCredentials.list(ctx.tenant.key, ctx.options)
    credential = Enum.find(credentials, &(&1.provider == "google"))

    Repo.update_all(
      from(c in Vxpipe.Persistence.Schema.ProviderCredential,
        where: c.public_id == ^credential.id
      ),
      set: [status: "revoked"]
    )
  end

  defp row_counts do
    Enum.map([CallSpec, CallSpecRevision, ParticipantRoute], &Repo.aggregate(&1, :count))
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Tenant voice",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          speech_to_text: %{
            provider: "deepgram",
            model: "flux-general-en",
            options: %{encoding: "opus", sample_rate: 48_000}
          },
          model_inference: %{provider: "google", model: "gemini-3.5-flash-lite"},
          text_to_speech: %{
            provider: "deepgram",
            model: "flux-haley-en",
            options: %{encoding: "linear16", sample_rate: 48_000}
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
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp destination_source(kind) do
    input = source()

    selection =
      input.defaults.capabilities |> Map.fetch!(kind) |> Map.put(:credential_name, "destination")

    destination =
      if kind == :speech_to_text do
        %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "transfer"},
          capabilities: %{speech_to_text: selection}
        }
      else
        %{
          type: "agent",
          prompt: "Handle the destination request.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{kind => selection},
          tools: %{},
          transfers: []
        }
      end

    input
    |> put_in([:participants, "assistant", :transfers], ["destination"])
    |> put_in([:participants, "destination"], destination)
  end
end
