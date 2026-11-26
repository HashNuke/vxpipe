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

  @optional_callbacks preflight: 4

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
end
