defmodule Vxpipe.AgentRuntime.PendingContext do
  @moduledoc false

  alias Vxpipe.AgentRuntime.PendingInvocation

  @default_timeout_ms 1_000
  @default_maximum_invocations 32

  @type source :: {module(), term()}

  @spec fetch(source(), map(), keyword()) ::
          {:ok, [PendingInvocation.t()]}
          | {:error,
             :invalid_pending_context
             | :invalid_pending_context_options
             | :pending_context_too_large
             | :pending_context_unavailable}
  def fetch(source, correlation, options \\ [])

  def fetch({module, source}, correlation, options)
      when is_atom(module) and is_map(correlation) and is_list(options) do
    with {:ok, options} <- Keyword.validate(options, [:timeout_ms, :maximum_invocations]),
         {:ok, timeout_ms} <-
           positive_limit(Keyword.get(options, :timeout_ms, @default_timeout_ms)),
         {:ok, maximum_invocations} <-
           positive_limit(
             Keyword.get(options, :maximum_invocations, @default_maximum_invocations)
           ),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :snapshot, 3),
         {:ok, invocations} <- call_source(module, source, correlation, timeout_ms),
         {:ok, invocations} <- normalize(invocations, maximum_invocations) do
      {:ok, invocations}
    else
      {:error, reason}
      when reason in [:invalid_pending_context, :pending_context_too_large] ->
        {:error, reason}

      {:error, :pending_context_unavailable} ->
        {:error, :pending_context_unavailable}

      {:error, _reason} ->
        {:error, :invalid_pending_context_options}

      _unavailable ->
        {:error, :pending_context_unavailable}
    end
  end

  def fetch(_source, _correlation, _options), do: {:error, :pending_context_unavailable}

  defp call_source(module, source, correlation, timeout_ms) do
    task =
      Task.async(fn ->
        invoke_source(module, source, correlation, timeout_ms)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, invocations}} -> {:ok, invocations}
      _unavailable -> {:error, :pending_context_unavailable}
    end
  end

  defp invoke_source(module, source, correlation, timeout_ms) do
    try do
      case module.snapshot(source, correlation, timeout_ms) do
        {:ok, invocations} -> {:ok, invocations}
        _error -> {:error, :pending_context_unavailable}
      end
    rescue
      _error -> {:error, :pending_context_unavailable}
    catch
      _kind, _reason -> {:error, :pending_context_unavailable}
    end
  end

  defp normalize(invocations, maximum_invocations) when is_list(invocations),
    do: normalize(invocations, maximum_invocations, MapSet.new(), [])

  defp normalize(_invocations, _maximum_invocations), do: {:error, :invalid_pending_context}

  defp normalize([], _remaining, _invocation_ids, acc), do: {:ok, Enum.reverse(acc)}

  defp normalize([_invocation | _rest], 0, _invocation_ids, _acc),
    do: {:error, :pending_context_too_large}

  defp normalize([%PendingInvocation{} = invocation | rest], remaining, invocation_ids, acc) do
    cond do
      not PendingInvocation.valid?(invocation) ->
        {:error, :invalid_pending_context}

      MapSet.member?(invocation_ids, invocation.invocation_id) ->
        {:error, :invalid_pending_context}

      true ->
        normalize(
          rest,
          remaining - 1,
          MapSet.put(invocation_ids, invocation.invocation_id),
          [invocation | acc]
        )
    end
  end

  defp normalize([_invalid | _rest], _remaining, _invocation_ids, _acc),
    do: {:error, :invalid_pending_context}

  defp positive_limit(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_limit(_value), do: {:error, :invalid_limit}
end
