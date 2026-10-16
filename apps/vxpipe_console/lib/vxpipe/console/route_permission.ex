defmodule Vxpipe.Console.RoutePermission do
  @moduledoc "Maps Console HTTP routes to exact registered user actions."

  @type requirement ::
          :authenticated
          | :superadmin
          | {:installation, String.t()}
          | {:tenant, String.t(), String.t()}
          | {:directory, String.t()}
          | :unknown

  @spec for_request(String.t(), [String.t()]) :: requirement()
  def for_request("GET", ["api", "account", "connections"]), do: :authenticated
  def for_request("DELETE", ["api", "account", "connections", _id]), do: :authenticated

  def for_request("GET", ["api", "tenants", tenant, "calls" | _rest]),
    do: {:tenant, "calls.read", tenant}

  def for_request("POST", ["api", "tenants"]),
    do: for_request("POST", ["admin", "api", "tenants"])

  def for_request(method, ["api", "api-keys" | rest]),
    do: for_request(method, ["admin", "api", "api-keys" | rest])

  def for_request(method, ["api", "platform", resource | rest])
      when resource in ["services", "credentials"],
      do: for_request(method, ["admin", "api", "platform", resource | rest])

  def for_request(method, ["api", "tenants", tenant, resource | rest])
      when resource in [
             "services",
             "service-bindings",
             "credentials",
             "telephony-applications",
             "telephony-services"
           ],
      do: for_request(method, ["admin", "api", "tenants", tenant, resource | rest])

  def for_request(method, ["api", "roles" | rest]),
    do: for_request(method, ["admin", "api", "roles" | rest])

  def for_request("POST", ["api", "users", id, "reset-password"]),
    do: for_request("POST", ["admin", "api", "users", id, "reset-password"])

  def for_request(method, ["admin", "api", "api-keys" | _rest])
      when method in ["GET", "POST", "DELETE"], do: :authenticated

  def for_request("GET", ["admin", "api", "session"]), do: :authenticated
  def for_request("GET", ["admin", "api", "navigation"]), do: :authenticated

  def for_request("GET", ["admin", "api", "role-options"]),
    do: {:installation, "users.read"}

  def for_request("GET", ["admin", "api", "users"]), do: {:installation, "users.read"}

  def for_request("GET", ["admin", "api", "users", _id]),
    do: {:installation, "users.read"}

  def for_request("POST", ["admin", "api", "users"]), do: :authenticated

  def for_request("PATCH", ["admin", "api", "users", _id]),
    do: :authenticated

  def for_request("POST", ["admin", "api", "users", _id, "reset-password"]),
    do: :authenticated

  def for_request("PATCH", ["admin", "api", "account"]), do: :authenticated
  def for_request("GET", ["admin", "api", "roles"]), do: :authenticated
  def for_request("GET", ["admin", "api", "roles", _id]), do: :authenticated
  def for_request("POST", ["admin", "api", "roles"]), do: :authenticated
  def for_request("PATCH", ["admin", "api", "roles", _id]), do: :authenticated
  def for_request("DELETE", ["admin", "api", "roles", _id]), do: :authenticated
  def for_request("POST", ["admin", "api", "tenants"]), do: {:installation, "tenants.write"}
  def for_request("GET", ["admin", "api", "tenants"]), do: {:directory, "tenants.read"}

  def for_request("POST", ["api", "onboarding", "demo-tenant"]),
    do: {:installation, "tenants.write"}

  def for_request("POST", ["admin", "api", "onboarding", "demo-tenant"]),
    do: {:installation, "tenants.write"}

  def for_request("POST", ["api", "onboarding", "demo-tenant", "samples"]),
    do: {:installation, "tenants.write"}

  def for_request("POST", ["admin", "api", "onboarding", "demo-tenant", "samples"]),
    do: {:installation, "tenants.write"}

  def for_request("GET", ["admin", "api", "platform", "services"]),
    do: {:installation, "platform_services.read"}

  def for_request("POST", ["admin", "api", "platform", "credentials", "test"]),
    do: {:installation, "platform_services.write"}

  def for_request("POST", ["admin", "api", "platform", "credentials"]),
    do: {:installation, "platform_services.write"}

  def for_request(method, ["admin", "api", "platform", "credentials", _id])
      when method in ["PATCH", "DELETE"],
      do: {:installation, "platform_services.write"}

  def for_request(method, ["admin", "api", "tenants", tenant | rest]) do
    tenant_requirement(method, tenant, rest)
  end

  def for_request("POST", [prefix, "samples", action])
      when prefix in ["admin", "api"] and action in ["calls", "transfers"],
      do: :authenticated

  def for_request("GET", ["admin", "diagnostics" | _rest]),
    do: :superadmin

  def for_request("GET", ["tenants", tenant, "calls" | _rest]),
    do: {:tenant, "calls.read", tenant}

  def for_request(_method, _segments), do: :unknown

  # Dashboard admits any visible tenant; the Calls boundary conceals foreign identities.
  defp tenant_requirement("GET", _tenant, ["dashboard"]), do: :authenticated

  defp tenant_requirement("GET", tenant, ["providers"]),
    do: {:tenant, "call_specs.read", tenant}

  defp tenant_requirement("GET", tenant, ["providers", _provider, "models"]),
    do: {:tenant, "call_specs.read", tenant}

  defp tenant_requirement("GET", tenant, ["call-spec-editor-lookups"]),
    do: {:tenant, "call_specs.read", tenant}

  defp tenant_requirement("GET", tenant, ["telephony-services", _service, "numbers"]),
    do: {:tenant, "call_specs.write", tenant}

  defp tenant_requirement("GET", tenant, ["call-specs"]),
    do: {:tenant, "call_specs.read", tenant}

  defp tenant_requirement("GET", tenant, ["call-specs", _id]),
    do: {:tenant, "call_specs.read", tenant}

  defp tenant_requirement("POST", tenant, ["call-specs"]),
    do: {:tenant, "call_specs.write", tenant}

  defp tenant_requirement("PUT", tenant, ["call-specs", _id]),
    do: {:tenant, "call_specs.write", tenant}

  defp tenant_requirement("POST", tenant, ["call-specs", _id, "revisions", _revision, "publish"]),
    do: {:tenant, "call_specs.write", tenant}

  defp tenant_requirement("GET", tenant, ["calls"]),
    do: {:tenant, "calls.read", tenant}

  defp tenant_requirement("GET", tenant, ["calls", _id]),
    do: {:tenant, "calls.read", tenant}

  defp tenant_requirement("GET", tenant, ["services"]),
    do: {:tenant, "tenant_services.read", tenant}

  defp tenant_requirement("GET", tenant, ["service-bindings"]),
    do: {:tenant, "tenant_services.read", tenant}

  defp tenant_requirement("GET", tenant, ["telephony-applications"]),
    do: {:tenant, "tenant_services.read", tenant}

  defp tenant_requirement("GET", tenant, ["credentials"]),
    do: {:tenant, "tenant_services.read", tenant}

  defp tenant_requirement("POST", tenant, ["telephony-applications"]),
    do: {:tenant, "tenant_services.write", tenant}

  defp tenant_requirement("PATCH", tenant, ["telephony-applications", _id]),
    do: {:tenant, "tenant_services.write", tenant}

  defp tenant_requirement("POST", tenant, ["credentials"]),
    do: {:tenant, "tenant_api_keys.write", tenant}

  defp tenant_requirement("POST", tenant, ["credentials", "test"]),
    do: {:tenant, "tenant_api_keys.write", tenant}

  defp tenant_requirement(method, tenant, ["credentials", _id])
       when method in ["PATCH", "DELETE"],
       do: {:tenant, "tenant_api_keys.write", tenant}

  defp tenant_requirement(_method, _tenant, _rest), do: :unknown
end
