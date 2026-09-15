defmodule Vxpipe.Calls.TestObservedTelephonyServiceRepository do
  @moduledoc false

  def resolve({bindings, observer}, tenant_key, name) do
    send(observer, {:service_resolution, tenant_key, name})
    Vxpipe.Calls.TestTelephonyServiceRepository.resolve(bindings, tenant_key, name)
  end
end
