defmodule Vxpipe.Persistence.EntryOpeningPublicationTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    CallSpecAuthoring,
    InstallationOperator,
    ProviderCredentials
  }

  alias Vxpipe.Persistence.{
    CallStore,
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore
  }

  test "upgrading a human-only call reauthorizes its inherited opening voice and preserves older publications" do
    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Opening voice", [:admin, :calls], options)

    {:ok, author} = Administration.authenticate(tenant.key, issued.secret, :admin, options)
    operator = InstallationOperator.authority()

    {:ok, _} =
      ProviderCredentials.provision(
        :platform,
        "deepgram",
        "opening-voice",
        "api_key",
        %{"api_key" => "synthetic-platform"},
        options
      )

    legacy = legacy_source()
    assert {:ok, old} = CallSpecAuthoring.save(author, tenant.key, legacy, options)
    id = old.call_spec_id
    assert {:ok, published} = CallSpecAuthoring.publish(author, tenant.key, id, 1, options)
    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    assert {:ok, historical, _token} = Calls.prepare_call(author, route.key, %{}, options)
    assert historical.plan.opening_audio.text_to_speech.provider == "morse"

    upgraded =
      legacy
      |> Map.put(:schema_version, "20261125.01")
      |> update_in([:opening_audio], &Map.delete(&1, :text_to_speech))

    update_options = Keyword.put(options, :call_spec_id, id)

    assert {:error,
            %{
              code: :provider_service_forbidden,
              details: %{"path" => ["defaults", "capabilities", "text_to_speech"]}
            }} =
             CallSpecAuthoring.save(author, tenant.key, upgraded, update_options)

    assert {:ok, %{revision: 2}} =
             CallSpecAuthoring.save(operator, tenant.key, upgraded, update_options)

    assert {:error, %{code: :provider_service_forbidden}} =
             CallSpecAuthoring.publish(author, tenant.key, id, 2, options)

    assert {:ok, _} = CallSpecAuthoring.publish(operator, tenant.key, id, 2, options)
    assert {:ok, restored} = CallSpecAuthoring.publish(author, tenant.key, id, 1, options)
    assert restored.source["opening_audio"]["text_to_speech"]["provider"] == "morse"
  end

  defp legacy_source do
    voice = %{
      provider: "deepgram",
      model: "flux-haley-en",
      credential_name: "opening-voice",
      options: %{encoding: "linear16", sample_rate: 48_000}
    }

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"}
    }

    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "receiver"},
      defaults: %{capabilities: %{text_to_speech: voice}},
      participants: %{"caller" => human, "receiver" => human},
      wait_sounds: nil,
      opening_audio: %{
        type: "text",
        text: "Welcome",
        text_to_speech: %{provider: "morse", model: "morse"}
      }
    }
  end
end
