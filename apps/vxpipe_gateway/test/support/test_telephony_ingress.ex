defmodule Vxpipe.Gateway.TestTelephonyIngress do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.IngressHandler

  @impl true
  def handle_event({observer, result}, service, event, _owner) do
    send(observer, {:telephony_event, service.identity, event})
    result
  end

  def handle_event(observer, service, event, _owner) do
    send(observer, {:telephony_event, service.identity, event})
    :ok
  end
end
