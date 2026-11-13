defmodule Vxpipe.Gateway.HTTP.TelnyxCallCostTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.Telephony.ServiceReference
  alias Vxpipe.CallEngine.Usage.{Attribution, Observation, ProviderContext}
  alias Vxpipe.Calls.{ProviderCredential, ResolvedProviderCredential}
  alias Vxpipe.Gateway.HTTP.Mount

  @tenant "COSTTESTTENANT01"
  @now 1_789_123_500

  setup do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)

    {:ok, provider} =
      ProviderContext.new(
        name: "telnyx",
        integration_id: "telnyx",
        operation_id: "leg",
        session_id: "session"
      )

    {:ok, observation} =
      Observation.new(
        id: "identified",
        tenant_id: @tenant,
        call_id: "call",
        attempt_id: "attempt",
        capability: :telephony,
        provider: provider,
        attribution: %Attribution{participant_id: "caller"},
        outcome: :in_progress,
        observed_at: DateTime.from_unix!(@now)
      )

    reference = %ServiceReference{
      tenant_id: @tenant,
      service_id: "service",
      name: "telnyx",
      provider: "telnyx",
      provider_connection_id: "application",
      credential_id: "credential",
      credential_owner: :platform,
      credential_name: "telnyx",
      application_owner: :platform
    }

    credential = %ResolvedProviderCredential{
      credential: %ProviderCredential{
        id: "credential",
        tenant_key: nil,
        owner: :platform,
        provider: "telnyx",
        name: "telnyx",
        auth_kind: "api_key"
      },
      payload: %{"public_key" => Base.encode64(public)}
    }

    context = %{observer: self(), target: {observation, reference}, credential: credential}

    mount =
      Mount.init(
        telephony: [
          enabled: true,
          public_base_url: "https://voice.example.test",
          usage_repository: {__MODULE__, context},
          provider_credential_repository: {__MODULE__, context},
          handler: {__MODULE__, self()},
          clock: fn -> @now end
        ]
      )

    [private: private, mount: mount]
  end

  test "v2 costs persist exact final amounts without a live call or current number route", data do
    assert request(data, body()).status == 200
    assert_receive {:stored, %{measurement: %{component: "cost"} = total} = observation}
    assert total.quantity == Decimal.new("0.0106")
    assert total.unit == {:currency, "USD"}
    assert total.status == :final
    assert total.provenance == :provider_reported
    assert total.mode == :cumulative
    assert observation.tenant_id == @tenant
    assert observation.provider.operation_id == "leg"
    assert observation.outcome == :unknown
    assert_receive {:stored, %{measurement: %{component: "billed_duration", quantity: 120_000}}}

    assert_receive {:stored,
                    %{measurement: %{component: "cost_sip_trunking", included_in: "cost"}}}

    refute_received {:lifecycle, _}
  end

  test "signature, scope and original application are required before storing costs", data do
    {_, wrong_private} = :crypto.generate_key(:eddsa, :ed25519)
    assert request(%{data | private: wrong_private}, body()).status == 401
    assert request(data, body(), {:tenant, "OTHERTENANT00001"}).status == 403
    assert request(data, body(%{"connection_id" => "other-app"})).status == 403
    refute_received {:stored, _}
  end

  test "missing durable usage returns retryable failure, not a dropped event", data do
    assert request(data, body(%{"call_leg_id" => "not-archived"})).status == 503
    refute_received {:stored, _}
  end

  test "carrier cost errors preserve unknown cost instead of inventing zero", data do
    assert request(
             data,
             body(%{
               "status" => "error",
               "total_cost" => nil,
               "billed_duration_secs" => nil,
               "cost_parts" => []
             })
           ).status == 200

    assert_receive {:stored, %{measurement: nil, outcome: :unknown}}
    refute_received {:stored, _}
  end

  test "malformed and ambiguous monetary payloads cannot write usage", data do
    for patch <- [
          %{"total_cost" => 0.0106},
          %{"billed_duration_secs" => -1},
          %{"cost_parts" => []},
          %{"status" => "unexpected"}
        ] do
      assert request(data, body(patch)).status == 400
    end

    refute_received {:stored, _}
  end

  test "retries retain observation identity and changed deliveries alter the receipt fingerprint",
       data do
    assert request(data, body(), {:tenant, @tenant}).status == 200
    assert_receive {:stored, %{measurement: nil} = first}
    assert request(data, body()).status == 200
    assert_receive {:stored, %{measurement: nil} = retry}
    assert first == retry
    assert request(data, body(%{"total_cost" => "0.02"})).status == 200
    assert_receive {:stored, %{measurement: nil} = changed}
    assert changed.id == first.id
    refute changed.delivery_id == first.delivery_id
  end

  def fetch_telephony_billing_target(context, "telnyx", "leg", "session"),
    do: {:ok, context.target}

  def fetch_telephony_billing_target(_context, _provider, _leg, _session),
    do: {:error, :usage_target_not_found}

  def resolve(context, :platform, "telnyx", "telnyx"), do: {:ok, context.credential}

  def store_usage_observation(context, observation) do
    send(context.observer, {:stored, observation})
    {:ok, observation}
  end

  def handle_event(observer, _service, event, _owner), do: send(observer, {:lifecycle, event})

  defp request(data, body, scope \\ :platform) do
    timestamp = Integer.to_string(@now)
    signature = :crypto.sign(:eddsa, :none, timestamp <> "|" <> body, [data.private, :ed25519])

    path =
      case scope do
        :platform -> "/webhooks/platform/telnyx"
        {:tenant, tenant} -> "/webhooks/tenants/#{tenant}/telnyx"
      end

    conn(:post, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", Base.encode64(signature))
    |> Mount.call(data.mount)
  end

  defp body(patch \\ %{}) do
    payload =
      Map.merge(
        %{
          "connection_id" => "application",
          "call_control_id" => "control",
          "call_leg_id" => "leg",
          "call_session_id" => "session",
          "status" => "success",
          "total_cost" => "0.0106",
          "billed_duration_secs" => 120,
          "cost_parts" => [
            %{
              "call_part" => "sip-trunking",
              "currency" => "USD",
              "cost" => "0.0106",
              "rate" => "0.0053",
              "billed_duration_secs" => 120
            }
          ]
        },
        patch
      )

    JSON.encode!(%{
      data: %{
        id: "cost-event",
        record_type: "event",
        event_type: "call.cost",
        occurred_at: "2026-09-11T11:00:00Z",
        payload: payload
      }
    })
  end
end
