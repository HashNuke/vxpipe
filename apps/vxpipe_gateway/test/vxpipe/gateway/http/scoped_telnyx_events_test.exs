defmodule Vxpipe.Gateway.HTTP.ScopedTelnyxEventsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Gateway.TestTelephonyServiceRepository, as: Repository

  @first "AAAAAAAAAAAAAAAA"
  @second "BBBBBBBBBBBBBBBB"
  @now 1_789_123_500

  setup do
    {platform_public, platform_private} = :crypto.generate_key(:eddsa, :ed25519)
    {tenant_public, tenant_private} = :crypto.generate_key(:eddsa, :ed25519)
    first = snapshot(@first, :platform, "first-app", platform_public)
    second = snapshot(@second, {:tenant, @second}, "second-app", tenant_public)

    context = %{
      observer: self(),
      snapshots: [first, second],
      credentials: %{:platform => first.credential, {:tenant, @second} => second.credential}
    }

    %{
      context: context,
      first: first,
      platform_private: platform_private,
      tenant_private: tenant_private,
      mount: mount(context)
    }
  end

  test "mounted scoped routes authenticate raw bytes and dispatch the mapped tenant", data do
    handler_id = {__MODULE__, self()}

    :ok =
      :telemetry.attach(
        handler_id,
        Vxpipe.Gateway.Telemetry.request_stop_event(),
        &__MODULE__.observe/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    for {scope, tenant, application, private} <- [
          {:platform, @first, "first-app", data.platform_private},
          {{:tenant, @second}, @second, "second-app", data.tenant_private}
        ] do
      body = body(application)
      conn = request(data.mount, scope, body, private)
      assert conn.status == 200
      assert conn.halted
      assert conn.script_name == ["voice"]
      assert get_resp_header(conn, "access-control-allow-origin") == []
      assert_receive {:operation, :telephony_webhook}
      assert_receive {:event, service, event, nil}
      assert service.identity.scope == {:tenant, tenant}
      assert service.identity.service_reference.credential_owner == scope
      assert event.provider_connection_id == application
    end
  end

  test "unverified locators never authorize dispatch and tenant URLs cannot cross tenants",
       data do
    incoming = body("first-app")

    for conn <- [
          signed(:platform, incoming, data.tenant_private),
          signed(:platform, incoming <> " ", data.platform_private, signed_body: incoming),
          signed(:platform, incoming, data.platform_private, timestamp: @now - 301)
        ] do
      assert Mount.call(conn, data.mount).status == 401
      refute_received {:event, _, _, _}
    end

    assert request(data.mount, :platform, "malformed", data.tenant_private).status == 400
    assert request(data.mount, {:tenant, @second}, incoming, data.platform_private).status == 404

    assert request(data.mount, {:tenant, "CCCCCCCCCCCCCCCC"}, incoming, data.platform_private).status ==
             404

    refute_received {:event, _, _, _}
  end

  test "tenant applications work at the platform URL and with inherited credentials", data do
    assert request(data.mount, :platform, body("second-app"), data.tenant_private).status == 200
    assert_receive {:event, service, _, nil}
    assert service.identity.scope == {:tenant, @second}

    assert request(data.mount, {:tenant, @first}, body("first-app"), data.platform_private).status ==
             200

    assert_receive {:event, inherited, _, nil}
    assert inherited.identity.scope == {:tenant, @first}
    assert inherited.identity.service_reference.credential_owner == :platform
    assert request(data.mount, :platform, body("second-app"), data.platform_private).status == 401

    assert request(data.mount, :platform, body("unknown-app"), data.platform_private).status ==
             404

    refute_received {:event, _, _, _}
  end

  test "the shared application's called number selects its tenant", data do
    first = %{
      data.first
      | service: %{
          data.first.service
          | provider_connection_id: "shared",
            application_owner: :platform
        }
    }

    second = snapshot(@second, :platform, "shared", <<1::256>>)

    second = %{
      second
      | credential: first.credential,
        service: %{
          second.service
          | application_owner: :platform,
            credential_id: first.service.credential_id,
            public_key: first.service.public_key
        }
    }

    context =
      %{data.context | snapshots: [first, second], credentials: %{:platform => first.credential}}
      |> Map.put(:numbers, %{@first => "+15550001000", @second => "+15550002000"})

    shared_mount = mount(context)

    for {tenant, number} <- [{@first, "+15550001000"}, {@second, "+15550002000"}] do
      assert request(
               shared_mount,
               :platform,
               body("shared", "leg-#{tenant}", nil, number),
               data.platform_private
             ).status == 200

      assert_receive {:event, configured, _, nil}
      assert configured.identity.scope == {:tenant, tenant}
      assert configured.identity.service_reference.application_owner == :platform
    end

    assert request(
             shared_mount,
             :platform,
             body("shared", "unknown", nil, "+15550009999"),
             data.platform_private
           ).status == 404

    assert request(
             shared_mount,
             {:tenant, @first},
             body("shared", "foreign", nil, "+15550002000"),
             data.platform_private
           ).status == 404

    refute_received {:event, _, _, _}
  end

  test "a credential changed between verification and application resolution cannot dispatch",
       data do
    changed = %{
      data.first
      | credential: %{
          data.first.credential
          | credential: %{data.first.credential.credential | version: 2}
        }
    }

    context = %{data.context | snapshots: [changed]}
    conn = request(mount(context), :platform, body("first-app"), data.platform_private)
    assert conn.status == 403
    refute_received {:event, _, _, _}
  end

  test "missing public keys and invalid public origins fail closed", data do
    credential = %{
      data.first.credential
      | payload: Map.delete(data.first.credential.payload, "public_key")
    }

    context = %{data.context | credentials: %{:platform => credential}}

    assert request(mount(context), :platform, body("first-app"), data.platform_private).status ==
             404

    invalid_origin = mount(data.context, public_base_url: "http://invalid.example.test")

    assert request(invalid_origin, :platform, body("first-app"), data.platform_private).status ==
             503

    refute_received {:event, _, _, _}
  end

  test "a mapped application's stricter freshness window still applies", data do
    snapshot = %{data.first | service: %{data.first.service | webhook_tolerance_seconds: 30}}
    configured = mount(%{data.context | snapshots: [snapshot]})
    conn = signed(:platform, body("first-app"), data.platform_private, timestamp: @now - 31)
    assert Mount.call(conn, configured).status == 401
    refute_received {:event, _, _, _}
  end

  test "retained incoming and outgoing owners keep their exact verifier during a storage outage",
       data do
    {:ok, service} = ConfiguredService.from_snapshot(data.first, "https://original.example.test")
    leg = "retained-#{System.unique_integer([:positive])}"
    local = "outgoing-#{leg}"
    registry = Vxpipe.Gateway.Telephony.LegRegistry

    assert {:ok, _} =
             Registry.register(registry, {:scoped_telnyx, "first-app", leg}, {
               :incoming,
               service
             })

    assert {:ok, _} = Registry.register(registry, {:outgoing, local}, {:outgoing, service})
    unavailable = mount(Map.put(data.context, :unavailable, true))

    for {kind, state} <- [
          {:incoming, nil},
          {:outgoing, Vxpipe.Providers.Telnyx.ClientState.encode(local)}
        ] do
      incoming = body("first-app", leg, state)
      assert request(unavailable, :platform, incoming, data.platform_private).status == 200
      assert_receive {:event, ^service, _event, {^kind, owner}}
      assert owner == self()
      refute_received {:credential_lookup, _}
      refute_received {:application_lookup, _}
      assert request(unavailable, :platform, incoming, data.tenant_private).status == 401

      assert request(unavailable, {:tenant, @second}, incoming, data.tenant_private).status != 200
      refute_received {:event, _, _, _}
    end

    assert request(unavailable, :platform, body("first-app"), data.platform_private).status == 503
  end

  def resolve(%{unavailable: true}, _scope, "telnyx", "telnyx"),
    do: {:error, :provider_credentials_unavailable}

  def resolve(context, scope, "telnyx", "telnyx") do
    send(context.observer, {:credential_lookup, scope})
    scope = if is_binary(scope), do: {:tenant, scope}, else: scope

    selected = Map.get(context.credentials, scope, Map.get(context.credentials, :platform))

    case selected do
      nil -> {:error, :provider_credential_unavailable}
      credential -> {:ok, credential}
    end
  end

  def resolve(context, tenant, name) do
    case Enum.find(
           context.snapshots,
           &(&1.service.tenant_key == tenant and &1.service.name == name)
         ) do
      nil -> {:error, :provider_credential_unavailable}
      snapshot -> {:ok, snapshot}
    end
  end

  def fetch_telnyx_route(%{unavailable: true}, _scope, _application, _number),
    do: {:error, :telephony_services_unavailable}

  def fetch_telnyx_route(context, scope, application, number) do
    send(context.observer, {:application_lookup, application})

    matches =
      Enum.filter(context.snapshots, fn snapshot ->
        tenant = snapshot.service.tenant_key
        expected_number = Map.get(Map.get(context, :numbers, %{}), tenant, "+15550001000")

        snapshot.service.provider_connection_id == application and number == expected_number and
          (scope == :platform or scope == {:tenant, tenant})
      end)

    case matches do
      [snapshot] ->
        {:ok,
         %{
           snapshot.service
           | credential_owner: nil,
             credential_id: nil,
             application_owner: nil,
             public_key: nil,
             provider_connection_id:
               if(snapshot.service.application_owner == :platform, do: nil, else: application)
         }}

      _ ->
        {:error, :telephony_service_not_found}
    end
  end

  def handle_event(observer, service, event, owner) do
    send(observer, {:event, service, event, owner})
    :ok
  end

  def observe(_event, _measurements, metadata, observer) do
    if self() == observer, do: send(observer, {:operation, metadata.operation})
  end

  defp snapshot(tenant, owner, application, public) do
    original =
      Repository.snapshot(
        id: "phone",
        ingress_key: "ingress-#{tenant}",
        scope: {:tenant, tenant},
        provider: :telnyx,
        provider_connection_id: application,
        public_key: Base.encode64(public),
        api_key: "synthetic-private-key"
      )

    credential = %{
      original.credential.credential
      | owner: owner,
        tenant_key: if(owner == :platform, do: nil, else: tenant),
        name: "telnyx"
    }

    %{
      original
      | service: %{
          original.service
          | credential_owner: owner,
            credential_name: "telnyx",
            application_owner: {:tenant, tenant}
        },
        credential: %{
          original.credential
          | credential: credential,
            payload: Map.put(original.credential.payload, "public_key", Base.encode64(public))
        }
    }
  end

  defp mount(context, overrides \\ []),
    do:
      Mount.init(
        path_prefix: "/voice",
        cors: [allowed_origins: ["https://browser.example.test"]],
        telephony:
          Keyword.merge(
            [
              enabled: true,
              public_base_url: "https://voice.example.test/voice",
              provider_credential_repository: {__MODULE__, context},
              telephony_service_repository: {__MODULE__, context},
              handler: {__MODULE__, self()},
              clock: fn -> @now end
            ],
            overrides
          )
      )

  defp request(mount, scope, body, private), do: Mount.call(signed(scope, body, private), mount)

  defp signed(scope, body, private, options \\ []) do
    timestamp = Integer.to_string(Keyword.get(options, :timestamp, @now))

    signature =
      :crypto.sign(:eddsa, :none, timestamp <> "|" <> Keyword.get(options, :signed_body, body), [
        private,
        :ed25519
      ])

    path =
      case scope do
        :platform -> "/voice/webhooks/platform/telnyx"
        {:tenant, tenant} -> "/voice/webhooks/tenants/#{tenant}/telnyx"
      end

    conn(:post, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("origin", "https://browser.example.test")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", Base.encode64(signature))
  end

  defp body(application, leg \\ "fresh-leg", state \\ nil, number \\ "+15550001000"),
    do:
      JSON.encode!(%{
        data: %{
          id: "event-1",
          record_type: "event",
          event_type: "call.initiated",
          occurred_at: "2026-09-11T11:00:00Z",
          payload: %{
            connection_id: application,
            call_control_id: "control",
            call_leg_id: leg,
            call_session_id: "session",
            direction: "incoming",
            from: "+15550001001",
            to: number,
            client_state: state
          }
        }
      })
end
