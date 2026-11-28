defmodule Vxpipe.CallEngine.Tool.InvocationExecution do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding, as: VariablesBinding
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.Tool.{Context, InvocationBinding, PlatformResult}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer

  @spec run(InvocationBinding.t(), map(), Context.t(), pos_integer()) ::
          {:ok, term()} | {:error, :invalid_result | :tool_failed}
  def run(
        %InvocationBinding{handler: {:host, action}},
        arguments,
        %Context{} = context,
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    action
    |> execute(arguments, context)
    |> normalize(maximum_result_bytes)
  end

  def run(
        %InvocationBinding{handler: {:platform, action}},
        arguments,
        %Context{} = context,
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    action
    |> execute(arguments, context)
    |> normalize_platform(maximum_result_bytes)
  end

  def run(
        %InvocationBinding{
          name: name,
          handler: {:call_variables, %VariablesBinding{} = binding}
        },
        arguments,
        %Context{} = context,
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    binding
    |> VariablesBinding.execute(name, arguments, context)
    |> normalize(maximum_result_bytes)
  end

  def run(
        %InvocationBinding{name: name, handler: {:invalid_variable_arguments, binding}},
        arguments,
        %Context{} = context,
        maximum_result_bytes
      ) do
    binding
    |> VariablesBinding.reject_arguments(name, arguments, context)
    |> normalize(maximum_result_bytes)
  end

  def run(
        %InvocationBinding{handler: {:participant_transfer, binding}},
        arguments,
        %Context{} = context,
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    binding
    |> ParticipantTransfer.execute(arguments, context)
    |> normalize_platform(maximum_result_bytes)
  end

  def run(
        %InvocationBinding{name: name, handler: {:remote_mcp, owner}},
        arguments,
        %Context{},
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    owner
    |> IntegrationOwner.execute(name, arguments)
    |> normalize_remote(maximum_result_bytes)
  end

  def run(_binding, _arguments, _context, _maximum_result_bytes), do: {:error, :tool_failed}

  defp execute(action, arguments, context) do
    try do
      action.execute(arguments, context)
    rescue
      _exception -> {:error, :tool_failed}
    catch
      _kind, _reason -> {:error, :tool_failed}
    end
  end

  defp normalize({:ok, %PlatformResult{}}, _maximum_result_bytes),
    do: {:error, :invalid_result}

  defp normalize({:ok, result}, maximum_result_bytes) do
    try do
      if byte_size(JSON.encode!(result)) <= maximum_result_bytes do
        {:ok, result}
      else
        {:error, :invalid_result}
      end
    rescue
      _exception -> {:error, :invalid_result}
    end
  end

  defp normalize({:error, _reason} = error, _maximum_result_bytes),
    do: normalize_execution_error(error)

  defp normalize(_result, _maximum_result_bytes), do: {:error, :invalid_result}

  # Guardrail transfer verdicts travel as typed errors so the room, history
  # and model channels can distinguish disallowed destinations (:rejected),
  # matched policy questions (:transfer_denied, with private lines for the
  # originating model only) and checker outages (:transfer_unavailable).
  # Anything else stays a generic tool failure.
  defp normalize_execution_error({:error, reason} = error)
       when reason in [:rejected, :transfer_denied, :transfer_unavailable],
       do: error

  defp normalize_execution_error(
         {:error, {:transfer_denied, %{messages: lines, on_dispatch: callback} = receipt}} = error
       )
       when map_size(receipt) == 2 and is_function(callback, 0) do
    if denied_lines_valid?(lines), do: error, else: {:error, :tool_failed}
  end

  defp normalize_execution_error({:error, {:transfer_denied, lines}} = error)
       when is_list(lines) do
    if denied_lines_valid?(lines), do: error, else: {:error, :tool_failed}
  end

  defp normalize_execution_error({:error, _reason}), do: {:error, :tool_failed}

  # Denial lines are service-authored feedback for the originating model only.
  # Never forward unvalidated payloads toward history-adjacent channels.
  defp denied_lines_valid?(lines) when is_list(lines) and lines != [] do
    Enum.all?(lines, &(is_binary(&1) and &1 != "")) and
      byte_size(JSON.encode!(lines)) <= 4_096
  rescue
    _exception -> false
  end

  defp denied_lines_valid?(_lines), do: false

  defp normalize_platform(
         {:ok, %PlatformResult{effect: effect, result: result} = platform_result},
         maximum_result_bytes
       )
       when effect in [:hangup, :announced_hangup, :participant_transfer_committed] do
    case normalize({:ok, result}, maximum_result_bytes) do
      {:ok, _result} -> {:ok, platform_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_platform(outcome, maximum_result_bytes),
    do: normalize(outcome, maximum_result_bytes)

  defp normalize_remote({:error, reason} = error, _maximum_result_bytes)
       when reason in [:invalid_result, :unknown],
       do: error

  defp normalize_remote(result, maximum_result_bytes), do: normalize(result, maximum_result_bytes)
end
