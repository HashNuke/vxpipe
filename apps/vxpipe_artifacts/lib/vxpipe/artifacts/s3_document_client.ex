defmodule Vxpipe.Artifacts.S3DocumentClient do
  @moduledoc false

  @callback put_new(String.t(), String.t(), binary(), binary(), keyword()) ::
              {:ok, map()} | {:error, :already_exists | term()}

  @callback head(String.t(), String.t(), keyword()) ::
              {:ok, %{optional(:etag) => String.t() | nil, checksum: binary()}} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :put_new, 5) and
      function_exported?(module, :head, 3)
  end

  def valid?(_module), do: false
end
