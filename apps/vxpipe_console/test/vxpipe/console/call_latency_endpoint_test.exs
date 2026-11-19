defmodule Vxpipe.Console.CallLatencyEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  alias Vxpipe.Calls.{TestLatencyReadRepository, TestLatencyRecords, TurnDiagnostic}
  alias Vxpipe.Console.Test.{FakeUserIdentity, NavigationIdentity}
  @endpoint Vxpipe.Console.Endpoint

  setup do
    keys = [
      {:vxpipe_calls, Vxpipe.Calls},
      {:vxpipe_console, :user_identity_backend},
      {:vxpipe_console, :navigation_test_principal}
    ]

    previous = Enum.map(keys, fn {app, key} -> {app, key, Application.get_env(app, key)} end)

    on_exit(fn ->
      Enum.each(previous, fn {app, key, value} ->
        if value == nil,
          do: Application.delete_env(app, key),
          else: Application.put_env(app, key, value)
      end)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, NavigationIdentity)
    Application.delete_env(:vxpipe_console, :navigation_test_principal)
    run = %{TestLatencyRecords.run() | tenant_key: "AAAAAAAAAAAAAAAA"}

    {:ok, turn} =
      TurnDiagnostic.new(%{
        run_id: run.id,
        turn_id: "turn-1",
        stt_allocation_id: "stt-1",
        clock_id: run.clock_id,
        source_epoch: run.source_epoch,
        revision: 3,
        landmarks_us: %{provider_end_received: 100_100, room_turn_completed: 120_200}
      })

    context = %{
      owner: self(),
      run: run,
      turns: [turn],
      error: nil,
      summary: [
        %{
          profile: run.profile,
          metric: "provider_to_room",
          valid_count: 120,
          excluded_count: 2,
          p50_us: 20_100.0,
          p95_us: 30_000.0
        }
      ]
    }

    configure(context)
    %{context: context}
  end

  test "both report routes require a browser session and reject bearer credentials" do
    for path <- [report_path(), turns_path()] do
      assert json_response(get(build_conn(), path), 401)["error"]["code"] == "session_required"

      response =
        login()
        |> recycle()
        |> Plug.Conn.put_req_header("authorization", "Bearer synthetic")
        |> get(path)

      assert json_response(response, 401)["error"]["code"] == "session_required"
    end

    refute_received {:list_runs, _, _, _, _}
    refute_received {:fetch_run, _, _, _}
  end

  test "returns private versioned reports with full-call aggregate counts" do
    response = login() |> recycle() |> get(report_path() <> "?limit=1&cursor=previous")
    body = json_response(response, 200)
    assert body["schema_version"] == 1
    assert body["call_id"] == "call-1"

    assert [
             %{
               "id" => "run-1",
               "profile" => %{"inference_source" => "benchmark_only"},
               "coverage" => %{"stored_turns" => 2}
             }
           ] = body["runs"]

    assert hd(body["summary"])["valid_count"] == 120
    assert hd(body["summary"])["p50_us"] == 20_100.0
    assert body["next_cursor"] == "run-next"
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["private, no-store"]
    refute response.resp_body =~ "__struct__"
    assert_received {:list_runs, "AAAAAAAAAAAAAAAA", "call-1", 1, "previous"}
  end

  test "turn JSON preserves revision, null stages, clock provenance and microsecond precision" do
    response = login() |> recycle() |> get(turns_path())
    body = json_response(response, 200)
    assert body["schema_version"] == 1
    assert body["call_id"] == "call-1"
    assert body["run_id"] == "run-1"

    assert [
             %{
               "turn_id" => "turn-1",
               "revision" => 3,
               "clock_id" => "clock-1",
               "durations_us" => %{
                 "provider_to_room" => 20_100,
                 "speech_end_to_provider_end" => nil
               }
             }
           ] = body["turns"]

    assert body["next_cursor"] == nil
    assert_received {:list_turns, "AAAAAAAAAAAAAAAA", "call-1", "run-1", 50, nil}
  end

  test "member without tenant call-read permission cannot reach the repository" do
    principal = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    Application.put_env(:vxpipe_console, :navigation_test_principal, {:ok, principal})

    for path <- [report_path(), turns_path()] do
      assert login() |> recycle() |> get(path) |> json_response(403) == %{
               "error" => %{"code" => "forbidden"}
             }
    end

    refute_received {:list_runs, _, _, _, _}
    refute_received {:fetch_run, _, _, _}
  end

  test "missing and cross-tenant calls and unknown runs use the same missing response" do
    for path <- [
          String.replace(report_path(), "AAAAAAAAAAAAAAAA", "BBBBBBBBBBBBBBBB"),
          String.replace(turns_path(), "run-1", "run-other")
        ] do
      assert login() |> recycle() |> get(path) |> json_response(404) == %{
               "error" => %{"code" => "call_diagnostics_not_found"}
             }
    end
  end

  test "malformed paging is rejected before repository access" do
    for query <- ["limit=101", "limit=-1", "limit=1junk", "limit[]=1", "cursor[]=x", "cursor="] do
      for path <- [report_path(), turns_path()] do
        assert login() |> recycle() |> get(path <> "?" <> query) |> json_response(400) == %{
                 "error" => %{"code" => "invalid_latency_request"}
               }
      end
    end

    refute_received {:list_runs, _, _, _, _}
    refute_received {:fetch_run, _, _, _}
  end

  test "storage outage is a retryable diagnostics error without internal details", c do
    configure(%{c.context | error: :repository_unavailable})
    response = login() |> recycle() |> get(report_path())

    assert json_response(response, 503) == %{
             "error" => %{"code" => "call_diagnostics_unavailable"}
           }

    refute response.resp_body =~ "repository"
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["private, no-store"]
  end

  test "the tenant host alias exposes the same session-only report contract" do
    path = String.replace(report_path(), "/api/tenants/", "/tenants/")

    assert login() |> recycle() |> get(path) |> json_response(200) |> Map.fetch!("schema_version") ==
             1
  end

  defp configure(context),
    do:
      Application.put_env(:vxpipe_calls, Vxpipe.Calls,
        latency_repository: {TestLatencyReadRepository, context}
      )

  defp report_path, do: "https://localhost/api/tenants/AAAAAAAAAAAAAAAA/calls/call-1/latency"
  defp turns_path, do: report_path() <> "/runs/run-1/turns"

  defp login,
    do:
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
end
