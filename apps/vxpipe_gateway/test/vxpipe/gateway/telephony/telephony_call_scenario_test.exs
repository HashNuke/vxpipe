defmodule Vxpipe.Gateway.TelephonyCallScenarioTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.{TestTelephonyServiceRepository, TwilioCallScenario}

  test "independent scenarios isolate retained webhook owners and credential bindings" do
    first = TwilioCallScenario.build(self(), self(), "incoming", "outgoing")
    second = TwilioCallScenario.build(self(), self(), "incoming", "outgoing")
    first_service = TestTelephonyServiceRepository.configured(first.service_options)
    second_service = TestTelephonyServiceRepository.configured(second.service_options)

    refute first_service.identity.ingress_key == second_service.identity.ingress_key
    refute first_service.identity.service_reference == second_service.identity.service_reference
    refute first.plan.tenant_id == second.plan.tenant_id
  end
end
