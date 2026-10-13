defmodule Vxpipe.Console.RequireUserTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Vxpipe.Console.RequireUser

  defmodule Backend do
    def authenticate(_token) do
      {:ok,
       %{
         user_public_id: "member",
         account_kind: :member,
         grants: MapSet.new(["calls.read", "call_specs.read"]),
         assigned_tenants: %{"north" => :read},
         all_tenant_actions: MapSet.new()
       }}
    end
  end

  defmodule ServiceManager do
    def authenticate(_token) do
      {:ok,
       %{
         user_public_id: "manager",
         account_kind: :member,
         grants: MapSet.new(["tenant_services.read"]),
         assigned_tenants: %{"north" => :read},
         all_tenant_actions: MapSet.new()
       }}
    end
  end

  @token String.duplicate("x", 43)

  test "HTML pages apply tenant permissions before sending the application" do
    allowed =
      conn(:get, "/admin/tenants/north/call-specs")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUser.call(backend: Backend)

    refute allowed.halted

    denied =
      conn(:get, "/admin/users")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUser.call(backend: Backend)

    assert denied.status == 403
    assert denied.halted
  end

  test "anonymous HTML requests redirect to email login" do
    result =
      conn(:get, "/admin")
      |> init_test_session(%{})
      |> RequireUser.call(backend: Backend)

    assert result.status == 302
    assert Plug.Conn.get_resp_header(result, "location") == ["/auth/login"]
    assert result.halted
  end

  test "tenant services page honors assigned tenant service reads" do
    allowed =
      conn(:get, "/admin/tenants/north/services")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUser.call(backend: ServiceManager)

    refute allowed.halted

    denied =
      conn(:get, "/admin/tenants/south/services")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUser.call(backend: ServiceManager)

    assert denied.status == 403
  end
end
