defmodule Vxpipe.Console.Integration.UniversalReplyHangupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallStarted}

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  @moduletag :live_providers
  @moduletag :live_universal_hangup
  @moduletag :capture_log
  @moduletag timeout: 120_000

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      access_key_repository: {AccessKeyStore, Repo},
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{}},
      publication_enabled: false
    ]

    %{options: Keyword.put(options, :credential_source, {ProviderCredentialSource, options})}
  end

  for {provider, tag} <- [{"google", :live_gemini}, {"openai", :live_openai}] do
    @tag tag
    test "published #{provider} agent invokes the authorized real Hangup action", context do
      provider = unquote(provider)
      selection = Vxpipe.Providers.LiveModels.llm(provider)
      options = context.options

      {:ok, tenant, issued} =
        Administration.bootstrap_tenant("Synthetic Hangup acceptance", [:admin, :calls], options)

      {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

      assert {:ok, _} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 "llm",
                 "api_key",
                 %{"api_key" => System.fetch_env!(selection.env)},
                 options
               )

      assert {:ok, draft} = Calls.save_call_spec(tenant.key, source(provider, selection), options)
      assert draft.validation_errors == []

      assert {:ok, published} =
               Calls.publish_call_spec(tenant.key, draft.call_spec_id, draft.revision, options)

      [route] = published.routes
      assert {:ok, prepared, _token} = Calls.prepare_call(principal, route.key, %{}, options)
      plan = prepared.plan
      assert plan.agent_protocol["version"] == "mode_message_v1"

      assert {:ok, room} =
               CallEngine.TestCallStartup.start_call(plan,
                 credential_source: {ProviderCredentialSource, options}
               )

      caller = Map.fetch!(plan.participants, plan.entry_caller)
      connection = "synthetic-hangup-caller"

      assert {:ok, attach} =
               AttachConnection.new(
                 tenant_id: plan.tenant_id,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: caller.participant_id,
                 connection_id: connection,
                 deadline: DateTime.add(DateTime.utc_now(), 10, :second)
               )

      assert {:ok, attachment} = CallEngine.attach_connection(attach)
      CallEngine.TestCallStartup.await_ready(attachment)

      assert {:ok, command} =
               SendText.new(
                 tenant_id: plan.tenant_id,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: caller.participant_id,
                 connection_id: connection,
                 correlation_id: "controlled-hangup",
                 content: "Please end this synthetic test call now by calling end_call.",
                 deadline: DateTime.add(DateTime.utc_now(), 60, :second)
               )

      started = System.monotonic_time(:millisecond)
      assert :ok = CallEngine.send_text(command)

      assert_receive {:vxpipe_event,
                      %ToolCallStarted{name: "end_call", arguments: %{}, tool_call_id: id}},
                     60_000

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: ^id, result: %{"status" => "ending"}}},
                     10_000

      monitor = attachment.room_monitor
      assert_receive {:DOWN, ^monitor, :process, _, _}, 10_000
      refute_received {:vxpipe_event, %ToolCallStarted{}}

      IO.puts(
        "UNIVERSAL_HANGUP_EVIDENCE " <>
          JSON.encode!(%{
            provider: provider,
            model: selection.model,
            protocol: "mode_message_v1",
            native_action: "hangup",
            outcome: "ended",
            elapsed_ms: System.monotonic_time(:millisecond) - started
          })
      )
    end
  end

  defp source(provider, selection) do
    %{
      schema_version: "20260915.01",
      name: "Synthetic universal reply Hangup",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          first_message: %{mode: "wait_for_input"},
          prompt:
            "You are a synthetic office receptionist. When explicitly asked to end the call, invoke end_call exactly once. Do not call current_time unless asked for the time. Do not speak before the requested Hangup action.",
          capabilities: %{
            model_inference: %{
              provider: provider,
              model: selection.model,
              credential_name: "llm",
              options: %{max_tokens: 2_048},
              provider_options: selection.specific
            }
          },
          tools: %{
            "end_call" => %{type: "platform", tool: "hangup"},
            "current_time" => %{type: "platform", tool: "get_current_time"}
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 120_000}
    }
  end
end
