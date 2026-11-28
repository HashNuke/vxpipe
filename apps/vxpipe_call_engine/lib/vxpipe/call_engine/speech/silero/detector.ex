defmodule Vxpipe.CallEngine.Speech.Silero.Detector do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Silero.{Batch, ModelCache, Pool}

  @derive {Inspect, only: []}
  @enforce_keys [:lease, :model, :timeout]
  defstruct @enforce_keys

  def start_load(allocation, opts) do
    with {:ok, detector, deadline} <- reserve(allocation, opts) do
      task =
        Task.Supervisor.async_nolink(
          Vxpipe.CallEngine.Speech.SessionTree.commands(allocation),
          fn -> load(detector, opts, deadline) end,
          shutdown: :brutal_kill
        )

      {:ok, detector, task}
    end
  end

  defp reserve(allocation, opts) do
    deadline =
      min(
        allocation.deadline,
        System.monotonic_time(:millisecond) + Keyword.get(opts, :load_timeout_ms, 15_000)
      )

    with {:ok, lease} <-
           Pool.reserve(allocation.generation, deadline, Keyword.get(opts, :pool, Pool)) do
      {:ok,
       %__MODULE__{
         lease: lease,
         model: nil,
         timeout: Keyword.get(opts, :inference_timeout_ms, 2_000)
       }, deadline}
    end
  end

  defp load(detector, opts, deadline) do
    cache = Keyword.get(opts, :model_cache, ModelCache)

    with remaining when remaining > 0 <- deadline - System.monotonic_time(:millisecond),
         {:ok, model} <- ModelCache.fetch(cache, remaining),
         true <- System.monotonic_time(:millisecond) < deadline do
      {:ok, %{detector | model: model}}
    else
      _ -> {:error, :model_unavailable}
    end
  end

  def stream, do: %{samples: 0, packed: Batch.initial_state()}

  def submit(detector, stream, frame, epoch, deadline \\ nil) do
    limit = System.monotonic_time(:millisecond) + detector.timeout

    Pool.submit(
      detector.lease,
      {epoch, stream.samples},
      detector.model,
      {frame, stream.packed},
      min(deadline || limit, limit)
    )
  end

  def cancel(detector, ref), do: Pool.cancel(detector.lease, ref)
end
