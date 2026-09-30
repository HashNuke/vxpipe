defmodule Vxpipe.Console.ElevenLabsServiceActivationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, PlanStartup}
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}

  alias Vxpipe.Persistence.{
    CredentialKeyring,
    CredentialStore,
    CallSpecStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Providers.ElevenLabs.TTSSession

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo}
    ]

    %{options: options}
  end

  test "published ElevenLabs calls use a tenant override or the inherited platform key", %{
    options: options
  } do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("ElevenLabs service", [:admin], options)

    assert {:ok, platform} =
             ProviderCredentials.provision(
               :platform,
               "elevenlabs",
               "voice",
               "api_key",
               %{"api_key" => "synthetic-platform-elevenlabs"},
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
               actor_id: "operator-test"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    runtime_options = [
      owner: self(),
      credential_source: {ProviderCredentialSource, options},
      agent_runtime:
        Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
        |> Keyword.fetch!(:agent_runtime),
      text_to_speech: [providers: %{TTSSession => [enabled: true, maximum_requests: 4]}]
    ]

    assert {:ok, inherited} = PlanStartup.new(plan, runtime_options)

    assert Keyword.fetch!(inherited.text_to_speech.provider_private, :config).api_key ==
             "synthetic-platform-elevenlabs"

    assert inherited.text_to_speech.asset_cache_identity["credential"]["id"] == platform.id

    assert {:ok, own} =
             ProviderCredentials.provision(
               tenant.key,
               "elevenlabs",
               "voice",
               "api_key",
               %{"api_key" => "synthetic-tenant-elevenlabs"},
               options
             )

    assert {:ok, overridden} = PlanStartup.new(plan, runtime_options)

    assert Keyword.fetch!(overridden.text_to_speech.provider_private, :config).api_key ==
             "synthetic-tenant-elevenlabs"

    refute overridden.text_to_speech.asset_cache_identity ==
             inherited.text_to_speech.asset_cache_identity

    refute inspect(overridden) =~ "synthetic-tenant-elevenlabs"
    refute :erlang.term_to_binary(publication) =~ "synthetic-"

    assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)
    assert {:ok, restored} = PlanStartup.new(plan, runtime_options)

    assert restored.text_to_speech.asset_cache_identity ==
             inherited.text_to_speech.asset_cache_identity

    assert Keyword.fetch!(restored.text_to_speech.provider_private, :config).api_key ==
             "synthetic-platform-elevenlabs"

    assert {TTSSession, public} = restored.text_to_speech.provider
    assert Keyword.fetch!(public, :model) == "eleven_flash_v2_5"
    assert restored.text_to_speech.usage_provider.name == "elevenlabs"
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "ElevenLabs voice",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          text_to_speech: %{
            provider: "elevenlabs",
            model: "eleven_flash_v2_5",
            credential_name: "voice",
            options: %{voice: "JBFqnCBsd6RMkjVDRZzb"}
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
end
