defmodule Vxpipe.Console.MorseCodeApiServiceActivationTest do
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

  alias Vxpipe.CallEngine.Speech.ConversationalSTT
  alias Vxpipe.Providers.MorseCodeApi.{STTSession, TTSSession}

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    original = Application.fetch_env(:vxpipe_providers, :morse_code_api)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:vxpipe_providers, :morse_code_api, value)
        :error -> Application.delete_env(:vxpipe_providers, :morse_code_api)
      end
    end)

    %{
      options: [
        credential_repository: {CredentialStore, Repo},
        provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        call_spec_repository: {CallSpecStore, Repo}
      ]
    }
  end

  test "one published call retains credentials while a runtime origin switch changes its private cache identity",
       %{options: options} do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("Morse API service", [:admin], options)

    assert {:ok, platform} =
             ProviderCredentials.provision(
               :platform,
               "morse_code_api",
               "voice",
               "api_key",
               %{"api_key" => "synthetic platform compatibility key"},
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

    Application.put_env(:vxpipe_providers, :morse_code_api,
      base_url: "http://127.0.0.1:9876",
      allow_http?: true
    )

    assert {:ok, local} = PlanStartup.new(plan, runtime_options)
    assert {TTSSession, public} = local.text_to_speech.provider
    assert Keyword.fetch!(public, :model) == "morse_v1"
    assert local.text_to_speech.usage_provider.name == "morse_code_api"
    assert local.text_to_speech.asset_cache_identity["credential"]["id"] == platform.id
    assert private(local).endpoint == "http://127.0.0.1:9876"
    assert {ConversationalSTT, recognition} = stt_runtime(local).provider
    assert Keyword.fetch!(recognition, :provider) == STTSession
    assert Keyword.fetch!(recognition, :vad) == false
    assert private_stt(local).endpoint == "ws://127.0.0.1:9876"
    assert private_stt(local).api_key == private(local).api_key
    assert stt_runtime(local).usage_provider.name == "morse_code_api"

    Application.put_env(:vxpipe_providers, :morse_code_api,
      base_url: "https://hosted.morse.example"
    )

    assert {:ok, hosted} = PlanStartup.new(plan, runtime_options)
    assert private(hosted).endpoint == "https://hosted.morse.example"
    assert private(hosted).api_key == private(local).api_key
    assert private_stt(hosted).endpoint == "wss://hosted.morse.example"
    assert private_stt(hosted).api_key == private(hosted).api_key
    refute hosted.text_to_speech.asset_cache_identity == local.text_to_speech.asset_cache_identity

    assert {:ok, own} =
             ProviderCredentials.provision(
               tenant.key,
               "morse_code_api",
               "voice",
               "api_key",
               %{"api_key" => "synthetic tenant compatibility key"},
               options
             )

    assert {:ok, overridden} = PlanStartup.new(plan, runtime_options)
    assert private(overridden).api_key == "synthetic tenant compatibility key"
    assert private_stt(overridden).api_key == private(overridden).api_key

    refute overridden.text_to_speech.asset_cache_identity ==
             hosted.text_to_speech.asset_cache_identity

    refute inspect(overridden) =~ "compatibility key"
    refute :erlang.term_to_binary(publication) =~ "synthetic"
    refute :erlang.term_to_binary(plan) =~ "hosted.morse.example"

    assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)
    assert {:ok, restored} = PlanStartup.new(plan, runtime_options)
    assert private_stt(restored).api_key == private(hosted).api_key

    assert restored.text_to_speech.asset_cache_identity ==
             hosted.text_to_speech.asset_cache_identity

    Application.delete_env(:vxpipe_providers, :morse_code_api)
    assert {:error, _} = PlanStartup.new(plan, runtime_options)
  end

  defp private(startup), do: Keyword.fetch!(startup.text_to_speech.provider_private, :config)

  defp private_stt(startup) do
    stt_runtime(startup).provider_private
    |> Keyword.fetch!(:recognizer_private)
    |> Keyword.fetch!(:config)
  end

  defp stt_runtime(startup) do
    Map.fetch!(startup.speech_to_text_runtimes, startup.caller.participant_id)
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Morse API voice",
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
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
