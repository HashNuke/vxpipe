defmodule Vxpipe.Console.RequireUserAPITest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Vxpipe.Console.RequireUserAPI

  defmodule Backend do
    def authenticate("ungranted" <> _) do
      {:ok,
       %{
         user_public_id: "ungranted",
         account_kind: :member,
         grants: MapSet.new(),
         assigned_tenants: %{"north" => :read},
         all_tenant_actions: MapSet.new(["calls.read"])
       }}
    end

    def authenticate("keys" <> _) do
      {:ok,
       %{
         user_public_id: "keys",
         account_kind: :member,
         grants: MapSet.new(["tenant_api_keys.read"]),
         assigned_tenants: %{"north" => :read},
         all_tenant_actions: MapSet.new()
       }}
    end

    def authenticate(_token) do
      {:ok,
       %{
         user_public_id: "reader",
         account_kind: :member,
         grants: MapSet.new(["calls.read"]),
         assigned_tenants: %{"north" => :read},
         all_tenant_actions: MapSet.new()
       }}
    end
  end

  @token String.duplicate("x", 43)

  test "a tenant reader can inspect assigned calls but cannot read platform services" do
    allowed =
      conn(:get, "/admin/api/tenants/north/calls")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUserAPI.call(backend: Backend)

    assert allowed.assigns.user_principal.user_public_id == "reader"
    refute allowed.halted

    denied =
      conn(:get, "/admin/api/platform/services")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUserAPI.call(backend: Backend)

    assert denied.status == 403
    assert denied.halted
  end

  test "tenant assignments and stale scope without grants do not authorize the directory" do
    denied =
      conn(:get, "/admin/api/tenants")
      |> init_test_session(%{"vxpipe_user_session" => "ungranted" <> String.duplicate("x", 34)})
      |> RequireUserAPI.call(backend: Backend)

    assert denied.status == 403
    assert denied.halted
  end

  test "credential-only readers can open services, but not bindings or foreign tenants" do
    for {path, allowed?} <- [
          {"/admin/api/tenants/north/services", true},
          {"/admin/api/tenants/north/service-bindings", false},
          {"/admin/api/tenants/south/services", false}
        ] do
      result =
        conn(:get, path)
        |> init_test_session(%{"vxpipe_user_session" => "keys" <> String.duplicate("x", 39)})
        |> RequireUserAPI.call(backend: Backend)

      assert result.halted == not allowed?
    end
  end

  test "an unknown action and missing session fail closed" do
    unknown =
      conn(:get, "/admin/api/internal/unknown")
      |> init_test_session(%{"vxpipe_user_session" => @token})
      |> RequireUserAPI.call(backend: Backend)

    assert unknown.status == 403
    assert unknown.halted

    anonymous =
      conn(:get, "/admin/api/tenants/north/calls")
      |> init_test_session(%{})
      |> RequireUserAPI.call(backend: Backend)

    assert anonymous.status == 401
    assert anonymous.halted
  end
end
