defmodule Vxpipe.Console.AdminCallsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.{CallDirectorySummary, CallSpecFilter, Tenant}

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-calls-secret-", 3)
  @token "operator-admin-calls-token"
  @tenant_key "AAAAAAAAAAAAAAAA"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()
    :ok
  end

  test "returns one filtered tenant call page to an installation operator" do
    tenant = %Tenant{
      key: @tenant_key,
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    call_specs = [
      %CallSpecFilter{id: "delivery-rescheduling", name: "Delivery rescheduling"}
    ]

    calls = [
      %CallDirectorySummary{
        id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
        call_spec_id: "delivery-rescheduling",
        call_spec_name: "Delivery rescheduling",
        call_spec_revision: 3,
        state: :running,
        created_at: ~U[2026-09-17 02:20:00Z],
        started_at: ~U[2026-09-17 02:20:03Z],
        ended_at: nil,
        terminal_reason: nil,
        archive_state: :unconfirmed
      },
      %CallDirectorySummary{
        id: "018f27a2-51d5-77c9-a44f-e5c648bf8495",
        call_spec_id: "delivery-rescheduling",
        call_spec_name: "Delivery rescheduling",
        call_spec_revision: 2,
        state: :failed,
        created_at: ~U[2026-09-17 02:10:00Z],
        started_at: ~U[2026-09-17 02:10:03Z],
        ended_at: ~U[2026-09-17 02:10:04Z],
        terminal_reason: :session_start_failed,
        archive_state: :incomplete
      }
    ]

    configure_admin_repository({:ok, {tenant, call_specs, false, calls, 26}})

    conn =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/calls?page=2&call_spec_id=delivery-rescheduling")

    assert json_response(conn, 200) == %{
             "tenant" => %{"key" => @tenant_key, "name" => "Example tenant"},
             "call_specs" => [
               %{"id" => "delivery-rescheduling", "name" => "Delivery rescheduling"}
             ],
             "call_specs_truncated" => false,
             "selected_call_spec_id" => "delivery-rescheduling",
             "calls" => [
               %{
                 "id" => "018f27cb-6f87-7d1c-a61f-8873cb667342",
                 "call_spec_id" => "delivery-rescheduling",
                 "call_spec_name" => "Delivery rescheduling",
                 "call_spec_revision" => 3,
                 "state" => "ongoing",
                 "created_at" => "2026-09-17T02:20:00Z"
               },
               %{
                 "id" => "018f27a2-51d5-77c9-a44f-e5c648bf8495",
                 "call_spec_id" => "delivery-rescheduling",
                 "call_spec_name" => "Delivery rescheduling",
                 "call_spec_revision" => 2,
                 "state" => "ended",
                 "created_at" => "2026-09-17T02:10:00Z"
               }
             ],
             "pagination" => %{
               "page" => 2,
               "page_size" => 25,
               "total" => 26,
               "total_pages" => 2
             }
           }

    assert_received {:operator_calls_requested, @tenant_key, "delivery-rescheduling", 25, 25}
  end

  test "keeps missing resources, unavailable storage, invalid input, and anonymous access distinct" do
    for reason <- [:tenant_not_found, :call_spec_not_found] do
      configure_admin_repository({:error, reason})

      missing =
        authenticate()
        |> recycle()
        |> https_get("/admin/api/tenants/#{@tenant_key}/calls?call_spec_id=missing")

      assert json_response(missing, 404) == %{
               "error" => %{"code" => "call_directory_not_found"}
             }
    end

    configure_admin_repository({:error, :database_unavailable})

    unavailable =
      authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/calls")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "call_directory_unavailable"}
           }

    invalid =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/calls?call_spec_id[]=invalid")

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_filter"}}

    anonymous = https_get("/admin/api/tenants/#{@tenant_key}/calls")

    assert json_response(anonymous, 401) == %{
             "error" => %{"code" => "operator_session_required"}
           }
  end

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
end
