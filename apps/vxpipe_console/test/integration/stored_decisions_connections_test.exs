defmodule Vxpipe.Console.Integration.StoredDecisionsConnectionsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.Calls.{Administration, ProviderCredentialSource}
  alias Vxpipe.Console.Test.FakeUserIdentity

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.ProviderCredential, as: StoredCredential

  @moduletag :capture_log
  @providers [
    {"openai", "gpt-6-luna", "api.openai.com", "/v1/decisions"},
    {"google", "gemini-decision-1", "generativelanguage.googleapis.com", "/v1beta/decisions"},
    {"jev", "jev-1.14.0", "api.typesafe.ai", "/v1/systemone"}
  ]

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Guarded connections", [:calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)
    operator = FakeUserIdentity.principal()

    context = %{operator: operator, options: options, principal: principal, tenant: tenant.key}

    services =
      Map.new(@providers, fn {provider, _, _, _} ->
        secret =
          "synthetic-" <> provider <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(12))

        service = create_connection(context, tenant.key, provider, secret)

        ciphertext = Repo.get_by!(StoredCredential, public_id: service.id).encrypted_payload
        assert is_binary(ciphertext) and byte_size(ciphertext) > byte_size(secret)
        assert :binary.match(ciphertext, secret) == :nomatch
        {provider, {service.id, secret}}
      end)

    Map.put(context, :services, services)
  end

  for {provider, model, host, path} <- @providers do
    @provider provider
    @model model
    @host host
    @path path
    test "the published #{@provider} selection uses its encrypted named connection on a real turn",
         c do
      assert {:ok, %{providers: offerings}} =
               Calls.list_providers(c.operator, c.tenant, "decisions", c.options)

      assert Enum.any?(offerings, &(&1.id == @provider and &1.credential_available))

      assert {:ok, %{models: models}} =
               Calls.list_provider_models(c.operator, c.tenant, @provider, "decisions", c.options)

      assert Enum.any?(models, &(&1.id == @model))

      {credential_id, secret} = Map.fetch!(c.services, @provider)
      plan = prepare(c, @provider, @model)

      assert %{"id" => ^credential_id, "scope" => "tenant"} =
               Map.fetch!(plan.credential_bindings, {@provider, "policy"})

      refute :erlang.term_to_binary(plan) =~ secret
      assert_admitted(c, plan, @provider, @model, @host, @path, secret)
    end
  end

  test "a stored tenant override can rotate its API key without changing the prepared call binding",
       c do
    {id, _original} = Map.fetch!(c.services, "google")

    create_connection(c, :platform, "google", "synthetic-platform-google")

    plan = prepare(c, "google", "gemini-decision-1")

    assert %{"id" => ^id, "scope" => "tenant"} =
             Map.fetch!(plan.credential_bindings, {"google", "policy"})

    next = "synthetic-rotated-google"

    assert {:ok, %{id: ^id, version: 2}} =
             Calls.update_operator_credential(
               c.operator,
               c.tenant,
               id,
               "google",
               "api_key",
               %{"api_key" => next},
               c.options
             )

    assert_admitted(
      c,
      plan,
      "google",
      "gemini-decision-1",
      "generativelanguage.googleapis.com",
      "/v1beta/decisions",
      next
    )
  end

  test "a prepared call rejects ambient, foreign, inherited and recreated credentials before HTTP",
       c do
    {id, secret} = Map.fetch!(c.services, "openai")
    plan = prepare(c, "openai", "gpt-6-luna")
    [question] = plan.participants["agent"].guardrails.before_turn
    configure_transport("openai", secret, question.id)
    previous = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "synthetic-unused-ambient")

    on_exit(fn ->
      if previous,
        do: System.put_env("OPENAI_API_KEY", previous),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    assert {:ok, other, _} = Administration.bootstrap_tenant("Other tenant", [:calls], c.options)

    create_connection(c, other.key, "openai", "synthetic-foreign")

    assert :ok = Calls.delete_operator_credential(c.operator, c.tenant, id, c.options)
    assert_rejected(c, plan)

    create_connection(c, :platform, "openai", "synthetic-platform")

    assert_rejected(c, plan)

    replacement = create_connection(c, c.tenant, "openai", "synthetic-recreated")

    refute replacement.id == id
    assert_rejected(c, plan)
    refute_received :decisions_http_submitted
  end

  defp create_connection(c, owner, provider, key) do
    assert {:ok, connection} =
             Calls.create_operator_credential(
               c.operator,
               owner,
               provider,
               "policy",
               "api_key",
               %{"api_key" => key},
               c.options
             )

    connection
  end

  defp assert_rejected(c, plan) do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    options = [
      owner: self(),
      credential_source: {ProviderCredentialSource, c.options},
      agent_runtime: Keyword.fetch!(settings, :agent_runtime)
    ]

    assert {:error,
            %{
              code: :unsupported_call_plan,
              details: %{"path" => ["defaults", "capabilities", "decisions"]}
            }} =
             CallEngine.PlanStartup.new(plan, options)
  end

  defp assert_admitted(c, plan, provider, model, host, path, secret) do
    [question] = plan.participants["agent"].guardrails.before_turn
    question_id = question.id
    configure_transport(provider, secret, question_id)

    assert {:ok, room} =
             CallEngine.TestCallStartup.start_call(plan,
               credential_source: {ProviderCredentialSource, c.options},
               archive: [
                 enabled: true,
                 writer: {CallEngine.TestCollectingArchiveWriter, self()},
                 maximum_pending_facts: 64,
                 retry_delay_ms: 5,
                 drain_timeout_ms: 1_000
               ]
             )

    identity = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: plan.participants["caller"].participant_id,
      connection_id: "stored-decisions",
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    ]

    assert {:ok, attach} = AttachConnection.new(identity)
    assert {:ok, attachment} = CallEngine.attach_connection(attach)
    CallEngine.TestCallStartup.await_ready(attachment)

    assert {:ok, input} =
             SendText.new(
               identity ++ [correlation_id: "input", content: "My invoice", audio_response: false]
             )

    assert :ok = CallEngine.send_text(input)

    wire_model = if provider == "google", do: "models/" <> model, else: model
    assert_receive {:submitted, ^host, ^path, true, ^wire_model, "My invoice"}, 2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{
                        "selected_provider" => ^provider,
                        "selected_model" => ^model,
                        "outcome" => "passed",
                        "question_ids" => [^question_id],
                        "attempt_ids" => [_]
                      }
                    }},
                   2_000

    assert_receive {:test_agent_runtime_stream, _, _}, 2_000
  end

  defp prepare(c, provider, model) do
    source = %{
      schema_version: "20261128.01",
      name: "Configured guardrail",
      incoming_call: %{caller: "caller", handled_by: "agent"},
      media_policy: %{save_transcripts: true},
      opening_audio: nil,
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "test"},
          text_to_speech: %{provider: "morse", model: "morse"},
          decisions: %{provider: provider, model: model, credential_name: "policy"}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "agent" => %{
          type: "agent",
          prompt: "Help.",
          first_message: %{mode: "wait_for_input"},
          guardrails: %{
            before_turn: [%{question: "Is this about billing?", required_answer: "yes"}]
          }
        }
      }
    }

    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source, c.options)

    assert {:ok, %{routes: [route]}} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    assert {:ok, prepared, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)
    assert {:ok, stored} = Calls.fetch_call(c.tenant, prepared.id, c.options)
    stored.plan
  end

  defp configure_transport(provider, secret, id) do
    observer = self()

    plug = fn conn ->
      send(observer, :decisions_http_submitted)
      body = JSON.decode!(Req.Test.raw_body(conn))
      packet = body["state"] || JSON.decode!(body["input"])

      {header, expected} =
        if provider == "google",
          do: {"x-goog-api-key", secret},
          else: {"authorization", "Bearer " <> secret}

      authenticated? = Plug.Conn.get_req_header(conn, header) == [expected]

      send(
        observer,
        {:submitted, conn.host, conn.request_path, authenticated?, body["model"],
         packet["current"]["text"]}
      )

      answers =
        case body["questions"] do
          [%{"name" => ^id, "type" => "predicate"}] ->
            [%{name: id, type: "predicate", probability: 0.97}]

          %{^id => %{"type" => "noul"}} ->
            %{id => %{type: "noul", noul: 0.97}}
        end

      Req.Test.json(conn, %{model: body["model"], answers: answers})
    end

    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      Keyword.merge(Keyword.fetch!(original, :agent_runtime),
        fixture: {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]},
        decisions_http_plug: plug
      )

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(original, :agent_runtime, runtime)
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end
end
