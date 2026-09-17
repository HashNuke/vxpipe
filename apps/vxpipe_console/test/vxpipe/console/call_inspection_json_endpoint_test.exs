defmodule Vxpipe.Console.CallInspectionJSONEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Vxpipe.CallEngine.CallDefinition.ConnectionIntent
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDirectorySummary,
    CallDetailPage,
    CallHistory,
    CallSummary,
    PreparedCall,
    Tenant,
    UsageReport,
    VariableSnapshotHistory
  }

  alias Vxpipe.Console.TestCallInspectionBackend

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-call-details-secret-", 3)
  @token "operator-admin-call-details-token"
  @tenant_key "tenantkey1234567"
  @call_id "call-public-id"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_inspection_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
      Application.put_env(:vxpipe_console, :call_inspection_backend, original_backend)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()
    configure_admin_repository({:ok, {tenant(), call_directory_summary()}})

    :ok
  end

  test "requires the installation operator session" do
    assert json_response(https_get(route()), 401) == %{
             "error" => %{"code" => "operator_session_required"}
           }
  end

  test "returns the latest database inspection as private JSON" do
    configure_backend(successful_responses())

    conn =
      authenticate()
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> https_get(route())

    response = json_response(conn, 200)
    inspection = response["inspection"]

    assert response["tenant"] == %{"key" => @tenant_key, "name" => "Example tenant"}

    assert response["definition"] == %{
             "id" => "definition-public-id",
             "name" => "Delivery rescheduling"
           }

    assert response["definition_revision"] == 1
    assert inspection["schema_version"] == 1
    assert inspection["call"]["id"] == @call_id
    assert inspection["participants"] |> List.first() |> Map.fetch!("id") == "caller-runtime"
    refute Map.has_key?(inspection, "older_cursor")
    refute Map.has_key?(inspection, "as_of")

    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    refute conn.resp_body =~ "valid-api-key"

    assert_receive {:inspect_call, principal, @call_id, [limit: 1]}
    assert {:ok, @tenant_key} = Vxpipe.Calls.CallReadAccess.tenant_key(principal)
    assert_receive {:fetch_prepared_call, @tenant_key, @call_id, []}
    assert_receive {:fetch_call_history, _, @call_id, []}
    assert_receive {:usage_report, _, @call_id, []}
    refute_receive {:inspect_live_call, _, _, _}
  end

  test "returns authoritative lifecycle timing for an ended call" do
    ended_at = ~U[2026-09-16 09:01:31Z]
    call = %{call_summary() | state: :ended, ended_at: ended_at, terminal_reason: :completed}

    prepared = %{
      prepared_call()
      | state: :ended,
        ended_at: ended_at,
        terminal_reason: :completed
    }

    responses =
      successful_responses()
      |> Map.put(:inspect_call, {:ok, %{detail_page() | call: call}})
      |> Map.put(:fetch_prepared_call, {:ok, prepared})

    configure_backend(responses)

    response = authenticate() |> recycle() |> https_get(route()) |> json_response(200)
    response = response["inspection"]

    assert response["call"]["state"] == "ended"
    assert response["call"]["duration_ms"] == 90_000
    assert response["call"]["terminal_reason"] == "completed"
  end

  test "does not distinguish a missing or cross-tenant call" do
    configure_backend(%{inspect_call: {:error, :call_not_found}})

    conn = authenticate() |> recycle() |> https_get(route())

    assert %{"error" => %{"code" => "call_not_found"}} = json_response(conn, 404)
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    refute conn.resp_body =~ @tenant_key
  end

  test "does not inspect a call through another tenant namespace" do
    configure_admin_repository({:error, :call_not_found})
    configure_backend(%{inspect_call: {:error, :call_not_found}})

    conn =
      authenticate()
      |> recycle()
      |> https_get("/admin/api/tenants/other-tenant-key/calls/#{@call_id}")

    assert json_response(conn, 404) == %{"error" => %{"code" => "call_not_found"}}
  end

  test "does not distinguish a missing tenant from a missing call" do
    configure_admin_repository({:error, :tenant_not_found})

    conn = authenticate() |> recycle() |> https_get(route())

    assert json_response(conn, 404) == %{"error" => %{"code" => "call_not_found"}}
  end

  test "maps an invalid inspection request to bad request" do
    configure_backend(%{inspect_call: {:error, :invalid_call_inspection_request}})

    conn = authenticate() |> recycle() |> https_get(route())

    assert %{"error" => %{"code" => "invalid_call_inspection"}} =
             json_response(conn, 400)
  end

  test "maps unavailable database state without exposing the internal reason" do
    configure_backend(%{inspect_call: {:error, :repository_unavailable}})

    conn = authenticate() |> recycle() |> https_get(route())

    assert %{"error" => %{"code" => "call_inspection_unavailable"}} =
             json_response(conn, 503)

    refute conn.resp_body =~ "repository_unavailable"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  defp route, do: "/admin/api/tenants/#{@tenant_key}/calls/#{@call_id}"

  defp authenticate do
    form = https_get("/auth/login-token/#{@token}")

    form
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => csrf_token(form.resp_body),
      "operator" => %{"token" => @token, "code" => "01234567"}
    })
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp configure_login_repository do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :operator_login_challenge_repository, {
        Vxpipe.Console.Test.OperatorLoginChallengeRepository,
        {self(), :ok}
      })
    )
  end

  defp configure_backend(responses) do
    Application.put_env(
      :vxpipe_console,
      :call_inspection_backend,
      {TestCallInspectionBackend, {self(), responses}}
    )
  end

  defp configure_admin_repository(result) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(
        settings,
        :admin_repository,
        {Vxpipe.Console.Test.AdminRepository, {self(), result}}
      )
    )
  end

  defp tenant do
    %Tenant{key: @tenant_key, name: "Example tenant", inserted_at: ~U[2026-09-17 01:00:00Z]}
  end

  defp call_directory_summary do
    %CallDirectorySummary{
      id: @call_id,
      definition_id: "definition-public-id",
      definition_name: "Delivery rescheduling",
      definition_revision: 1,
      state: :running,
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: nil,
      terminal_reason: nil,
      archive_state: :unconfirmed
    }
  end

  defp successful_responses do
    %{
      inspect_call: {:ok, detail_page()},
      fetch_prepared_call: {:ok, prepared_call()},
      fetch_call_history:
        {:ok, CallHistory.new([], %VariableSnapshotHistory{snapshots: [], latest: nil})},
      usage_report: {:ok, %UsageReport{amounts: [], totals: []}}
    }
  end

  defp detail_page do
    %CallDetailPage{
      call: call_summary(),
      timeline: [],
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: 0
    }
  end

  defp call_summary do
    %CallSummary{
      id: @call_id,
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 1,
      state: :running,
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: nil,
      terminal_reason: nil,
      latest_variable_revision: 0
    }
  end

  defp prepared_call do
    %PreparedCall{
      id: @call_id,
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 1,
      schema_version: "20260915.01",
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "caller",
      initial_variables: %{},
      plan: resolved_plan(),
      plan_digest: <<0>>,
      state: :running,
      room_id: "room-public-id",
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: nil,
      incarnation_id: "incarnation-public-id",
      terminal_reason: nil
    }
  end

  defp resolved_plan do
    %ResolvedCallPlan{
      definition_id: "definition-public-id",
      definition_revision: 1,
      schema_version: "20260915.01",
      tenant_id: @tenant_key,
      actor_id: "actor-public-id",
      call_id: @call_id,
      room_id: "room-public-id",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "caller",
      opening_audio: nil,
      media_policy: nil,
      participants: %{"caller" => caller()},
      transfer_policy: nil,
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 120_000
    }
  end

  defp caller do
    %Participant{
      definition_key: "caller",
      participant_id: "caller-runtime",
      activation_id: nil,
      kind: :human,
      description: nil,
      connection: %ConnectionIntent{
        service: :web,
        mode: :receive,
        admission: :start_call,
        number: nil,
        number_from_variable: nil
      },
      transfer_notice: nil,
      prompt: nil,
      first_message: nil,
      first_message_text: nil,
      capabilities: %Capabilities{},
      while_present: nil,
      tools: %{},
      transfers: [],
      transfer_history: nil,
      variable_permissions: nil
    }
  end
end
