defmodule Vxpipe.Gateway.Telephony.OutgoingLegConnector do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.OutboundLegConnector

  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest
  alias Vxpipe.Gateway.Id

  alias Vxpipe.Gateway.Telephony.{
    LegSupervisor,
    MediaAdmission,
    OutgoingLeg,
    OutgoingLegReference,
    ServiceRegistry
  }

  @disconnect_timeout 5_000

  @impl true
  def connect(options, %OutboundLegRequest{} = request, timeout)
      when is_list(options) and is_integer(timeout) and timeout > 0 do
    clock = Keyword.get(options, :monotonic_clock, fn -> System.monotonic_time(:millisecond) end)
    deadline = clock.() + timeout

    with {:ok, registry} <- service_registry(options),
         {:ok, service} <-
           ServiceRegistry.fetch_for_tenant(
             registry,
             request.service_id,
             request.tenant_id,
             request.service_reference
           ),
         true <- clock.() < deadline,
         {:ok, leg_id} <- generate_leg_id(options) do
      start_leg(options, request, service, leg_id, deadline, clock)
    else
      false -> {:error, :outbound_connection_unavailable}
      {:error, _reason} -> {:error, :outbound_connection_unavailable}
    end
  catch
    :exit, _reason -> {:error, :outbound_connection_unavailable}
  end

  def connect(_options, %OutboundLegRequest{}, _timeout) do
    {:error, :outbound_connection_unavailable}
  end

  @impl true
  def disconnect(_options, %OutgoingLegReference{purpose: :initial} = reference),
    do: OutgoingLeg.abandon(reference.leg)

  def disconnect(_options, %OutgoingLegReference{} = reference) do
    case OutgoingLeg.disconnect(reference.leg, @disconnect_timeout) do
      :ok ->
        :ok

      {:error, :telephony_leg_unavailable} ->
        stop_local_owner(reference)
    end
  catch
    :exit, _reason -> :ok
  end

  def disconnect(_options, _reference), do: {:error, :invalid_outbound_leg_reference}

  @impl true
  def owner(_options, %OutgoingLegReference{leg: leg}) when is_pid(leg), do: {:ok, leg}
  def owner(_options, _reference), do: {:error, :invalid_outbound_leg_reference}

  defp stop_local_owner(reference) do
    case DynamicSupervisor.terminate_child(reference.supervisor, reference.leg) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  defp start_leg(options, request, service, leg_id, deadline, clock) do
    supervisor = Keyword.get(options, :leg_supervisor, LegSupervisor)
    media_admission = Keyword.get(options, :media_admission, MediaAdmission)

    runtime_options =
      options
      |> Keyword.take([:media_supervisor, :usage_clock, :usage_reporter])
      |> Keyword.merge(deadline_ms: deadline, monotonic_clock: clock)

    case LegSupervisor.start_outgoing(
           supervisor,
           leg_id,
           request,
           service,
           media_admission,
           runtime_options
         ) do
      {:ok, leg} ->
        await_leg(supervisor, leg, leg_id, max(deadline - clock.(), 0), request.purpose)

      {:error, _reason} ->
        {:error, :outbound_connection_unavailable}
    end
  end

  defp await_leg(supervisor, leg, leg_id, 0, :initial),
    do: unknown_reference(supervisor, leg, leg_id)

  defp await_leg(supervisor, leg, _leg_id, 0, _purpose) do
    _ = DynamicSupervisor.terminate_child(supervisor, leg)
    {:error, :outbound_connection_unavailable}
  end

  defp await_leg(supervisor, leg, leg_id, timeout, purpose) do
    case OutgoingLeg.await(leg, timeout) do
      :ok ->
        {:ok,
         %OutgoingLegReference{leg: leg, leg_id: leg_id, supervisor: supervisor, purpose: purpose}}

      {:ok, :unknown} ->
        unknown_reference(supervisor, leg, leg_id)

      {:error, :telephony_leg_unavailable} when purpose == :initial ->
        unknown_reference(supervisor, leg, leg_id)

      {:error, _reason} ->
        _ = DynamicSupervisor.terminate_child(supervisor, leg)
        {:error, :outbound_connection_unavailable}
    end
  end

  defp unknown_reference(supervisor, leg, leg_id),
    do:
      {:ok,
       %OutgoingLegReference{leg: leg, leg_id: leg_id, supervisor: supervisor, purpose: :initial},
       :unknown}

  defp service_registry(options) do
    case Keyword.get(options, :service_registry) do
      %ServiceRegistry{} = registry -> {:ok, registry}
      _missing -> {:error, :service_registry_unavailable}
    end
  end

  defp generate_leg_id(options) do
    generator = Keyword.get(options, :leg_id, fn -> Id.generate(:telephony_leg) end)

    case generator.() do
      leg_id when is_binary(leg_id) and byte_size(leg_id) > 0 and byte_size(leg_id) <= 128 ->
        {:ok, leg_id}

      _invalid ->
        {:error, :invalid_telephony_leg_id}
    end
  rescue
    _exception -> {:error, :invalid_telephony_leg_id}
  end
end
