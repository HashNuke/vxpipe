defmodule Vxpipe.CallEngine.Speech.Silero.Detector do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Silero.{Batch, ModelCache, Pool}

  @derive {Inspect, only: []}
  @enforce_keys [:lease, :model, :timeout]
  defstruct @enforce_keys

  def prepare(allocation, opts) do
    now = System.monotonic_time(:millisecond)
    deadline = min(allocation.deadline, now + Keyword.get(opts, :load_timeout_ms, 15_000))

    with {:ok, lease} <-
           Pool.reserve(allocation.generation, deadline, Keyword.get(opts, :pool, Pool)) do
      cache = Keyword.get(opts, :model_cache, ModelCache)
      result = ModelCache.fetch(cache, max(0, deadline - System.monotonic_time(:millisecond)))

      case result do
        {:ok, model} ->
          if System.monotonic_time(:millisecond) < deadline do
            {:ok,
             %__MODULE__{
               lease: lease,
               model: model,
               timeout: Keyword.get(opts, :inference_timeout_ms, 2_000)
             }}
          else
            Pool.close(lease)
            {:error, :model_unavailable}
          end

        _ ->
          Pool.close(lease)
          {:error, :model_unavailable}
      end
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
