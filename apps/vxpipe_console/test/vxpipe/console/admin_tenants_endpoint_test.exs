defmodule Vxpipe.Console.AdminTenantsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.Tenant

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-tenants-secret-", 3)
  @token "operator-admin-tenants-token"

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

  test "returns one bounded tenant page to an installation operator" do
    tenants = [
      %Tenant{key: "BBBBBBBBBBBBBBBB", name: "Second", inserted_at: ~U[2026-09-17 02:00:00Z]},
      %Tenant{key: "AAAAAAAAAAAAAAAA", name: "First", inserted_at: ~U[2026-09-17 01:00:00Z]}
    ]

    configure_admin_repository({:ok, {tenants, 57}})

    conn =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants?page=2")

    assert json_response(conn, 200) == %{
             "tenants" => [
               %{
                 "key" => "BBBBBBBBBBBBBBBB",
                 "name" => "Second",
                 "created_at" => "2026-09-17T02:00:00Z"
               },
               %{
                 "key" => "AAAAAAAAAAAAAAAA",
                 "name" => "First",
                 "created_at" => "2026-09-17T01:00:00Z"
               }
             ],
             "pagination" => %{
               "page" => 2,
               "page_size" => 25,
               "total" => 57,
               "total_pages" => 3
             }
           }

    assert_received {:operator_tenants_requested, 25, 25}
  end

  test "keeps an empty result distinct from persistence failure" do
    configure_admin_repository({:ok, {[], 0}})

    empty = authenticate() |> recycle() |> https_get("/admin/api/tenants")
    assert %{"tenants" => [], "pagination" => %{"total" => 0}} = json_response(empty, 200)

    configure_admin_repository({:error, :database_unavailable})

    unavailable = authenticate() |> recycle() |> https_get("/admin/api/tenants")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "tenant_directory_unavailable"}
           }
  end

  test "rejects invalid pages and anonymous requests" do
    configure_admin_repository({:ok, {[], 0}})

    invalid =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants?page=zero")

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_tenants_requested, _, _}

    structured = authenticate() |> recycle() |> get("/admin/api/tenants?page[]=1")

    assert json_response(structured, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_tenants_requested, _, _}

    anonymous = https_get("/admin/api/tenants")

    assert json_response(anonymous, 401) == %{
             "error" => %{"code" => "operator_session_required"}
           }

    refute_received {:operator_tenants_requested, _, _}
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
