defmodule Vxpipe.Gateway.Telephony.ServiceRegistryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.ServiceRegistry
  alias Vxpipe.Gateway.HTTP.{Router, TelephonyIngressConfig}

  test "disabled telephony cannot query or resolve tenant credentials" do
    registry = ServiceRegistry.init!(enabled: false)
    assert {:error, :disabled} = ServiceRegistry.fetch(registry, "ingress")

    assert {:error, :disabled} =
             ServiceRegistry.fetch_for_tenant(registry, "phone", "AAAAAAAAAAAAAAAA", nil)
  end

  test "retired static credentials are rejected without including their values in diagnostics" do
    retired = [enabled: true, services: [[api_key: "private-retired-credential"]]]

    for initialize <- [
          fn -> ServiceRegistry.init!(retired) end,
          fn -> TelephonyIngressConfig.init(retired) end,
          fn -> Router.init(telephony: retired) end
        ] do
      error = assert_raise ArgumentError, initialize
      refute Exception.message(error) =~ "private-retired-credential"
    end
  end
end
