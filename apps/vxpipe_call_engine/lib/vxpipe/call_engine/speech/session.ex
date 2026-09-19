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
    owner = Keyword.get(options, :owner, self())

    allocation = %Allocation{
      scope: scope,
      generation: make_ref(),
      owner: owner,
      consumer: Keyword.get(options, :consumer, owner),
      lease: Keyword.get(options, :lease),
      deadline: System.monotonic_time(:millisecond) + budget,
      token: :atomics.new(1, [])
    }

    try do
      case ScopeControl.reserve(allocation, options, budget) do
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

  def adopt(allocation, consumer), do: call(allocation, {:adopt, consumer})
  def ack(allocation, event), do: call(allocation, {:ack, event})

  def push_audio(allocation, audio)
      when is_binary(audio) and byte_size(audio) in 1..@maximum_audio_bytes do
    deadline = System.monotonic_time(:millisecond) + @timeout

    with {:ok, metadata} <- metadata(allocation), true <- metadata.active? do
      invoke(
        allocation,
        min(deadline, System.monotonic_time(:millisecond) + metadata.call_timeout),
        fn ->
          metadata.module.push_audio(metadata.producer, audio)
        end
      )
    else
      false -> {:error, :not_ready}
      error -> error
    end
  end

  def push_audio(_allocation, audio) when is_binary(audio), do: {:error, :invalid_audio_size}
  def push_audio(_allocation, _audio), do: {:error, :invalid_audio}

  def close(allocation) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    tree = tree(allocation)
    monitor = if is_pid(tree), do: Process.monitor(tree)

    result = ScopeControl.close(allocation, :closed)

    if result == :ok and monitor do
      receive do
        {:DOWN, ^monitor, :process, ^tree, _reason} -> :ok
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          Process.demonitor(monitor, [:flush])
          {:error, :close_timeout}
      end
    else
      if monitor, do: Process.demonitor(monitor, [:flush])
      result
    end
  catch
    :exit, _reason -> :ok
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
    if Allocation.valid?(allocation),
      do: GenServer.call(Channel.address(allocation), message, @timeout),
      else: {:error, :closed}
  catch
    :exit, _reason -> {:error, :closed}
  end

  defp invoke(allocation, deadline, operation) do
    task =
      Task.Supervisor.async_nolink(SessionTree.commands(allocation), fn -> safely(operation) end)

    case Task.yield(task, max(deadline - System.monotonic_time(:millisecond), 0)) do
      {:ok, {:error, :session_failed}} ->
        fail(allocation)

      {:ok, result} ->
        result

      _failed ->
        Task.shutdown(task, :brutal_kill)
        fail(allocation)
    end
  catch
    :exit, _reason -> fail(allocation)
  end

  defp fail(allocation) do
    _result = ScopeControl.close(allocation, :session_failed)
    {:error, :session_failed}
  end

  defp safely(operation) do
    operation.()
  rescue
    _error -> {:error, :session_failed}
  catch
    _kind, _reason -> {:error, :session_failed}
  end
end
