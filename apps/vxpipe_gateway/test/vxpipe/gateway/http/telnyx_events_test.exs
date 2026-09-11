defmodule Vxpipe.Gateway.HTTP.TelnyxEventsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.{Endpoint, TelephonyIngressConfig}
  alias Vxpipe.Gateway.Telephony.{CallIngress, IngressIdentity, ServiceRegistry}
  alias Vxpipe.Gateway.TestTelephonyIngress

  @ingress_key "ingress_telnyx_primary"
  @received_at 1_789_123_500

  setup do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    endpoint =
      Endpoint.init(
        telephony: [
          enabled: true,
          clock: fn -> @received_at end,
          handler: {TestTelephonyIngress, self()},
          services: [
            [
              id: "telnyx-primary",
              ingress_key: @ingress_key,
              provider: :telnyx,
              provider_connection_id: "voice-application-1",
              public_key: Base.encode64(public_key),
              api_key: "test-api-key",
              public_base_url: "https://voice.example.test",
              scope: {:tenant, "tenantkey1234567"}
            ]
          ]
        ]
      )

    %{endpoint: endpoint, private_key: private_key}
  end

  test "authenticates the exact body and dispatches only a normalized event", context do
    body = incoming_body("voice-application-1", pretty: true)

    conn = request(context.endpoint, body, context.private_key)

    assert conn.status == 200
    assert conn.resp_body == "ok"

    assert_receive {:telephony_event,
                    %IngressIdentity{
                      service_id: "telnyx-primary",
                      ingress_key: @ingress_key,
                      provider: :telnyx,
                      provider_connection_id: "voice-application-1",
                      scope: {:tenant, "tenantkey1234567"}
                    },
                    %Event{
                      kind: :incoming,
                      provider: :telnyx,
                      provider_event_id: "event-incoming-1",
                      provider_connection_id: "voice-application-1",
                      to: "+15550001000"
                    }}
  end

  test "rejects tampering before dispatch", context do
    body = incoming_body("voice-application-1")
    tampered_conn = signed_conn(body <> " ", context.private_key, body)

    conn = Endpoint.call(tampered_conn, context.endpoint)

    assert conn.status == 401
    assert conn.resp_body == "invalid webhook authentication"
    refute_receive {:telephony_event, _identity, _event}
  end

  test "verifies a signed malformed body before returning a decoder error", context do
    conn = request(context.endpoint, "not-json", context.private_key)

    assert conn.status == 400
    assert conn.resp_body == "invalid webhook"
    refute_receive {:telephony_event, _identity, _event}
  end

  test "rejects an event from another provider connection", context do
    body = incoming_body("voice-application-other")

    conn = request(context.endpoint, body, context.private_key)

    assert conn.status == 403
    assert conn.resp_body == "webhook source mismatch"
    refute_receive {:telephony_event, _identity, _event}
  end

  test "acknowledges authenticated events that the platform ignores", context do
    body = event_body("call.playback.ended", "voice-application-1")

    conn = request(context.endpoint, body, context.private_key)

    assert conn.status == 200
    assert conn.resp_body == "ok"
    refute_receive {:telephony_event, _identity, _event}
  end

  test "does not expose an unknown configured-service route", context do
    body = incoming_body("voice-application-1")

    conn =
      :post
      |> conn("/api/telephony/telnyx/not_configured/events", body)
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(context.endpoint)

    assert conn.status == 404
    assert conn.resp_body == "not found"
  end

  test "rejects a webhook body beyond the bounded ingress size", context do
    oversized = :binary.copy("x", 131_073)

    conn = request(context.endpoint, oversized, context.private_key)

    assert conn.status == 413
    assert conn.resp_body == "payload too large"
    refute_receive {:telephony_event, _identity, _event}
  end

  test "pins the default call ingress to the configured service and media admission" do
    {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)
    media_admission = self()

    options =
      TelephonyIngressConfig.init(
        enabled: true,
        media_admission: media_admission,
        services: [
          [
            id: "telnyx-primary",
            ingress_key: @ingress_key,
            provider: :telnyx,
            provider_connection_id: "voice-application-1",
            public_key: Base.encode64(public_key),
            api_key: "test-api-key",
            public_base_url: "https://voice.example.test",
            scope: {:tenant, "tenantkey1234567"}
          ]
        ]
      )

    assert {CallIngress, ingress_options} = options.handler
    assert {CallAdmission, backend_options} = Keyword.fetch!(ingress_options, :backend)
    assert ^media_admission = Keyword.fetch!(backend_options, :media_admission)
    assert %ServiceRegistry{enabled?: true} = Keyword.fetch!(backend_options, :service_registry)
  end

  defp request(endpoint, body, private_key) do
    body
    |> signed_conn(private_key)
    |> Endpoint.call(endpoint)
  end

  defp signed_conn(body, private_key, signed_body \\ nil) do
    timestamp = Integer.to_string(@received_at)
    signed_body = signed_body || body

    signature =
      :crypto.sign(:eddsa, :none, timestamp <> "|" <> signed_body, [private_key, :ed25519])

    :post
    |> conn("/api/telephony/telnyx/#{@ingress_key}/events", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", Base.encode64(signature))
  end

  defp incoming_body(provider_connection_id, options \\ []) do
    event_body(
      "call.initiated",
      provider_connection_id,
      %{"direction" => "incoming"},
      options
    )
  end

  defp event_body(event_type, provider_connection_id, overrides \\ %{}, options \\ []) do
    payload =
      Map.merge(
        %{
          "call_control_id" => "call-control-1",
          "call_leg_id" => "call-leg-1",
          "call_session_id" => "call-session-1",
          "connection_id" => provider_connection_id,
          "from" => "+15550001001",
          "to" => "+15550001000"
        },
        overrides
      )

    envelope = %{
      "data" => %{
        "record_type" => "event",
        "event_type" => event_type,
        "id" => "event-incoming-1",
        "occurred_at" => "2026-09-11T09:45:12.123456Z",
        "payload" => payload
      }
    }

    if Keyword.get(options, :pretty, false) do
      ~s({\n  "data": #{JSON.encode!(envelope["data"])}\n})
    else
      JSON.encode!(envelope)
    end
  end
end
