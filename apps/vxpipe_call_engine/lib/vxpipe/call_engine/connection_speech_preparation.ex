defmodule Vxpipe.CallEngine.ConnectionSpeechPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup

  @supervisor Vxpipe.CallEngine.ReadinessTaskSupervisor

  def run(plan, participant, options, timeout) when is_integer(timeout) and timeout > 0 do
    task =
      Task.Supervisor.async(@supervisor, fn ->
        PlanStartup.connection_speech_to_text(plan, participant, options)
      end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      _failed_or_expired ->
        _ = Task.shutdown(task, :brutal_kill)
        {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def run(_plan, _participant, _options, _timeout), do: {:error, :unavailable}
end
