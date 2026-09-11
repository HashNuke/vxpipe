defmodule Vxpipe.CallEngine.Recording.Writer do
  @moduledoc """
  Non-blocking handoff boundary from a room recording to an artifact writer.

  Implementations may supervise workers and allocate bounded in-memory handoffs in
  `open/2`, but neither callback may perform network, disk, or database I/O inline.
  """

  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}

  @type handle :: term()

  @callback open(Stream.t(), keyword()) :: {:ok, handle()} | {:error, term()}
  @callback offer(handle(), Chunk.t()) :: :ok | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(writer) when is_atom(writer) do
    Code.ensure_loaded?(writer) and function_exported?(writer, :open, 2) and
      function_exported?(writer, :offer, 2)
  end

  def valid?(_writer), do: false
end
