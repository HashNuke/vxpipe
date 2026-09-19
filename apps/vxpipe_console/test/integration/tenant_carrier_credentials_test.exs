defmodule Vxpipe.Console.TenantCarrierCredentialsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.ServiceRegistry

  alias Vxpipe.Persistence.{
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore
  }

  @moduletag :integration
  @origin "https://voice.example.test/voice"
  @timestamp 1_789_123_500
  @account "AC00000000000000000000000000000000"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context}
    ]

    {:ok, first, _} = Administration.bootstrap_tenant("First carrier tenant", [:admin], options)
    {:ok, second, _} = Administration.bootstrap_tenant("Second carrier tenant", [:admin], options)
    %{tenants: [first, second], options: options, context: context}
  end

  test "encrypted tenant records supply both existing carrier readers and real webhook verification",
       data do
    registry =
      ServiceRegistry.init!(
        enabled: true,
        public_base_url: @origin,
        telephony_service_repository: {TelephonyServiceStore, data.context}
      )

    for provider <- ["telnyx", "twilio"] do
      records = Enum.map(data.tenants, &provision(&1.key, provider, data.options))

      for {service, secret, signing_key} <- records do
        reference = TelephonyServices.reference(service)

        assert {:ok, configured} =
                 ServiceRegistry.fetch_for_tenant(
                   registry,
                   service.name,
                   service.tenant_key,
                   reference
                 )

        assert {:ok, incoming} = ServiceRegistry.fetch(registry, service.ingress_key)
        assert incoming == configured
        assert configured.identity.scope == {:tenant, service.tenant_key}
        key = if provider == "twilio", do: :auth_token, else: :api_key
        assert Keyword.fetch!(configured.adapter_options, key) == secret
        refute inspect(configured) =~ secret

        endpoint =
          Endpoint.init(
            telephony: [
              enabled: true,
              public_base_url: @origin,
              provider_credential_repository: {ProviderCredentialStore, data.context},
              telephony_service_repository: {TelephonyServiceStore, data.context},
              clock: fn -> @timestamp end,
              handler:
                {Vxpipe.Gateway.TestTelephonyIngress,
                 {self(), {:ok, "wss://voice.example.test/media/test-token"}}}
            ]
          )

        assert request(endpoint, service, signing_key).status == 200
        assert_receive {:telephony_event, identity, _event}
        assert identity.service_reference == reference

        {_other_service, _other_secret, other_key} =
          Enum.find(records, fn {other, _, _} -> other.id != service.id end)

        assert request(endpoint, service, other_key).status == 401
        refute_receive {:telephony_event, _identity, _event}
      end
    end
  end

  defp provision(tenant, provider, options) do
    secret = "private-test-key-#{tenant}-#{provider}"

    {public_key, signing_key, kind, payload, account} =
      case provider do
        "telnyx" ->
          {public, private} = :crypto.generate_key(:eddsa, :ed25519)

          {Base.encode64(public), private, "api_key",
           %{"api_key" => secret, "public_key" => Base.encode64(public)}, "connection-#{tenant}"}

        "twilio" ->
          {nil, secret, "account_sid_auth_token",
           %{"account_sid" => @account, "auth_token" => secret}, @account}
      end

    name = if provider == "telnyx", do: "telnyx", else: "phone"

    assert {:ok, credential} =
             ProviderCredentials.provision(tenant, provider, name, kind, payload, options)

    attributes = %{
      "name" => "phone-#{provider}",
      "ingress_key" => "#{provider}-#{tenant}",
      "provider" => provider,
      "provider_connection_id" => account,
      "credential_id" => credential.id
    }

    attributes =
      if public_key,
        do: attributes |> Map.delete("credential_id") |> Map.put("credential_name", "telnyx"),
        else: attributes

    assert {:ok, service} = TelephonyServices.register(tenant, attributes, options)
    assert {:ok, snapshot} = TelephonyServices.resolve(tenant, service.name, options)
    {snapshot.service, secret, signing_key}
  end

  defp request(endpoint, %{provider: "telnyx"} = service, key) do
    body =
      JSON.encode!(%{
        "data" => %{
          "record_type" => "event",
          "event_type" => "call.initiated",
          "id" => "same-event",
          "occurred_at" => "2026-09-11T09:45:00Z",
          "payload" => %{
            "direction" => "incoming",
            "connection_id" => service.provider_connection_id,
            "call_control_id" => "same-control",
            "call_leg_id" => "same-leg",
            "call_session_id" => "same-session",
            "from" => "+15550001001",
            "to" => "+15550001000"
          }
        }
      })

    timestamp = Integer.to_string(@timestamp)
    signature = :crypto.sign(:eddsa, :none, timestamp <> "|" <> body, [key, :ed25519])

    :post
    |> conn("/webhooks/tenants/#{service.tenant_key}/telnyx", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", Base.encode64(signature))
    |> Endpoint.call(endpoint)
  end

  defp request(endpoint, %{provider: "twilio"} = service, key) do
    parameters = %{
      "AccountSid" => @account,
      "CallSid" => "CA00000000000000000000000000000001",
      "CallStatus" => "ringing",
      "Direction" => "inbound",
      "From" => "+15550001001",
      "To" => "+15550001000"
    }

    path = "/api/telephony/twilio/#{service.ingress_key}/voice"

    input =
      parameters
      |> Enum.sort()
      |> Enum.reduce(@origin <> path, fn {key, value}, acc -> acc <> key <> value end)

    signature = :crypto.mac(:hmac, :sha, key, input) |> Base.encode64()

    :post
    |> conn(path, URI.encode_query(parameters))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-twilio-signature", signature)
    |> Endpoint.call(endpoint)
  end
end
