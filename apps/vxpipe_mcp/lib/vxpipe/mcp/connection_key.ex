defmodule Vxpipe.MCP.ConnectionKey do
  @moduledoc """
  Identifies one scoped remote integration and resolved credential generation.

  Changing credentials requires a new generation, which prevents sessions from crossing
  credential lifetimes. Tenant identity is part of the key so equal integration and
  generation labels cannot share protocol state across tenants.
  """

  @max_identifier_bytes 128

  @enforce_keys [:scope, :integration_id, :credential_generation]
  defstruct @enforce_keys

  @type scope :: :application | {:tenant, String.t()}

  @type t :: %__MODULE__{
          scope: scope(),
          integration_id: String.t(),
          credential_generation: String.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_connection_key}
  def new(opts) when is_list(opts) do
    with {:ok, opts} <-
           Keyword.validate(opts, [
             :scope,
             :tenant_id,
             :integration_id,
             :credential_generation
           ]),
         {:ok, scope} <- scope(opts),
         integration_id when is_binary(integration_id) <- Keyword.get(opts, :integration_id),
         credential_generation when is_binary(credential_generation) <-
           Keyword.get(opts, :credential_generation),
         true <- bounded_identifier?(integration_id),
         true <- bounded_identifier?(credential_generation) do
      {:ok,
       %__MODULE__{
         scope: scope,
         integration_id: integration_id,
         credential_generation: credential_generation
       }}
    else
      _invalid -> {:error, :invalid_connection_key}
    end
  end

  defp scope(opts) do
    case {Keyword.get(opts, :scope), Keyword.get(opts, :tenant_id)} do
      {:application, nil} -> {:ok, :application}
      {:tenant, tenant_id} when is_binary(tenant_id) -> tenant_scope(tenant_id)
      _invalid -> {:error, :invalid_connection_key}
    end
  end

  defp tenant_scope(tenant_id) do
    if bounded_identifier?(tenant_id) do
      {:ok, {:tenant, tenant_id}}
    else
      {:error, :invalid_connection_key}
    end
  end

  defp bounded_identifier?(value) when is_binary(value),
    do: byte_size(value) in 1..@max_identifier_bytes

  defp bounded_identifier?(_value), do: false
end
