defmodule Vxpipe.Console.CartesiaServiceActivationTest do
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

  alias Vxpipe.Providers.Cartesia.TTSSession
  alias Vxpipe.Providers.Cartesia.STTSession

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

  test "published Cartesia calls use a tenant override or the inherited platform key", %{
    options: options
  } do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("Cartesia service", [:admin], options)

    assert {:ok, platform} =
             ProviderCredentials.provision(
               :platform,
               "cartesia",
               "voice",
               "api_key",
               %{"api_key" => "synthetic-platform-cartesia"},
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
      text_to_speech: [providers: %{TTSSession => [enabled: true, maximum_requests: 4]}],
      speech_to_text: [
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
      ]
    ]

    assert {:ok, inherited} = PlanStartup.new(plan, runtime_options)

    assert Keyword.fetch!(inherited.text_to_speech.provider_private, :config).api_key ==
             "synthetic-platform-cartesia"

    assert inherited.text_to_speech.asset_cache_identity["credential"]["id"] == platform.id
    assert stt_key(inherited) == "synthetic-platform-cartesia"

    assert {:ok, own} =
             ProviderCredentials.provision(
               tenant.key,
               "cartesia",
               "voice",
               "api_key",
               %{"api_key" => "synthetic-tenant-cartesia"},
               options
             )

    assert {:ok, overridden} = PlanStartup.new(plan, runtime_options)

    assert Keyword.fetch!(overridden.text_to_speech.provider_private, :config).api_key ==
             "synthetic-tenant-cartesia"

    refute overridden.text_to_speech.asset_cache_identity ==
             inherited.text_to_speech.asset_cache_identity

    refute inspect(overridden) =~ "synthetic-tenant-cartesia"
    assert stt_key(overridden) == "synthetic-tenant-cartesia"
    refute :erlang.term_to_binary(publication) =~ "synthetic-"

    assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)
    assert {:ok, restored} = PlanStartup.new(plan, runtime_options)

    assert restored.text_to_speech.asset_cache_identity ==
             inherited.text_to_speech.asset_cache_identity

    assert stt_key(restored) == "synthetic-platform-cartesia"
  end

  defp stt_key(startup) do
    [runtime] = startup.speech_to_text_runtimes |> Map.values() |> Enum.reject(&is_nil/1)
    assert {STTSession, public} = runtime.provider
    assert Keyword.fetch!(public, :model) == "ink-2"
    assert runtime.usage_provider.name == "cartesia"
    Keyword.fetch!(runtime.provider_private, :config).api_key
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Cartesia voice",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          speech_to_text: %{provider: "cartesia", model: "ink-2", credential_name: "voice"},
          text_to_speech: %{
            provider: "cartesia",
            model: "sonic-3.6",
            credential_name: "voice",
            options: %{voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"}
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
