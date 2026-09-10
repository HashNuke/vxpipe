defmodule Vxpipe.AgentRuntime.StreamBudget do
  @moduledoc false

  @derive {Inspect, only: []}
  @enforce_keys [:counters, :maximum_bytes, :maximum_events, :emit]
  defstruct @enforce_keys

  @bytes_index 1
  @events_index 2
  @status_index 3

  @ok 0
  @output_too_large 1
  @stream_event_limit 2
  @invalid_provider_response 3
  @event_unavailable 4

  @type t :: %__MODULE__{}

  @spec new(non_neg_integer(), non_neg_integer(), (String.t() -> :ok | {:error, atom()})) ::
          t()
  def new(maximum_bytes, maximum_events, emit)
      when is_integer(maximum_bytes) and maximum_bytes >= 0 and is_integer(maximum_events) and
             maximum_events >= 0 and is_function(emit, 1) do
    %__MODULE__{
      counters: :atomics.new(3, signed: false),
      maximum_bytes: maximum_bytes,
      maximum_events: maximum_events,
      emit: emit
    }
  end

  @spec emit(t(), term()) :: :ok | {:error, atom()}
  def emit(%__MODULE__{} = budget, ""), do: outcome(budget)

  def emit(%__MODULE__{} = budget, text) when is_binary(text) do
    case outcome(budget) do
      :ok -> accept(budget, text)
      {:error, _reason} = error -> error
    end
  end

  def emit(%__MODULE__{} = budget, _invalid) do
    fail(budget, @invalid_provider_response, :invalid_provider_response)
  end

  @spec outcome(t()) :: :ok | {:error, atom()}
  def outcome(%__MODULE__{} = budget) do
    case :atomics.get(budget.counters, @status_index) do
      @ok -> :ok
      @output_too_large -> {:error, :output_too_large}
      @stream_event_limit -> {:error, :stream_event_limit}
      @invalid_provider_response -> {:error, :invalid_provider_response}
      @event_unavailable -> {:error, :event_unavailable}
    end
  end

  defp accept(budget, text) do
    bytes = :atomics.add_get(budget.counters, @bytes_index, byte_size(text))
    events = :atomics.add_get(budget.counters, @events_index, 1)

    cond do
      bytes > budget.maximum_bytes ->
        fail(budget, @output_too_large, :output_too_large)

      events > budget.maximum_events ->
        fail(budget, @stream_event_limit, :stream_event_limit)

      true ->
        emit_safely(budget, text)
    end
  end

  defp emit_safely(budget, text) do
    case budget.emit.(text) do
      :ok -> :ok
      _unavailable -> fail(budget, @event_unavailable, :event_unavailable)
    end
  rescue
    _error -> fail(budget, @event_unavailable, :event_unavailable)
  catch
    _kind, _reason -> fail(budget, @event_unavailable, :event_unavailable)
  end

  defp fail(budget, status, reason) do
    :atomics.put(budget.counters, @status_index, status)
    {:error, reason}
  end
end
