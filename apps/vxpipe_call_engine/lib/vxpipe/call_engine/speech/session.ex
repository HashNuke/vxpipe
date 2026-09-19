defmodule Vxpipe.CallEngine.Speech.Session do
  @moduledoc """
  Speech allocations inside an explicitly owned `Speech.CapabilityTree` scope.
  `start/2` reserves one of two local slots and returns `{:ok, allocation, :starting}`.
  Wait for and acknowledge the allocation's ready event before submitting input.
  Prepared allocations use a lease authority and `consumer: nil`; `adopt/2` changes
  delivery authority while retaining their original supervised parent.
  """

  alias Vxpipe.CallEngine.Speech.{
    Allocation,
    Channel,
    ProviderName,
    Scope,
    ScopeControl,
    SessionTree
  }

  @timeout 5_000
  @maximum_audio_bytes 131_072

  def start(%Scope{} = scope, options) do
    budget = Keyword.get(options, :start_timeout, @timeout)
    timeout = Keyword.get(options, :call_timeout, @timeout)

    if is_integer(budget) and budget > 0 and is_integer(timeout) and timeout in 1..@timeout and
         valid_roles?(options) do
      reserve(scope, options, budget, timeout)
    else
      {:error, :invalid_configuration}
    end
  end

  defp valid_roles?(options) do
    owner = Keyword.get(options, :owner, self())
    consumer = Keyword.get(options, :consumer, owner)
    lease = Keyword.get(options, :lease)

    is_pid(owner) and
      ((is_pid(consumer) and is_nil(lease)) or (is_nil(consumer) and is_pid(lease)))
  end

  defp reserve(scope, options, budget, timeout) do
    owner = Keyword.get(options, :owner, self())

    allocation = %Allocation{
      scope: scope,
      generation: make_ref(),
      owner: owner,
      consumer: Keyword.get(options, :consumer, owner),
      lease: Keyword.get(options, :lease),
      deadline: System.monotonic_time(:millisecond) + budget,
      token: :atomics.new(1, []),
      call_timeout: timeout
    }

    try do
      case ScopeControl.reserve(
             allocation,
             options,
             min(remaining(allocation.deadline), @timeout)
           ) do
        {:ok, _, :starting} = result ->
          result

        error ->
          Allocation.cancel(allocation)
          error
      end
    catch
      :exit, _reason ->
        Allocation.cancel(allocation)
        {:error, :unavailable}
    end
  end

  def describe(allocation) do
    with {:ok, metadata} <- metadata(allocation), do: {:ok, metadata.descriptor}
  end

  def adopt(allocation, consumer) do
    command = command(allocation)

    try do
      result = request(allocation, {:adopt, consumer, command}, command.deadline)

      if result == :ok and remaining(command.deadline) == 0,
        do: adoption_timeout(allocation, command),
        else: result
    catch
      :exit, {:timeout, _call} -> adoption_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  def ack(allocation, event), do: call(allocation, {:ack, event})

  def push_audio(allocation, audio)
      when is_binary(audio) and byte_size(audio) in 1..@maximum_audio_bytes do
    command = command(allocation)

    try do
      if Allocation.valid?(allocation) do
        GenServer.call(
          Channel.address(allocation),
          {:input, allocation, command, audio},
          remaining(command.deadline)
        )
      else
        {:error, :closed}
      end
    catch
      :exit, {:timeout, _call} ->
        input_timeout(allocation, command)

      :exit, _reason ->
        if(Allocation.valid?(allocation), do: {:error, :session_failed}, else: {:error, :closed})
    end
  end

  def push_audio(_allocation, audio) when is_binary(audio), do: {:error, :invalid_audio_size}
  def push_audio(_allocation, _audio), do: {:error, :invalid_audio}

  def close(allocation) do
    deadline = System.monotonic_time(:millisecond) + allocation.call_timeout

    case ScopeControl.close(allocation, :closed, deadline) do
      {:ok, tree} -> await_closed(tree, deadline)
      error -> error
    end
  catch
    :exit, {:timeout, _call} -> {:error, :close_timeout}
    :exit, _reason -> if(tree(allocation), do: {:error, :unavailable}, else: :ok)
  end

  defp await_closed(nil, _deadline), do: :ok

  defp await_closed(tree, deadline) do
    monitor = Process.monitor(tree)

    try do
      receive do
        {:DOWN, ^monitor, :process, ^tree, _reason} -> :ok
      after
        remaining(deadline) -> {:error, :close_timeout}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  @doc false
  def tree(allocation), do: GenServer.whereis(SessionTree.address(allocation))
  @doc false
  def provider(allocation) do
    case ProviderName.whereis_name(allocation) do
      :undefined -> nil
      pid -> pid
    end
  end

  defp metadata(allocation), do: call(allocation, :metadata)

  defp call(allocation, message) do
    deadline = System.monotonic_time(:millisecond) + allocation.call_timeout

    request(allocation, message, deadline)
  catch
    :exit, {:timeout, _call} -> {:error, :command_timeout}
    :exit, _reason -> {:error, :closed}
  end

  defp request(allocation, message, deadline) do
    if Allocation.valid?(allocation),
      do:
        GenServer.call(
          Channel.address(allocation),
          {:command, allocation, deadline, message},
          remaining(deadline)
        ),
      else: {:error, :closed}
  end

  defp command(allocation) do
    %{
      ref: make_ref(),
      deadline: System.monotonic_time(:millisecond) + allocation.call_timeout,
      token: :atomics.new(1, [])
    }
  end

  defp adoption_timeout(allocation, command) do
    if :atomics.compare_exchange(command.token, 1, 0, 2) == 1, do: retire(allocation)
    {:error, :command_timeout}
  end

  defp input_timeout(allocation, command) do
    # Only the Channel can admit this fresh ticket after checking current authority.
    # Cancelling a queued command must not revoke an otherwise usable allocation.
    case :atomics.compare_exchange(command.token, 1, 0, 2) do
      :ok ->
        {:error, :command_timeout}

      1 ->
        retire(allocation)
        {:error, :session_failed}
    end
  end

  defp retire(allocation) do
    Allocation.cancel(allocation)
    ScopeControl.failed(allocation, :session_failed)
    if pid = provider(allocation), do: Process.exit(pid, :kill)
    if pid = GenServer.whereis(Channel.address(allocation)), do: Process.exit(pid, :kill)
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
