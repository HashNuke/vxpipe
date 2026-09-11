defmodule Vxpipe.Gateway.Telephony.CallIngress do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.IngressHandler

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Telephony.{IngressIdentity, LegSupervisor}

  @default_timeout 5_000

  @impl true
  def handle_event(options, %IngressIdentity{} = identity, %Event{kind: :incoming} = event) do
    backend = Keyword.get(options, :backend, {CallAdmission, []})
    supervisor = Keyword.get(options, :leg_supervisor, LegSupervisor)
    clock = Keyword.get(options, :clock, &DateTime.utc_now/0)
    timeout = Keyword.get(options, :timeout, @default_timeout)

    with {:ok, leg} <- LegSupervisor.start(supervisor, identity, event, backend, clock) do
      Vxpipe.Gateway.Telephony.Leg.await(leg, timeout)
    end
  end

  def handle_event(options, %IngressIdentity{} = identity, %Event{} = event) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    LegSupervisor.dispatch(identity.service_id, event, timeout)
  end
end
