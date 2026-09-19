defmodule Vxpipe.Gateway.Telephony.TenantServiceReaderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.TelephonyServices
  alias Vxpipe.Gateway.Telephony.ServiceRegistry
  alias Vxpipe.Gateway.TestTelephonyServiceRepository, as: Repository

  @tenant "AAAAAAAAAAAAAAAA"
  @other_tenant "BBBBBBBBBBBBBBBB"
  @origin "https://voice.example.test/voice"

  test "the selected tenant's credentials reach the existing encoded REST request" do
    Req.Test.verify_on_exit!()

    for provider <- [:telnyx, :twilio],
        {tenant, secret} <- [
          {@tenant, "first-private-key"},
          {@other_tenant, "second-private-key"}
        ] do
      options = service(provider, tenant, "ingress-#{tenant}", secret)
      registry = ServiceRegistry.init!([enabled: true] ++ Repository.options([options]))

      assert {:ok, configured} =
               ServiceRegistry.fetch_for_tenant(
                 registry,
                 "primary-phone",
                 tenant,
                 Repository.reference(options)
               )

      expected_header =
        case provider do
          :telnyx ->
            "Bearer " <> secret

          :twilio ->
            "Basic " <> Base.encode64(configured.identity.provider_connection_id <> ":" <> secret)
        end

      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == [expected_header]
        assert conn.method == "POST"

        case provider do
          :telnyx ->
            assert conn.request_path == "/v2/calls"

            assert JSON.decode!(Req.Test.raw_body(conn))["connection_id"] ==
                     configured.identity.provider_connection_id

            Req.Test.json(conn, %{
              data: %{call_control_id: "control", call_leg_id: "leg", call_session_id: "session"}
            })

          :twilio ->
            assert conn.request_path ==
                     "/2010-04-01/Accounts/#{configured.identity.provider_connection_id}/Calls.json"

            conn
            |> Plug.Conn.put_status(201)
            |> Req.Test.json(%{sid: "CA00000000000000000000000000000001", status: "queued"})
        end
      end)

      request = %Vxpipe.CallEngine.Telephony.Dial{
        leg_id: "encoded-request",
        from: "+15550001000",
        to: "+15550001001",
        callback_url:
          Vxpipe.Gateway.Telephony.ProviderEndpoint.event_url(configured, "encoded-request"),
        media_url: Vxpipe.Gateway.Telephony.ProviderEndpoint.media_url(configured, "media-token"),
        answering_machine_detection: :disabled
      }

      transport_options =
        Keyword.put(configured.adapter_options, :request_options, plug: {Req.Test, __MODULE__})

      assert {:ok, %{status: :accepted}} =
               Vxpipe.CallEngine.Telephony.Adapter.dial(
                 configured.adapter,
                 transport_options,
                 request
               )
    end
  end

  test "accepts generated tenant keys beginning with URL-safe punctuation" do
    for tenant <- ["-AAAAAAAAAAAAAAA", "_BBBBBBBBBBBBBBB"] do
      options = service(:telnyx, tenant, "tenant-ingress", "private-key")
      registry = ServiceRegistry.init!([enabled: true] ++ Repository.options([options]))
      reference = Repository.reference(options)

      assert {:ok, _service} =
               ServiceRegistry.fetch_for_tenant(registry, "primary-phone", tenant, reference)
    end
  end

  test "resolves both existing carriers by exact tenant and prepared service identity" do
    for provider <- [:telnyx, :twilio] do
      own = service(provider, @tenant, "own-ingress", "own-private-key")
      other = service(provider, @other_tenant, "other-ingress", "other-private-key")
      registry = ServiceRegistry.init!([enabled: true] ++ Repository.options([own, other]))
      own_reference = Repository.reference(own)

      assert {:ok, configured} =
               ServiceRegistry.fetch_for_tenant(registry, "primary-phone", @tenant, own_reference)

      assert configured.identity.service_reference == own_reference
      assert configured.identity.scope == {:tenant, @tenant}
      assert configured.identity.provider == provider
      assert configured.public_base_url == @origin
      refute inspect(configured) =~ "own-private-key"

      assert {:error, :service_not_found} =
               ServiceRegistry.fetch_for_tenant(
                 registry,
                 "primary-phone",
                 @other_tenant,
                 own_reference
               )

      assert {:error, :service_not_found} =
               ServiceRegistry.fetch_for_tenant(registry, "primary-phone", @tenant, nil)

      changed_pin = %{own_reference | credential_id: Repository.reference(other).credential_id}

      assert {:error, :service_not_found} =
               ServiceRegistry.fetch_for_tenant(registry, "primary-phone", @tenant, changed_pin)

      assert {:ok, incoming} = ServiceRegistry.fetch(registry, "other-ingress")
      assert incoming.identity.service_reference == Repository.reference(other)
      key = if provider == :twilio, do: :auth_token, else: :api_key
      assert Keyword.fetch!(incoming.adapter_options, key) == "other-private-key"
    end
  end

  test "an ingress alias rebind between metadata and credential lookup cannot change ownership" do
    original = Repository.snapshot(service(:telnyx, @tenant, "own-ingress", "old-private-key"))

    replacement = %{
      original
      | service: %{original.service | id: "10000000-0000-4000-8000-000000000001"}
    }

    context = fn
      :fetch_by_ingress, ["own-ingress"] -> {:ok, original.service}
      :resolve, [@tenant, "primary-phone"] -> {:ok, replacement}
    end

    registry = registry(context)
    assert {:error, :service_not_found} = ServiceRegistry.fetch(registry, "own-ingress")
  end

  test "fresh reads reject inactive credentials and sanitize repository failure without fallback" do
    snapshot = Repository.snapshot(service(:twilio, @tenant, "own-ingress", "private-key"))
    reference = TelephonyServices.reference(snapshot.service)

    revoked = %{
      snapshot
      | credential: %{
          snapshot.credential
          | credential: %{snapshot.credential.credential | status: :revoked}
        }
    }

    for context <- [
          fn :resolve, _arguments -> {:ok, revoked} end,
          fn :resolve, _arguments -> {:error, :repository_unavailable} end,
          fn :resolve, _arguments -> raise "private repository detail" end,
          fn :resolve, _arguments -> exit(:private_repository_detail) end
        ] do
      assert {:error, :service_not_found} =
               ServiceRegistry.fetch_for_tenant(
                 registry(context),
                 "primary-phone",
                 @tenant,
                 reference
               )
    end
  end

  test "scoped application metadata resolves platform authentication and pins its credential owner" do
    original =
      Repository.snapshot(service(:telnyx, @tenant, "scoped-ingress", "platform-private-key"))

    snapshot = %{
      original
      | service: %{original.service | credential_name: "telnyx", credential_owner: :platform},
        credential: %{
          original.credential
          | credential: %{
              original.credential.credential
              | owner: :platform,
                tenant_key: nil,
                name: "telnyx"
            },
            payload:
              Map.put(original.credential.payload, "public_key", original.service.public_key)
        }
    }

    metadata = %{snapshot.service | credential_id: nil, credential_owner: nil, public_key: nil}

    context = fn
      :fetch_by_ingress, ["scoped-ingress"] -> {:ok, metadata}
      :resolve, [@tenant, "primary-phone"] -> {:ok, snapshot}
    end

    registry = registry(context)
    assert {:ok, incoming} = ServiceRegistry.fetch(registry, "scoped-ingress")
    reference = TelephonyServices.reference(snapshot.service)
    assert incoming.identity.service_reference == reference
    assert incoming.identity.scope == {:tenant, @tenant}
    assert Keyword.fetch!(incoming.adapter_options, :api_key) == "platform-private-key"

    assert {:ok, _} =
             ServiceRegistry.fetch_for_tenant(registry, "primary-phone", @tenant, reference)

    assert {:error, :service_not_found} =
             ServiceRegistry.fetch_for_tenant(registry, "primary-phone", @tenant, %{
               reference
               | credential_owner: {:tenant, @tenant}
             })

    refute inspect(incoming) =~ "platform-private-key"
  end

  defp registry(context) do
    ServiceRegistry.init!(
      enabled: true,
      public_base_url: @origin,
      telephony_service_repository: {Repository, context}
    )
  end

  defp service(provider, tenant, ingress, secret) do
    common = [
      id: "primary-phone",
      provider: provider,
      scope: {:tenant, tenant},
      ingress_key: ingress,
      public_base_url: @origin
    ]

    case provider do
      :telnyx ->
        common ++
          [
            api_key: secret,
            provider_connection_id: "connection-1",
            public_key: Base.encode64(:binary.copy(<<1>>, 32))
          ]

      :twilio ->
        common ++ [account_sid: "AC00000000000000000000000000000000", auth_token: secret]
    end
  end
end
