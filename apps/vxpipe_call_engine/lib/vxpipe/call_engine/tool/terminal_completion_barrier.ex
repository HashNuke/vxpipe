defmodule Vxpipe.CallEngine.Tool.TerminalCompletionBarrier do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.InvocationRegistry

  @default_timeout_ms 30_000
  @poll_interval_ms 5

  @doc """
  Waits until every ordinary invocation in this batch finishes.

  Only observes via `InvocationRegistry.peek_completion/2`; never leases or
  consumes, so original invocation correlation and caller-turn admission for
  nonblocking tools are preserved. Never calls Room (room may submit
  synchronously); only short registry calls, so no GenServer cycle and no
  deadlock with completion delivery.

  Returns `:ok` when all ordinaries succeeded, `{:error, :ordinary_failed}`
  when any ordinary finished with error (caller must withhold terminal effect
  and return a correlated result for a later distinct proposal), or
  `{:error, :timeout | :stale}` under the absolute bound / stale activation.
  """
  @spec await_ordinary(GenServer.server(), [String.t()], keyword()) ::
          :ok | {:error, :ordinary_failed | :timeout | :stale}
  def await_ordinary(registry, ordinary_ids, opts \\ [])

  def await_ordinary(_registry, [], _opts), do: :ok

  def await_ordinary(registry, ordinary_ids, opts) when is_list(ordinary_ids) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @poll_interval_ms)
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    poll(registry, ordinary_ids, deadline_ms, poll_interval_ms)
  end

  defp poll(registry, ordinary_ids, deadline_ms, poll_interval_ms) do
    case check_all(registry, ordinary_ids) do
      :ok ->
        :ok

      {:error, :ordinary_failed} = error ->
        error

      {:error, :stale} = error ->
        error

      :running ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          {:error, :timeout}
        else
          Process.sleep(poll_interval_ms)
          poll(registry, ordinary_ids, deadline_ms, poll_interval_ms)
        end
    end
  end

  defp check_all(registry, ordinary_ids) do
    Enum.reduce_while(ordinary_ids, :ok, fn invocation_id, :ok ->
      case safe_peek(registry, invocation_id) do
        {:ok, :running} -> {:halt, :running}
        {:ok, {:ok, _result}} -> {:cont, :ok}
        {:ok, :consumed} -> {:cont, :ok}
        {:ok, {:error, _reason}} -> {:halt, {:error, :ordinary_failed}}
        {:error, _reason} -> {:halt, {:error, :stale}}
      end
    end)
  end

  defp safe_peek(registry, invocation_id) do
    InvocationRegistry.peek_completion(registry, invocation_id)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
