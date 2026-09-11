defmodule Vxpipe.CallEngine.Tool.InvocationUsage do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{InvocationRecord, InvocationSubmission}
  alias Vxpipe.CallEngine.Usage.ToolAttempt

  @spec configuration(keyword() | nil) ::
          {:ok, keyword() | nil} | {:error, :invalid_usage_context}
  def configuration(nil), do: {:ok, nil}

  def configuration(options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, [:call_id, :activation_id]),
         call_id when is_binary(call_id) and call_id != "" <- Keyword.get(options, :call_id),
         activation_id when is_binary(activation_id) and activation_id != "" <-
           Keyword.get(options, :activation_id) do
      {:ok, [call_id: call_id, activation_id: activation_id]}
    else
      _invalid -> {:error, :invalid_usage_context}
    end
  end

  def configuration(_options), do: {:error, :invalid_usage_context}

  @spec started(InvocationRecord.t(), keyword() | nil, pid() | nil, pid()) ::
          InvocationRecord.t()
  def started(%InvocationRecord{} = record, nil, _target, _capability), do: record

  def started(
        %InvocationRecord{submission: %InvocationSubmission{} = submission} = record,
        usage,
        target,
        capability
      )
      when is_list(usage) do
    with {:ok, attempt, observations} <-
           ToolAttempt.start(
             Keyword.fetch!(usage, :call_id),
             Keyword.fetch!(usage, :activation_id),
             submission,
             DateTime.utc_now(:millisecond)
           ) do
      publish(target, capability, observations)
      InvocationRecord.attach_usage(record, attempt)
    else
      {:error, :invalid_tool_usage} -> record
    end
  end

  @spec settled(InvocationRecord.t(), pid() | nil, pid()) :: :ok
  def settled(%InvocationRecord{usage_attempt: nil}, _target, _capability), do: :ok

  def settled(%InvocationRecord{} = record, target, capability) do
    with {:ok, observations} <-
           ToolAttempt.finish(
             record.usage_attempt,
             record.completion,
             DateTime.utc_now(:millisecond)
           ) do
      publish(target, capability, observations)
    else
      {:error, :invalid_tool_usage} -> :ok
    end
  end

  defp publish(target, capability, observations)
       when is_pid(target) and is_pid(capability) and is_list(observations) and
              observations != [] do
    send(target, {:vxpipe_usage_observations, capability, observations})
    :ok
  end

  defp publish(_target, _capability, _observations), do: :ok
end
