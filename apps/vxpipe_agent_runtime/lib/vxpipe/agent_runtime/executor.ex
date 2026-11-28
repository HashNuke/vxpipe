defmodule Vxpipe.AgentRuntime.Executor do
  @moduledoc "The private submit-only tool boundary implemented by a runtime host."

  @type conversation_mode :: :blocking | :non_blocking | :await_completion
  @type submission_error :: :rejected | :saturated | :unavailable | :caller_answer_pending

  @callback submit(
              binding :: term(),
              arguments :: map(),
              context :: map(),
              invocation_id :: String.t()
            ) :: {:accepted, conversation_mode()} | {:error, submission_error()}

  @callback preflight(
              binding :: term(),
              arguments :: map(),
              context :: map(),
              invocation_id :: String.t()
            ) :: :ok | {:error, submission_error()}

  @callback await_ordinary_completions(
              context :: map(),
              ordinary_invocation_ids :: [String.t()]
            ) :: :ok | {:error, :ordinary_failed | :timeout | :stale | :unavailable}

  @optional_callbacks preflight: 4, await_ordinary_completions: 2

  @spec submit(module(), term(), map(), map(), String.t()) ::
          {:accepted, conversation_mode()} | {:error, submission_error()}
  def submit(executor, binding, arguments, context, invocation_id)
      when is_atom(executor) and is_map(arguments) and is_map(context) and
             is_binary(invocation_id) do
    try do
      case executor.submit(binding, arguments, context, invocation_id) do
        {:accepted, mode} when mode in [:blocking, :non_blocking, :await_completion] ->
          {:accepted, mode}

        {:error, reason}
        when reason in [:rejected, :saturated, :unavailable, :caller_answer_pending] ->
          {:error, reason}

        _invalid ->
          {:error, :unavailable}
      end
    rescue
      _error -> {:error, :unavailable}
    catch
      _kind, _reason -> {:error, :unavailable}
    end
  end

  def submit(_executor, _binding, _arguments, _context, _invocation_id),
    do: {:error, :unavailable}

  @spec preflight(module(), term(), map(), map(), String.t()) ::
          :ok | {:error, submission_error()}
  def preflight(executor, binding, arguments, context, invocation_id)
      when is_atom(executor) and is_map(arguments) and is_map(context) and
             is_binary(invocation_id) do
    if Code.ensure_loaded?(executor) and function_exported?(executor, :preflight, 4) do
      try do
        case executor.preflight(binding, arguments, context, invocation_id) do
          :ok ->
            :ok

          {:error, reason}
          when reason in [:rejected, :saturated, :unavailable, :caller_answer_pending] ->
            {:error, reason}

          _invalid ->
            {:error, :unavailable}
        end
      rescue
        _error -> {:error, :unavailable}
      catch
        _kind, _reason -> {:error, :unavailable}
      end
    else
      :ok
    end
  end

  def preflight(_executor, _binding, _arguments, _context, _invocation_id), do: :ok

  @spec await_ordinary_completions(module(), map(), [String.t()]) ::
          :ok | {:error, :ordinary_failed | :timeout | :stale | :unavailable}
  def await_ordinary_completions(executor, context, ordinary_ids)
      when is_atom(executor) and is_map(context) and is_list(ordinary_ids) do
    if Code.ensure_loaded?(executor) and
         function_exported?(executor, :await_ordinary_completions, 2) do
      try do
        case executor.await_ordinary_completions(context, ordinary_ids) do
          :ok ->
            :ok

          {:error, reason}
          when reason in [:ordinary_failed, :timeout, :stale, :unavailable] ->
            {:error, reason}

          _invalid ->
            {:error, :unavailable}
        end
      rescue
        _error -> {:error, :unavailable}
      catch
        _kind, _reason -> {:error, :unavailable}
      end
    else
      :ok
    end
  end

  def await_ordinary_completions(_executor, _context, _ordinary_ids), do: :ok
end
