defmodule Vxpipe.Console.RoutePermissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.RoutePermission

  test "maps tenant reads and writes to separate registered actions" do
    assert RoutePermission.for_request("GET", ["admin", "api", "tenants", "tenant-a", "calls"]) ==
             {:tenant, "calls.read", "tenant-a"}

    assert RoutePermission.for_request("POST", [
             "admin",
             "api",
             "tenants",
             "tenant-a",
             "call-specs"
           ]) ==
             {:tenant, "call_specs.write", "tenant-a"}

    assert RoutePermission.for_request("POST", [
             "admin",
             "api",
             "tenants",
             "tenant-a",
             "credentials"
           ]) ==
             {:tenant, "tenant_api_keys.write", "tenant-a"}
  end

  test "keeps platform writes separate from tenant writes" do
    assert RoutePermission.for_request("POST", ["admin", "api", "platform", "credentials"]) ==
             {:installation, "platform_services.write"}

    assert RoutePermission.for_request("GET", ["admin", "api", "platform", "services"]) ==
             {:installation, "platform_services.read"}
  end

  test "tenant credential inventory uses its own read permission" do
    assert RoutePermission.for_request("GET", [
             "admin",
             "api",
             "tenants",
             "tenant-a",
             "credentials"
           ]) ==
             {:tenant, "tenant_services.read", "tenant-a"}
  end

  test "call spec editor lookups require spec read access, not service administration" do
    for resource <- [
          ["providers"],
          ["providers", "openai", "models"]
        ] do
      assert RoutePermission.for_request(
               "GET",
               ["admin", "api", "tenants", "tenant-a" | resource]
             ) == {:tenant, "call_specs.read", "tenant-a"}
    end

    assert RoutePermission.for_request(
             "GET",
             [
               "admin",
               "api",
               "tenants",
               "tenant-a",
               "telephony-services",
               "service-id",
               "numbers"
             ]
           ) == {:tenant, "call_specs.write", "tenant-a"}
  end

  test "does not grant unknown or sample routes by a prefix" do
    assert RoutePermission.for_request("POST", ["admin", "api", "users", "guess"]) == :unknown

    assert RoutePermission.for_request("POST", ["admin", "samples", "calls"]) ==
             {:installation, "tenants.write"}

    assert RoutePermission.for_request("POST", ["admin", "samples", "calls", "guess"]) ==
             :unknown
  end

  test "account mutations reach target-aware policy after authentication" do
    assert RoutePermission.for_request("POST", ["admin", "api", "users"]) == :authenticated

    assert RoutePermission.for_request("PATCH", ["admin", "api", "users", "user-id"]) ==
             :authenticated

    assert RoutePermission.for_request("POST", [
             "admin",
             "api",
             "users",
             "user-id",
             "reset-password"
           ]) == :authenticated

    assert RoutePermission.for_request("GET", ["admin", "api", "users"]) ==
             {:installation, "users.read"}
  end
end
