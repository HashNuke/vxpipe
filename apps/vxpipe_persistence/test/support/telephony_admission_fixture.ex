defmodule Vxpipe.Persistence.TestTelephonyAdmissionFixture do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Persistence.{CallStore, CredentialKeyring, CredentialStore, DefinitionStore, Repo}
  alias Vxpipe.Persistence.{ProviderCredentialStore, TelephonyServiceStore}

  def new do
    {:ok, keyring} =
      CredentialKeyring.new("current", %{"current" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, _issued} =
      Administration.bootstrap_tenant("Incoming credentials", [:calls], options)

    {:ok, credential} = provision(tenant.key, "telnyx", "phone", options)

    {:ok, service} =
      TelephonyServices.register(
        tenant.key,
        %{
          "name" => "support",
          "ingress_key" => "incoming-#{tenant.key}",
          "provider" => "telnyx",
          "provider_connection_id" => "connection-1",
          "credential_id" => credential.id,
          "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
        },
        options
      )

    %{tenant: tenant, credential: credential, service: service, options: options}
  end

  def provision(tenant, provider, name, options),
    do:
      ProviderCredentials.provision(
        tenant,
        provider,
        name,
        "api_key",
        %{"api_key" => "incoming-private-marker"},
        options
      )

  def incoming(data, options),
    do: Calls.claim_incoming_telephony({:tenant, data.tenant.key}, "support", event(), options)

  def publish(data, input) do
    {:ok, draft} = Calls.save_definition(data.tenant.key, input, data.options)

    {:ok, published} =
      Calls.publish_definition(data.tenant.key, draft.definition_id, 1, data.options)

    published
  end

  def event do
    %Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "event-1",
      provider_connection_id: "connection-1",
      provider_call_control_id: "control-1",
      provider_call_leg_id: "leg-1",
      provider_call_session_id: "session-1",
      occurred_at: ~U[2026-09-16 00:00:00Z],
      from: "+15550001001",
      to: "+15550001000"
    }
  end

  def source do
    %{
      schema_version: "20260915.01",
      name: "Incoming credentials",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "support",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"}
        }
      }
    }
  end
end
