defmodule Vxpipe.Persistence.OAuth.BorutaContext do
  @moduledoc "Request-local verified grant context for synchronous Boruta callbacks; contains no raw tokens."
  @key {__MODULE__, :context}

  def run(context, operation) do
    previous = Process.get(@key)
    Process.put(@key, context)

    try do
      operation.()
    after
      if is_nil(previous), do: Process.delete(@key), else: Process.put(@key, previous)
    end
  end

  def current, do: Process.get(@key)
end
