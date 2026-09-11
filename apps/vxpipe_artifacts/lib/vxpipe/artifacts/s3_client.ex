defmodule Vxpipe.Artifacts.S3Client do
  @moduledoc false

  @callback initiate(String.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback upload_part(String.t(), String.t(), String.t(), pos_integer(), binary(), keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback complete(String.t(), String.t(), String.t(), [{pos_integer(), String.t()}], keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback abort(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(client) when is_atom(client) do
    Code.ensure_loaded?(client) and function_exported?(client, :initiate, 3) and
      function_exported?(client, :upload_part, 6) and
      function_exported?(client, :complete, 5) and function_exported?(client, :abort, 4)
  end

  def valid?(_client), do: false
end
