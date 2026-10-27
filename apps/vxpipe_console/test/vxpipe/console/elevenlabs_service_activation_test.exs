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
  alias Vxpipe.Providers.ElevenLabs.STTSession
  alias Vxpipe.Providers.ElevenLabs.RealtimeSession

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

  for vad <- [:omitted, false, true] do
    @vad vad
    test "published ElevenLabs calls prepare API onset choice #{vad} with tenant/platform credentials",
         %{
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

      assert {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source(@vad), options)
      assert draft.validation_errors == []

      assert {:ok, publication} =
               Vxpipe.Calls.publish_call_spec(
                 tenant.key,
                 draft.call_spec_id,
                 draft.revision,
                 options
               )

      published_stt = publication.source["defaults"]["capabilities"]["speech_to_text"]

      if @vad == :omitted,
        do: refute(Map.has_key?(published_stt, "vad")),
        else: assert(published_stt["vad"] == @vad)

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
               "synthetic-platform-elevenlabs"

      assert inherited.text_to_speech.asset_cache_identity["credential"]["id"] == platform.id
      assert stt_key(inherited, @vad == true) == "synthetic-platform-elevenlabs"

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
      assert stt_key(overridden, @vad == true) == "synthetic-tenant-elevenlabs"
      refute :erlang.term_to_binary(publication) =~ "synthetic-"

      assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)
      assert {:ok, restored} = PlanStartup.new(plan, runtime_options)

      assert restored.text_to_speech.asset_cache_identity ==
               inherited.text_to_speech.asset_cache_identity

      assert Keyword.fetch!(restored.text_to_speech.provider_private, :config).api_key ==
               "synthetic-platform-elevenlabs"

      assert {TTSSession, public} = restored.text_to_speech.provider
      assert stt_key(restored, @vad == true) == "synthetic-platform-elevenlabs"
      assert Keyword.fetch!(public, :model) == "eleven_flash_v2_5"
      assert restored.text_to_speech.usage_provider.name == "elevenlabs"
    end
  end

  for model <- ["eleven_realtime_v1_mini", "eleven_realtime_v1_max"] do
    test "published ElevenLabs #{model} inherits and overrides one saved key without local VAD",
         %{options: options} do
      model = unquote(model)
      assert {:ok, tenant, _} = Administration.bootstrap_tenant("Native STS", [:admin], options)

      assert {:ok, _platform} =
               ProviderCredentials.provision(
                 :platform,
                 "elevenlabs",
                 "voice",
                 "api_key",
                 %{"api_key" => "synthetic-platform-sts"},
                 options
               )

      source =
        put_in(source(), [:defaults, :capabilities], %{
          speech_to_speech: %{
            provider: "elevenlabs",
            model: model,
            credential_name: "voice",
            options: %{voice: "brian", turn_control: "provider"}
          }
        })

      assert {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source, options)
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
        speech_to_speech: [providers: %{RealtimeSession => [enabled: true]}],
        speech_to_text: [providers: %{}],
        text_to_speech: [providers: %{}]
      ]

      assert {:ok, inherited} = PlanStartup.new(plan, runtime_options)
      assert sts_key(inherited, model) == "synthetic-platform-sts"

      assert {:ok, own} =
               ProviderCredentials.provision(
                 tenant.key,
                 "elevenlabs",
                 "voice",
                 "api_key",
                 %{"api_key" => "synthetic-tenant-sts"},
                 options
               )

      assert {:ok, overridden} = PlanStartup.new(plan, runtime_options)
      assert sts_key(overridden, model) == "synthetic-tenant-sts"
      assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)
      assert {:ok, restored} = PlanStartup.new(plan, runtime_options)
      assert sts_key(restored, model) == "synthetic-platform-sts"
      refute :erlang.term_to_binary(publication) =~ "synthetic-"
    end
  end

  defp sts_key(startup, model) do
    assert {RealtimeSession, public} = startup.speech_to_speech.provider
    assert public == [model: model, voice: "brian", turn_control: "provider"]
    assert startup.agent_activation == nil
    assert startup.text_to_speech == nil
    assert Enum.all?(startup.speech_to_text_runtimes, fn {_key, runtime} -> is_nil(runtime) end)
    assert startup.speech_to_speech.output_speech_to_text == nil
    assert startup.speech_to_speech.usage_provider.name == "elevenlabs"
    assert startup.speech_to_speech.usage_provider.model == model
    refute inspect(startup) =~ "synthetic-"

    startup.speech_to_speech.provider_private
    |> Keyword.fetch!(:config)
    |> Map.fetch!(:api_key)
  end

  defp stt_key(startup, vad) do
    [runtime] = startup.speech_to_text_runtimes |> Map.values() |> Enum.reject(&is_nil/1)
    assert {Vxpipe.CallEngine.Speech.ConversationalSTT, composed} = runtime.provider
    assert Keyword.fetch!(composed, :vad) == vad
    assert Keyword.fetch!(composed, :provider) == STTSession
    public = Keyword.fetch!(composed, :options)
    assert Keyword.fetch!(public, :commit_strategy) == :vad
    assert Keyword.fetch!(public, :model) == "scribe_v2_realtime"
    assert runtime.usage_provider.name == "elevenlabs"

    runtime.provider_private
    |> Keyword.fetch!(:recognizer_private)
    |> Keyword.fetch!(:config)
    |> Map.fetch!(:api_key)
  end

  test "API rejects invalid onset choices before publication", %{options: options} do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("Onset validation", [:admin], options)

    for invalid <- [nil, "false", 0] do
      assert {:error, error} = Vxpipe.Calls.save_call_spec(tenant.key, source(invalid), options)
      assert error.details["path"] == ["defaults", "capabilities", "speech_to_text", "vad"]
    end
  end

  defp source(:omitted), do: source()

  defp source(vad) do
    put_in(source(), [:defaults, :capabilities, :speech_to_text, :vad], vad)
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
          speech_to_text: %{
            provider: "elevenlabs",
            model: "scribe_v2_realtime",
            credential_name: "voice"
          },
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
