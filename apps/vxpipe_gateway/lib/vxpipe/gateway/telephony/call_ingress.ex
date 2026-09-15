defmodule Vxpipe.Gateway.Telephony.CallIngress do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.IngressHandler

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, Leg, LegSupervisor}

  @default_timeout 5_000

  @impl true
  def handle_event(
        options,
        %ConfiguredService{} = service,
        %Event{kind: :incoming} = event,
        {:incoming, leg}
      ) do
    Leg.await(leg, service, event, Keyword.get(options, :timeout, @default_timeout))
  end

  def handle_event(
        options,
        %ConfiguredService{} = service,
        %Event{} = event,
        {_kind, _leg} = owner
      ) do
    LegSupervisor.dispatch_owner(
      owner,
      service.identity,
      event,
      Keyword.get(options, :timeout, @default_timeout)
    )
  end

  def handle_event(options, %ConfiguredService{} = service, %Event{kind: :incoming} = event, nil) do
    backend = Keyword.get(options, :backend, {CallAdmission, []})
    supervisor = Keyword.get(options, :leg_supervisor, LegSupervisor)
    clock = Keyword.get(options, :clock, &DateTime.utc_now/0)
    timeout = Keyword.get(options, :timeout, @default_timeout)

    with {:ok, leg} <- LegSupervisor.start(supervisor, service, event, backend, clock) do
      Leg.await(leg, service, event, timeout)
    end
  end

  def handle_event(_options, %ConfiguredService{}, %Event{}, nil), do: {:error, :leg_not_found}
end
