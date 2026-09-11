defmodule Vxpipe.Gateway.TestTelephonyIngress do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.IngressHandler

  @impl true
  def handle_event(observer, identity, event) do
    send(observer, {:telephony_event, identity, event})
    :ok
  end
end
