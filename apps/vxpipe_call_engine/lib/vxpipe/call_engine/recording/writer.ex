defmodule Vxpipe.CallEngine.Recording.Writer do
  @moduledoc """
  Non-blocking handoff boundary from a room recording to an artifact writer.

  Implementations may supervise workers and allocate bounded in-memory handoffs in
  `open/2`, but callbacks may not perform network, disk, or database I/O inline.
  Readiness acknowledges the initialized local handoff, preserving asynchronous storage/gap
  semantics even while remote work is pending. Missing readiness contracts fail closed.
  Evidence must identify a bound `recording_writer` resource at the actual local writer instance.
  """

  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}
  alias Vxpipe.CallEngine.Readiness.{Report, Resource}

  @type handle :: term()

  @callback open(Stream.t(), keyword()) :: {:ok, handle()} | {:error, term()}
  @callback offer(handle(), Chunk.t()) :: :ok | {:error, term()}
  @callback readiness(handle()) ::
              {:ok, Resource.t(), Report.status()} | {:error, :unavailable}

  @optional_callbacks readiness: 1

  @spec valid?(module()) :: boolean()
  def valid?(writer) when is_atom(writer) do
    Code.ensure_loaded?(writer) and function_exported?(writer, :open, 2) and
      function_exported?(writer, :offer, 2)
  end

  def valid?(_writer), do: false
end
