defmodule Vxpipe.AgentRuntime.ModelContext do
  @moduledoc false

  @default_timeout_ms 1_000
  @default_maximum_bytes 256 * 1_024
  @reserved_keys ["pending_tool_invocations"]

  @type source :: nil | {module(), term()}

  @spec fetch(source(), map(), keyword()) ::
          {:ok, map()}
          | {:error,
             :invalid_model_context
             | :invalid_model_context_options
             | :model_context_too_large
             | :model_context_unavailable}
  def fetch(source, correlation, options \\ [])

  def fetch(source, correlation, options) when is_map(correlation) and is_list(options) do
    with {:ok, options} <- Keyword.validate(options, [:timeout_ms, :maximum_bytes]),
         {:ok, timeout_ms} <- positive(Keyword.get(options, :timeout_ms, @default_timeout_ms)),
         {:ok, maximum_bytes} <-
           positive(Keyword.get(options, :maximum_bytes, @default_maximum_bytes)),
         {:ok, context} <- fetch_source(source, correlation, timeout_ms),
         {:ok, context} <- normalize(context, maximum_bytes) do
      {:ok, context}
    else
      {:error, reason}
      when reason in [
             :invalid_model_context,
             :model_context_too_large,
             :model_context_unavailable
           ] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :invalid_model_context_options}

      _invalid ->
        {:error, :model_context_unavailable}
    end
  end

  def fetch(_source, _correlation, _options), do: {:error, :model_context_unavailable}

  defp fetch_source(nil, _correlation, _timeout_ms), do: {:ok, %{}}

  defp fetch_source({module, source}, correlation, timeout_ms) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :snapshot, 3) do
      call_source(module, source, correlation, timeout_ms)
    else
      _invalid -> {:error, :model_context_unavailable}
    end
  end

  defp fetch_source(_source, _correlation, _timeout_ms),
    do: {:error, :model_context_unavailable}

  defp call_source(module, source, correlation, timeout_ms) do
    task = Task.async(fn -> invoke_source(module, source, correlation, timeout_ms) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, context}} -> {:ok, context}
      _unavailable -> {:error, :model_context_unavailable}
    end
  end

  defp invoke_source(module, source, correlation, timeout_ms) do
    try do
      case module.snapshot(source, correlation, timeout_ms) do
        {:ok, context} -> {:ok, context}
        _error -> {:error, :model_context_unavailable}
      end
    rescue
      _error -> {:error, :model_context_unavailable}
    catch
      _kind, _reason -> {:error, :model_context_unavailable}
    end
  end

  defp normalize(context, maximum_bytes) when is_map(context) do
    cond do
      not json_value?(context) ->
        {:error, :invalid_model_context}

      Enum.any?(@reserved_keys, &Map.has_key?(context, &1)) ->
        {:error, :invalid_model_context}

      encoded_size(context) > maximum_bytes ->
        {:error, :model_context_too_large}

      true ->
        {:ok, context}
    end
  rescue
    _error -> {:error, :invalid_model_context}
  end

  defp normalize(_context, _maximum_bytes), do: {:error, :invalid_model_context}

  defp encoded_size(context), do: context |> JSON.encode!() |> byte_size()

  defp json_value?(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: true

  defp json_value?(nil), do: true
  defp json_value?(value) when is_list(value), do: Enum.all?(value, &json_value?/1)

  defp json_value?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, entry} -> is_binary(key) and json_value?(entry) end)
  end

  defp json_value?(_value), do: false

  defp positive(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value), do: {:error, :invalid_limit}
end
