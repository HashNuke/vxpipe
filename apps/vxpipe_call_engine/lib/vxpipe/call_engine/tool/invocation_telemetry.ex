defmodule Vxpipe.CallEngine.Tool.InvocationTelemetry do
  @moduledoc false

  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.Tool.{InvocationCompletion, InvocationRecord}

  @type admission_outcome ::
          :accepted | :saturated | :start_failed | :unavailable | :invalid_tool

  @spec admission(admission_outcome(), non_neg_integer(), non_neg_integer()) :: :ok
  def admission(outcome, reserved, limit) do
    Telemetry.background_tool_admission(outcome, reserved, limit)
  end

  @spec settled(InvocationRecord.t()) :: :ok
  def settled(%InvocationRecord{completion: %InvocationCompletion{} = completion} = record) do
    Telemetry.background_tool_stop(record.started_at, stop_outcome(completion.outcome))
  end

  @spec terminated(InvocationRecord.t()) :: :ok
  def terminated(%InvocationRecord{} = record) do
    Telemetry.background_tool_stop(record.started_at, :terminated)
  end

  @spec handoff(:queued | :duplicate | :overflow | :consumed, non_neg_integer(), pos_integer()) ::
          :ok
  def handoff(outcome, depth, limit) do
    Telemetry.background_tool_handoff(outcome, depth, limit)
  end

  defp stop_outcome({:ok, _result}), do: :ok
  defp stop_outcome({:error, :unknown}), do: :unknown
  defp stop_outcome({:error, _reason}), do: :failed
end
