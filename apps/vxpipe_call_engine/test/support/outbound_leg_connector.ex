defmodule Vxpipe.CallEngine.TestOutboundLegConnector do
  @behaviour Vxpipe.CallEngine.Telephony.OutboundLegConnector

  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest

  @impl true
  def connect(observer, %OutboundLegRequest{} = request, timeout) do
    send(observer, {:test_outbound_leg_connect, self(), request, timeout})
    {:ok, request.participant_id}
  end

  @impl true
  def disconnect(observer, reference) do
    send(observer, {:test_outbound_leg_disconnect, self(), reference})
    :ok
  end
end
