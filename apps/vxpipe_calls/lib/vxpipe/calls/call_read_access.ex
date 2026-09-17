defmodule Vxpipe.Calls.CallReadAccess do
  @moduledoc "Tenant-scoped call-read authority derived from an installation operator grant."

  alias Vxpipe.Calls.{InstallationOperator, Principal}

  @enforce_keys [:tenant_key, :grant]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{
            tenant_key: String.t(),
            grant: :installation_operator
          }

  @type authority :: Principal.t() | t()

  @spec for_operator(InstallationOperator.t(), String.t()) ::
          {:ok, t()} | {:error, :installation_operator_required | :invalid_tenant_key}
  def for_operator(
        %InstallationOperator{grant: :installation_operator},
        tenant_key
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and byte_size(tenant_key) <= 256,
      do: {:ok, %__MODULE__{tenant_key: tenant_key, grant: :installation_operator}}

  def for_operator(%InstallationOperator{}, _tenant_key),
    do: {:error, :installation_operator_required}

  def for_operator(_authority, tenant_key)
      when not is_binary(tenant_key) or byte_size(tenant_key) == 0 or byte_size(tenant_key) > 256,
      do: {:error, :invalid_tenant_key}

  def for_operator(_authority, _tenant_key), do: {:error, :installation_operator_required}

  @spec tenant_key(authority()) :: {:ok, String.t()} | {:error, :insufficient_scope}
  def tenant_key(%Principal{tenant_key: tenant_key, scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: {:ok, tenant_key}, else: {:error, :insufficient_scope}
  end

  def tenant_key(%__MODULE__{tenant_key: tenant_key, grant: :installation_operator}),
    do: {:ok, tenant_key}

  def tenant_key(_authority), do: {:error, :invalid_call_read_access}

  @spec tenant_key(term(), atom()) :: {:ok, String.t()} | {:error, atom()}
  def tenant_key(authority, invalid_request_error) when is_atom(invalid_request_error) do
    case tenant_key(authority) do
      {:error, :invalid_call_read_access} -> {:error, invalid_request_error}
      result -> result
    end
  end
end
