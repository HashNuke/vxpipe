defmodule Vxpipe.Gateway.Telephony.WebhookServiceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, ServiceRegistry, WebhookService}
  alias Vxpipe.Gateway.TestTelephonyServiceRepository, as: Repository

  test "selects each provider's exact retained owner before consulting unavailable storage" do
    for provider <- [:telnyx, :twilio] do
      ingress = "owner-#{System.unique_integer([:positive])}"
      local_id = "local-#{ingress}"
      service = service(provider, ingress)
      registry = unavailable_registry()

      assert {:ok, _} =
               Registry.register(
                 Vxpipe.Gateway.Telephony.LegRegistry,
                 {:outgoing, local_id},
                 {:outgoing, service}
               )

      payload = body(provider, service, local_id)

      selected =
        case provider do
          :telnyx -> WebhookService.scoped_telnyx_owner({:tenant, "AAAAAAAAAAAAAAAA"}, payload)
          :twilio -> WebhookService.select_twilio(registry, ingress, payload, local_id)
        end

      assert {:ok, ^service, {:outgoing, owner}} = selected
      assert owner == self()
      refute_receive :credential_lookup

      rejected =
        case provider do
          :telnyx -> WebhookService.scoped_telnyx_owner(:platform, payload)
          :twilio -> WebhookService.select_twilio(registry, "other-ingress", payload, local_id)
        end

      assert {:error, :service_not_found} = rejected
      refute_receive :credential_lookup
    end
  end

  test "incoming lookup keeps provider account and ingress within the owner's identity" do
    ingress = "incoming-#{System.unique_integer([:positive])}"
    service = service(:twilio, ingress)
    sid = service.identity.provider_connection_id
    call_sid = "CA00000000000000000000000000000001"

    assert {:ok, _} =
             Registry.register(
               Vxpipe.Gateway.Telephony.LegRegistry,
               {:ingress, :twilio, ingress, sid, call_sid},
               {:incoming, service}
             )

    assert {:ok, ^service, {:incoming, owner}} =
             WebhookService.select_twilio(
               unavailable_registry(),
               ingress,
               body(:twilio, service, nil)
             )

    assert owner == self()
    refute_receive :credential_lookup

    assert {:error, :service_not_found} =
             WebhookService.select_twilio(
               unavailable_registry(),
               ingress,
               "CallSid=#{call_sid}&AccountSid=wrong"
             )

    assert_receive :credential_lookup
  end

  defp unavailable_registry do
    observer = self()

    ServiceRegistry.init!(
      enabled: true,
      public_base_url: "https://changed.example.test",
      telephony_service_repository:
        {Repository,
         fn _operation, _arguments ->
           send(observer, :credential_lookup)
           {:error, :repository_unavailable}
         end}
    )
  end

  defp service(provider, ingress) do
    options = [
      id: "primary-phone",
      provider: provider,
      ingress_key: ingress,
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      public_base_url: "https://voice.example.test",
      provider_connection_id: "connection-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "private-key"
    ]

    options =
      if provider == :twilio do
        options
        |> Keyword.drop([:provider_connection_id, :public_key, :api_key])
        |> Keyword.merge(
          account_sid: "AC00000000000000000000000000000000",
          auth_token: "private-token"
        )
      else
        options
      end

    {:ok, service} =
      ConfiguredService.from_snapshot(Repository.snapshot(options), "https://voice.example.test")

    service
  end

  defp body(:twilio, service, _local_id) do
    URI.encode_query(%{
      "AccountSid" => service.identity.provider_connection_id,
      "CallSid" => "CA00000000000000000000000000000001"
    })
  end

  defp body(:telnyx, service, local_id) do
    JSON.encode!(%{
      "data" => %{
        "payload" => %{
          "connection_id" => service.identity.provider_connection_id,
          "call_leg_id" => "provider-leg",
          "client_state" => Vxpipe.Gateway.Telephony.Telnyx.ClientState.encode(local_id)
        }
      }
    })
  end
end
