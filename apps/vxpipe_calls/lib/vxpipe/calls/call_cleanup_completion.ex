defmodule Vxpipe.Calls.CallCleanupCompletion do
  @moduledoc "Persists trusted exact-owner cleanup acknowledgement before requesting publication."

  alias Vxpipe.Calls.{PreparedCall, PublicationTriggers, Repositories}

  def complete(binding, completed_at, options) when is_list(options) do
    with :ok <- validate_binding(binding),
         :ok <- validate_time(completed_at) do
      persist(binding, completed_at, options)
    end
  end

  def complete(_binding, _completed_at, _options), do: {:error, :invalid_call_cleanup}

  defp persist(binding, completed_at, options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository),
         {:ok, call} <-
           persist_result(
             Repositories.call(repository, :complete_call_cleanup, [binding, completed_at]),
             binding
           ) do
      _result = PublicationTriggers.request(binding.tenant_key, binding.call_id, options)
      {:ok, call}
    else
      {:error, reason}
      when reason in [
             :not_found,
             :invalid_call_cleanup,
             :call_room_mismatch,
             :call_incarnation_mismatch,
             :cleanup_reservation_unavailable
           ] ->
        {:error, reason}

      _unavailable ->
        {:error, :call_cleanup_unavailable}
    end
  rescue
    _error -> {:error, :call_cleanup_unavailable}
  catch
    _kind, _reason -> {:error, :call_cleanup_unavailable}
  end

  defp persist_result({:ok, %PreparedCall{} = call}, binding) do
    if call.tenant_key == binding.tenant_key and call.id == binding.call_id and
         call.room_id == binding.room_id and call.incarnation_id == binding.incarnation_id and
         call.gateway_cleanup_required and match?(%DateTime{}, call.gateway_cleanup_completed_at),
       do: {:ok, call},
       else: {:error, :call_cleanup_unavailable}
  end

  defp persist_result({:error, reason}, _binding), do: {:error, reason}
  defp persist_result(_result, _binding), do: {:error, :call_cleanup_unavailable}

  defp validate_binding(
         %{tenant_key: tenant, call_id: call, room_id: room, incarnation_id: incarnation} =
           binding
       )
       when map_size(binding) == 4 do
    if Enum.all?([tenant, call, room, incarnation], &identifier?/1),
      do: :ok,
      else: {:error, :invalid_call_cleanup}
  end

  defp validate_binding(_binding), do: {:error, :invalid_call_cleanup}

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.valid?(value) and not String.contains?(value, [<<0>>, "\n", "\r"])

  defp identifier?(_value), do: false

  defp validate_time(%DateTime{calendar: Calendar.ISO, utc_offset: 0, std_offset: 0} = time) do
    _ = DateTime.to_unix(time, :microsecond)
    :ok
  rescue
    _invalid -> {:error, :invalid_call_cleanup}
  end

  defp validate_time(_time), do: {:error, :invalid_call_cleanup}
end
