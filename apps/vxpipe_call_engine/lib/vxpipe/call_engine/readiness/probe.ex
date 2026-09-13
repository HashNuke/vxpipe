defmodule Vxpipe.CallEngine.Readiness.Probe do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource

  @spec run([Resource.t()], pid(), reference(), keyword()) :: :ok
  def run(resources, collector, batch_id, options) do
    # The collector owns this batch's lifetime, including its bounded child calls.
    Process.link(collector)

    resources
    |> Task.async_stream(&readiness/1,
      max_concurrency: Keyword.fetch!(options, :maximum_concurrency),
      timeout: Keyword.fetch!(options, :timeout),
      on_timeout: :kill_task,
      ordered: true
    )
    |> Stream.zip(resources)
    |> Enum.each(fn {result, resource} ->
      send(collector, {:vxpipe_readiness_probe, batch_id, resource, result})
    end)
  end

  defp readiness(resource) do
    adapter = resource.adapter

    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :readiness, 1) do
      adapter.readiness(resource.instance)
    else
      {:error, :unsupported_adapter}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end
end
