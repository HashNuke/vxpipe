defmodule Vxpipe.MCP.ConnectionKey do
  @moduledoc """
  Identifies one remote integration and resolved credential generation.

  Changing credentials requires a new generation, which prevents sessions from crossing
  credential lifetimes. Both identifiers remain bounded strings.
  """

  @max_identifier_bytes 128

  @enforce_keys [:integration_id, :credential_generation]
  defstruct [:integration_id, :credential_generation]

  @type t :: %__MODULE__{
          integration_id: String.t(),
          credential_generation: String.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_connection_key}
  def new(opts) when is_list(opts) do
    integration_id = Keyword.get(opts, :integration_id)
    credential_generation = Keyword.get(opts, :credential_generation)

    if bounded_identifier?(integration_id) and bounded_identifier?(credential_generation) do
      {:ok,
       %__MODULE__{
         integration_id: integration_id,
         credential_generation: credential_generation
       }}
    else
      {:error, :invalid_connection_key}
    end
  end

  defp bounded_identifier?(value) when is_binary(value),
    do: byte_size(value) in 1..@max_identifier_bytes

  defp bounded_identifier?(_value), do: false
end
