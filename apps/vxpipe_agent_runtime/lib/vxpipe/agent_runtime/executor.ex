defmodule Vxpipe.AgentRuntime.Executor do
  @moduledoc "The private submit-only tool boundary implemented by a runtime host."

  @type conversation_mode :: :blocking | :non_blocking
  @type submission_error :: :rejected | :saturated | :unavailable

  @callback submit(
              binding :: term(),
              arguments :: map(),
              context :: map(),
              invocation_id :: String.t()
            ) :: {:accepted, conversation_mode()} | {:error, submission_error()}

  @spec submit(module(), term(), map(), map(), String.t()) ::
          {:accepted, conversation_mode()} | {:error, submission_error()}
  def submit(executor, binding, arguments, context, invocation_id)
      when is_atom(executor) and is_map(arguments) and is_map(context) and
             is_binary(invocation_id) do
    try do
      case executor.submit(binding, arguments, context, invocation_id) do
        {:accepted, mode} when mode in [:blocking, :non_blocking] -> {:accepted, mode}
        {:error, reason} when reason in [:rejected, :saturated, :unavailable] -> {:error, reason}
        _invalid -> {:error, :unavailable}
      end
    rescue
      _error -> {:error, :unavailable}
    catch
      _kind, _reason -> {:error, :unavailable}
    end
  end

  def submit(_executor, _binding, _arguments, _context, _invocation_id),
    do: {:error, :unavailable}
end
