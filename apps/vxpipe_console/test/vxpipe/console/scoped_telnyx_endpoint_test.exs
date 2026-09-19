defmodule Vxpipe.Console.ScopedTelnyxEndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount

  alias Vxpipe.Persistence.{
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore
  }

  @now 1_789_123_500

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, keyring} = CredentialKeyring.new("scope", %{"scope" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context}
    ]

    previous = Endpoint.config(:gateway_mount)
    on_exit(fn -> Phoenix.Config.put(Endpoint, :gateway_mount, previous) end)

    mount =
      Mount.init(
        telephony: [
          enabled: true,
          public_base_url: "https://voice.example.test",
          provider_credential_repository: {ProviderCredentialStore, context},
          telephony_service_repository: {TelephonyServiceStore, context},
          handler: {__MODULE__, self()},
          clock: fn -> @now end
        ]
      )

    Phoenix.Config.put(Endpoint, :gateway_mount, mount)
    %{options: options}
  end

  test "Phoenix serves signed scope routes from persisted credentials and honors tenant presence",
       data do
    {platform_public, platform_private} = :crypto.generate_key(:eddsa, :ed25519)
    {:ok, _platform} = provision(:platform, platform_public, data.options)

    services =
      for name <- ["First inheritor", "Second inheritor"] do
        {:ok, tenant, _} = Administration.bootstrap_tenant(name, [:admin], data.options)

        {:ok, service} =
          TelephonyServices.register(
            tenant.key,
            %{
              "name" => "phone",
              "provider" => "telnyx",
              "credential_name" => "telnyx",
              "provider_connection_id" => "application-#{tenant.key}",
              "ingress_key" => "ingress-#{tenant.key}"
            },
            data.options
          )

        assert signed(:platform, service, platform_private).status == 200
        assert_receive {:verified_service, identity}
        assert identity.scope == {:tenant, tenant.key}
        assert identity.service_reference.credential_owner == :platform
        assert signed({:tenant, tenant.key}, service, platform_private).status == 404
        service
      end

    [first, second] = services
    {tenant_public, tenant_private} = :crypto.generate_key(:eddsa, :ed25519)
    {:ok, own} = provision(second.tenant_key, tenant_public, data.options)
    scope = {:tenant, second.tenant_key}
    assert signed(scope, second, tenant_private).status == 200
    assert_receive {:verified_service, identity}
    assert identity.service_reference.credential_owner == scope
    assert signed(scope, second, platform_private).status == 401
    assert signed(:platform, second, tenant_private).status == 401
    assert signed(:platform, second, platform_private).status == 403
    assert signed(scope, first, tenant_private).status == 403
    refute_received {:verified_service, _}

    assert :ok = ProviderCredentials.delete(second.tenant_key, own.id, data.options)
    assert signed(:platform, second, platform_private).status == 200
    assert_receive {:verified_service, inherited}
    assert inherited.service_reference.credential_owner == :platform
    assert signed(scope, second, tenant_private).status == 404
  end

  def handle_event(observer, service, _event, _owner) do
    send(observer, {:verified_service, service.identity})
    :ok
  end

  defp provision(scope, public, options),
    do:
      ProviderCredentials.provision(
        scope,
        "telnyx",
        "telnyx",
        "api_key",
        %{"api_key" => "synthetic-encrypted-telnyx", "public_key" => Base.encode64(public)},
        options
      )

  defp signed(scope, service, private) do
    body =
      JSON.encode!(%{
        data: %{
          record_type: "event",
          event_type: "call.initiated",
          id: "event-1",
          occurred_at: "2026-09-11T11:00:00Z",
          payload: %{
            direction: "incoming",
            connection_id: service.provider_connection_id,
            call_control_id: "control",
            call_leg_id: "leg",
            call_session_id: "session",
            from: "+15550001001",
            to: "+15550001000"
          }
        }
      })

    path =
      case scope do
        :platform -> "/webhooks/platform/telnyx"
        {:tenant, tenant} -> "/webhooks/tenants/#{tenant}/telnyx"
      end

    timestamp = Integer.to_string(@now)
    signature = :crypto.sign(:eddsa, :none, timestamp <> "|" <> body, [private, :ed25519])

    conn(:post, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", Base.encode64(signature))
    |> Endpoint.call(Endpoint.init([]))
  end
end
