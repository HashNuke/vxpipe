defmodule Vxpipe.CallEngine.Speech.EventQueue do
  @moduledoc false

  defstruct sequence: 0,
            awaiting: nil,
            pending: {[], []},
            pending_count: 0,
            ready?: false

  def new, do: %__MODULE__{pending: :queue.new()}
  def count(%__MODULE__{} = events), do: events.pending_count
  def ready?(%__MODULE__{} = events), do: events.ready?
  def full?(%__MODULE__{} = events, maximum), do: events.pending_count >= maximum

  def enqueue(%__MODULE__{} = events, event, allocation, producer) do
    event = %{
      event
      | session: allocation,
        generation: allocation.generation,
        producer: producer,
        sequence: events.sequence + 1
    }

    events = %{
      events
      | sequence: event.sequence,
        pending: :queue.in(event, events.pending),
        pending_count: events.pending_count + 1,
        ready?: events.ready? or event.kind == :ready
    }

    {event, events}
  end

  def acknowledge(%__MODULE__{awaiting: event} = events, event) when not is_nil(event),
    do: {:ok, %{events | awaiting: nil}}

  def acknowledge(%__MODULE__{}, _event), do: {:error, :stale_event}

  def take(%__MODULE__{awaiting: nil, pending_count: count} = events) when count > 0 do
    {{:value, event}, pending} = :queue.out(events.pending)
    {:ok, event, %{events | awaiting: event, pending: pending, pending_count: count - 1}}
  end

  def take(%__MODULE__{}), do: :empty
end
