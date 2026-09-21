defmodule Vxpipe.Persistence.Integration.DestinationCredentialActivationTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{TextOutput, ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.CallEngine.{TestCallStartup, TestTransferConnection, TestTurnCall}
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}

  alias Vxpipe.Persistence.{
    CallStore,
    CredentialCipher,
    CredentialKeyring,
    CredentialStore,
    CallSpecStore,
    ProviderCredentialStore,
    TestTenantGoogleStream
  }

  @moduletag :integration
  @moduletag timeout: 20_000

  setup tags do
    assert {:ok, keyring} =
             CredentialKeyring.new("destination-key", %{
               "destination-key" => :crypto.strong_rand_bytes(32)
             })

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, issued} =
             Administration.bootstrap_tenant("Destination tenant", [:calls], options)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued.secret, :calls, options)

    credentials =
      Map.new(["google", "deepgram"], fn provider ->
        assert {:ok, credential} =
                 ProviderCredentials.provision(
                   tenant.key,
                   provider,
                   "destination",
                   "api_key",
                   %{"api_key" => provider <> "-old-private-marker"},
                   options
                 )

        {provider, credential}
      end)

    configure_adapters(Map.get(tags, :model_reply, false))
    assert {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)

    assert {:ok, published} =
             Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    assert [route] = published.routes
    assert {:ok, prepared, _token} = Calls.prepare_call(principal, route.key, %{}, options)
    plan = prepared.plan
    before = room_supervisors()

    on_exit(fn ->
      for supervisor <- MapSet.difference(room_supervisors(), before) do
        DynamicSupervisor.terminate_child(Vxpipe.CallEngine.RoomSupervisor, supervisor)
      end
    end)

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               credential_source: {Vxpipe.Calls.ProviderCredentialSource, options},
               archive: [
                 enabled: true,
                 writer: {Vxpipe.CallEngine.TestCollectingArchiveWriter, self()},
                 maximum_pending_facts: 64,
                 retry_delay_ms: 5,
                 drain_timeout_ms: 1_000
               ]
             )

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "destination-connection",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = TestTransferConnection.attach(attach, sink)
    TestCallStartup.await_ready(plan.room_id)

    refute :erlang.term_to_binary({draft, prepared}) =~ "private-marker"
    [plan: plan, room: room, caller: caller, credentials: credentials, keyring: keyring]
  end

  @tag model_reply: true
  test "a later activation authenticates with the current DB payloads", ctx do
    for provider <- ["google", "deepgram"] do
      replace_test_payload(ctx, provider, provider <> "-current-private-marker")
    end

    request_transfer(ctx)

    assert_receive {:test_tts_transport_started, _tts, connection}, 2_000
    assert connection.headers == [{"Authorization", "Token deepgram-current-private-marker"}]

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "destination-credentials"}},
                   2_000

    assert :ok = TestTransferConnection.send_text(text_command(ctx, "Hello destination."))
    assert_receive {:tenant_google_request, request}, 5_000
    assert {"x-goog-api-key", "google-current-private-marker"} in request.headers
    assert request.host == "generativelanguage.googleapis.com"
    refute request.query =~ "private-marker"

    destination = Map.fetch!(ctx.plan.participants, "destination")
    destination_id = destination.participant_id

    assert_receive {:vxpipe_event,
                    %TextOutput{participant_id: ^destination_id, text: "Hello back."}},
                   5_000

    assert_receive {:test_archive_fact, %Fact{kind: :participant_transfer_completed} = fact},
                   2_000

    refute :erlang.term_to_binary(fact) =~ "private-marker"
    refute :erlang.term_to_binary(ctx.plan) =~ "private-marker"
  end

  for provider <- ["google", "deepgram"] do
    @provider provider

    test "an inactive #{@provider} binding fails destination preparation before any request",
         ctx do
      credential = Map.fetch!(ctx.credentials, @provider)

      assert {1, _} =
               Repo.update_all(
                 from(c in Vxpipe.Persistence.Schema.ProviderCredential,
                   where: c.public_id == ^credential.id
                 ),
                 set: [status: "revoked"]
               )

      request_transfer(ctx)

      assert_receive {:vxpipe_event,
                      %ToolCallFailed{
                        tool_call_id: "destination-credentials",
                        reason: :tool_failed
                      } = event},
                     2_000

      assert_receive {:test_archive_fact, %Fact{kind: :participant_transfer_failed} = fact}, 2_000
      assert fact.payload["cause"] == "destination_plan_unavailable"
      refute :erlang.term_to_binary({event, fact}) =~ "private-marker"
      refute_receive {:test_tts_transport_started, _, _}
      refute_receive {:tenant_google_request, _}

      assert_receive {:test_agent_runtime_stream, source, _continuation}, 2_000
      assert {:ok, response} = ModelResponse.new(text: "The source remains available.")
      send(source, {:test_agent_runtime_response, {:ok, response}})
      source_id = Map.fetch!(ctx.plan.participants, ctx.plan.entry_receiver).participant_id

      assert_receive {:vxpipe_event,
                      %TextOutput{
                        participant_id: ^source_id,
                        text: "The source remains available."
                      }},
                     2_000
    end
  end

  defp request_transfer(ctx) do
    assert :ok =
             TestTransferConnection.send_text(text_command(ctx, "Transfer to the destination."))

    assert_receive {:test_agent_runtime_stream, source, _request}, 2_000

    assert {:ok, call} =
             ToolCall.new(
               id: "destination-credentials",
               name: "transfer",
               arguments: %{"destination" => "destination"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(source, {:test_agent_runtime_response, {:ok, response}})
  end

  defp text_command(ctx, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: ctx.plan.tenant_id,
               actor_id: ctx.plan.actor_id,
               room_id: ctx.plan.room_id,
               incarnation_id: ctx.room.incarnation_id,
               participant_id: ctx.caller.participant_id,
               connection_id: "destination-connection",
               content: content,
               audio_response: false,
               correlation_id:
                 "destination-turn-#{System.unique_integer([:positive, :monotonic])}",
               deadline: future_deadline()
             )

    command
  end

  # Change only test database state to distinguish a fresh read from a cached payload.
  defp replace_test_payload(ctx, provider, value) do
    credential = Map.fetch!(ctx.credentials, provider)

    assert {:ok, key_id, ciphertext} =
             CredentialCipher.encrypt(ctx.keyring, credential, %{"api_key" => value})

    assert {1, _} =
             Repo.update_all(
               from(c in Vxpipe.Persistence.Schema.ProviderCredential,
                 where: c.public_id == ^credential.id
               ),
               set: [encrypted_payload: ciphertext, encryption_key_id: key_id]
             )
  end

  defp configure_adapters(model_reply?) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    previous_adapter = Application.fetch_env(:req_llm, :finch_request_adapter)
    previous_target = Application.fetch_env(:vxpipe_persistence, :tenant_google_stream)

    port =
      if model_reply?,
        do: TestTenantGoogleStream.port(start_supervised!(TestTenantGoogleStream)),
        else: 0

    Application.put_env(:req_llm, :finch_request_adapter, TestTenantGoogleStream)
    Application.put_env(:vxpipe_persistence, :tenant_google_stream, {self(), port})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.update!(
        :agent_runtime,
        &Keyword.put(
          &1,
          :fixture,
          {Vxpipe.CallEngine.TestAgentRuntimeModelProvider, [owner: self()]}
        )
      )
      |> Keyword.put(:text_to_speech,
        providers: %{
          Vxpipe.Providers.Deepgram.TTSSession => [
            enabled: true,
            wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
            wire_options: [observer: self(), ready_on_start: true],
            maximum_requests: 4
          ]
        }
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)

      for {app, name, previous} <- [
            {:req_llm, :finch_request_adapter, previous_adapter},
            {:vxpipe_persistence, :tenant_google_stream, previous_target}
          ] do
        case previous do
          {:ok, value} -> Application.put_env(app, name, value)
          :error -> Application.delete_env(app, name)
        end
      end
    end)
  end

  defp source do
    TestTurnCall.call_spec()
    |> put_in([:participants, "receiver", :transfers], ["destination"])
    |> put_in([:participants, "destination"], %{
      type: "agent",
      prompt: "Help at the destination.",
      first_message: %{mode: "wait_for_input"},
      capabilities: %{
        model_inference: %{
          provider: "google",
          model: "gemini-3.5-flash-lite",
          credential_name: "destination"
        },
        text_to_speech: %{
          provider: "deepgram",
          model: "flux-haley-en",
          credential_name: "destination",
          options: %{encoding: "linear16", sample_rate: 48_000}
        }
      },
      tools: %{},
      transfers: []
    })
  end

  defp room_supervisors do
    Vxpipe.CallEngine.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> MapSet.new()
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 10, :second)
end
