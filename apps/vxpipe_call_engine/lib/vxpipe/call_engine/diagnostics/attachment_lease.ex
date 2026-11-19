defmodule Vxpipe.CallEngine.Diagnostics.AttachmentLease do
  @moduledoc "Bounds unresolved attachment admission and prevents adoption after cancellation."
  @enforce_keys [:gate, :owner, :deadline, :clock, :state]
  @derive {Inspect, only: [:deadline]}
  defstruct @enforce_keys
  @phase 1
  @operations 2
  @finished 3
  @released 4

  def gate(capacity) when is_integer(capacity) and capacity in 1..32,
    do: %{capacity: capacity, counter: :atomics.new(1, signed: false)}

  def pending(gate), do: :atomics.get(gate.counter, 1)

  def reserve(gate, owner, options \\ []) do
    with true <- is_pid(owner) and node(owner) == node() and Process.alive?(owner),
         {:ok, options} <-
           Keyword.validate(options,
             timeout_ms: 500,
             clock: fn -> System.monotonic_time(:millisecond) end
           ),
         timeout when is_integer(timeout) and timeout in 1..500 <-
           Keyword.fetch!(options, :timeout_ms),
         clock when is_function(clock, 0) <- Keyword.fetch!(options, :clock),
         now when is_integer(now) <- clock.(),
         :ok <- take(gate, 16) do
      {:ok,
       %__MODULE__{
         gate: gate,
         owner: owner,
         deadline: now + timeout,
         clock: clock,
         state: :atomics.new(4, signed: false)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def current?(nil), do: true

  def current?(lease) do
    if Process.alive?(lease.owner) do
      case :atomics.get(lease.state, @phase) do
        1 -> true
        0 -> provisional?(lease)
        2 -> false
      end
    else
      cancel(lease)
      false
    end
  end

  def adopt(lease) do
    if current?(lease) and :atomics.compare_exchange(lease.state, @phase, 0, 1) == :ok do
      if lease.clock.() < lease.deadline do
        true
      else
        cancel(lease)
        false
      end
    else
      false
    end
  end

  def cancel(lease), do: :atomics.put(lease.state, @phase, 2)

  def remaining(nil), do: :infinity

  def remaining(lease),
    do: if(current?(lease), do: max(lease.deadline - lease.clock.(), 0), else: 0)

  def operation(nil, function), do: function.()

  def operation(lease, function) do
    :atomics.add(lease.state, @operations, 1)

    try do
      if :atomics.get(lease.state, @finished) == 0 and current?(lease),
        do: function.(),
        else: {:error, :unavailable}
    after
      :atomics.sub(lease.state, @operations, 1)
      release_if_resolved(lease)
    end
  end

  def finish(lease) do
    :atomics.put(lease.state, @finished, 1)
    release_if_resolved(lease)
  end

  defp provisional?(lease) do
    if lease.clock.() < lease.deadline,
      do: true,
      else: :atomics.compare_exchange(lease.state, @phase, 0, 2) == 1
  end

  defp release_if_resolved(lease) do
    if :atomics.get(lease.state, @finished) == 1 and
         :atomics.get(lease.state, @operations) == 0 and
         :atomics.compare_exchange(lease.state, @released, 0, 1) == :ok,
       do: :atomics.sub(lease.gate.counter, 1, 1)

    :ok
  end

  defp take(_gate, 0), do: {:error, :unavailable}

  defp take(gate, attempts) do
    count = pending(gate)

    cond do
      count >= gate.capacity -> {:error, :unavailable}
      :atomics.compare_exchange(gate.counter, 1, count, count + 1) == :ok -> :ok
      true -> take(gate, attempts - 1)
    end
  end
end
