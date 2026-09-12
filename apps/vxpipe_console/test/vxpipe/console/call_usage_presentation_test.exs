defmodule Vxpipe.Console.CallUsagePresentationTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.CallEngine.Usage.{Attribution, EffectiveAmount, ProviderContext}

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallListPage,
    CallSummary,
    UsageReport
  }

  alias Vxpipe.Console.{TestCallInspectionBackend, TestOperatorAuthenticator}

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"

  setup do
    original_authenticator = Application.fetch_env!(:vxpipe_console, :operator_authenticator)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_inspection_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :operator_authenticator, original_authenticator)
      Application.put_env(:vxpipe_console, :call_inspection_backend, original_backend)
    end)

    Application.put_env(
      :vxpipe_console,
      :operator_authenticator,
      {TestOperatorAuthenticator, self()}
    )

    :ok
  end

  test "renders non-overlapping totals and disclosed effective-operation evidence" do
    configure_backend({:ok, usage_report()})

    html = sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)

    assert html =~ "Usage &amp; cost"
    assert html =~ "2 non-overlapping totals"
    assert html =~ "160 tokens"
    assert html =~ "0.0046 USD"
    assert html =~ "3 effective operations"
    assert html =~ "provider-fixture"
    assert html =~ "model-primary"
    assert html =~ "provider-request-model-1"
    assert html =~ "participant-agent"
    assert html =~ "turn-usage"
    assert html =~ "Provider reported"
    assert html =~ "Billing lookup"

    scroll_regions =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(".usage-table-scroll")

    assert LazyHTML.attribute(scroll_regions, "tabindex") == ["0", "0"]
    assert LazyHTML.attribute(scroll_regions, "role") == ["region", "region"]

    assert LazyHTML.attribute(scroll_regions, "aria-label") == [
             "Non-overlapping usage totals",
             "Effective usage operation evidence"
           ]

    assert_receive {:usage_report, principal, "call-public-id", []}
    assert principal.tenant_key == @tenant_key
  end

  test "distinguishes no projected usage from unavailable usage evidence" do
    configure_backend({:ok, %UsageReport{amounts: [], totals: []}})

    empty_html = sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)
    assert empty_html =~ "No usage observations projected"

    configure_backend({:error, :repository_unavailable})

    unavailable_html =
      sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)

    assert unavailable_html =~ "Usage evidence unavailable"
    refute unavailable_html =~ "repository_unavailable"
  end

  defp sign_in do
    post(build_conn(), "/operator/session", %{
      "operator" => %{
        "tenant_key" => @tenant_key,
        "api_key" => "valid-api-key"
      }
    })
  end

  defp configure_backend(usage_response) do
    call = call_summary()

    responses = %{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      usage_report: usage_response
    }

    Application.put_env(
      :vxpipe_console,
      :call_inspection_backend,
      {TestCallInspectionBackend, {self(), responses}}
    )
  end

  defp usage_report do
    provider = %ProviderContext{
      name: "provider-fixture",
      integration_id: "model-primary",
      model: "fixture-model",
      request_id: "provider-request-model-1"
    }

    attribution = %Attribution{
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      participant_id: "participant-agent",
      activation_id: "activation-agent",
      turn_id: "turn-usage"
    }

    amounts = [
      amount(provider, attribution, "input_tokens", :tokens, 100, included_in: "total_tokens"),
      amount(provider, attribution, "total_tokens", :tokens, 160),
      amount(
        %{provider | request_id: "provider-request-billing-1"},
        attribution,
        "cost",
        {:currency, "USD"},
        Decimal.new("0.0046"),
        attempt_id: "billing-attempt-1",
        provenance: :billing_lookup
      )
    ]

    {:ok, report} = UsageReport.new(amounts)
    report
  end

  defp amount(provider, attribution, component, unit, quantity, options \\ []) do
    %EffectiveAmount{
      attempt_id: Keyword.get(options, :attempt_id, "model-attempt-1"),
      capability: :model_inference,
      provider: provider,
      attribution: attribution,
      component: component,
      unit: unit,
      quantity: quantity,
      mode: :cumulative,
      status: :final,
      provenance: Keyword.get(options, :provenance, :provider_reported),
      included_in: Keyword.get(options, :included_in),
      observation_ids: ["usage-observation-#{component}"]
    }
  end

  defp call_summary do
    %CallSummary{
      id: "call-public-id",
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 3,
      state: :ended,
      created_at: ~U[2026-09-12 01:00:00Z],
      started_at: ~U[2026-09-12 01:00:01Z],
      ended_at: ~U[2026-09-12 01:01:00Z],
      terminal_reason: nil,
      latest_variable_revision: 2
    }
  end

  defp persisted_detail(call) do
    %CallDetailPage{
      call: call,
      timeline: [],
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: 2
    }
  end
end
