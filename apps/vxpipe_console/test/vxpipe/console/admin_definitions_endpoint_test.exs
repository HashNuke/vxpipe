defmodule Vxpipe.Console.AdminDefinitionsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.{DefinitionSummary, Tenant}

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-definitions-secret-", 3)
  @token "operator-admin-definitions-token"
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

  test "returns one tenant-scoped definition page to an installation operator" do
    tenant = %Tenant{
      key: @tenant_key,
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    definitions = [
      %DefinitionSummary{
        id: "delivery-rescheduling",
        name: "Delivery rescheduling",
        latest_revision: 4,
        published_revision: 3,
        call_count: 5,
        updated_at: ~U[2026-09-17 03:00:00Z]
      }
    ]

    configure_admin_repository({:ok, {tenant, definitions, 26}})

    conn =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/definitions?page=2")

    assert json_response(conn, 200) == %{
             "tenant" => %{"key" => @tenant_key, "name" => "Example tenant"},
             "definitions" => [
               %{
                 "id" => "delivery-rescheduling",
                 "name" => "Delivery rescheduling",
                 "latest_revision" => 4,
                 "published_revision" => 3,
                 "call_count" => 5,
                 "updated_at" => "2026-09-17T03:00:00Z"
               }
             ],
             "pagination" => %{
               "page" => 2,
               "page_size" => 25,
               "total" => 26,
               "total_pages" => 2
             }
           }

    assert_received {:operator_definitions_requested, @tenant_key, 25, 25}
  end

  test "distinguishes missing tenant, unavailable storage, invalid pages, and anonymous access" do
    configure_admin_repository({:error, :tenant_not_found})
    missing = authenticate() |> recycle() |> https_get("/admin/api/tenants/missing/definitions")
    assert json_response(missing, 404) == %{"error" => %{"code" => "tenant_not_found"}}
    assert_received {:operator_definitions_requested, "missing", 25, 0}

    configure_admin_repository({:error, :database_unavailable})

    unavailable =
      authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/definitions")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "definition_directory_unavailable"}
           }

    assert_received {:operator_definitions_requested, @tenant_key, 25, 0}

    configure_admin_repository(
      {:ok,
       {%Tenant{key: @tenant_key, name: "Example", inserted_at: ~U[2026-09-17 01:00:00Z]}, [], 0}}
    )

    invalid =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/definitions?page[]=1")

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_definitions_requested, _, _, _}

    anonymous = https_get("/admin/api/tenants/#{@tenant_key}/definitions")
    assert json_response(anonymous, 401) == %{"error" => %{"code" => "operator_session_required"}}
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
      Keyword.put(settings, :admin_repository, {
        Vxpipe.Console.Test.AdminRepository,
        {self(), result}
      })
    )
  end

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
