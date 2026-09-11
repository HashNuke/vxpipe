defmodule Vxpipe.Artifacts.S3ReadClient do
  @moduledoc false

  @callback read_range(
              String.t(),
              String.t(),
              non_neg_integer(),
              non_neg_integer(),
              String.t() | nil,
              keyword()
            ) :: {:ok, binary()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(client) when is_atom(client) do
    Code.ensure_loaded?(client) and function_exported?(client, :read_range, 6)
  end

  def valid?(_client), do: false
end
