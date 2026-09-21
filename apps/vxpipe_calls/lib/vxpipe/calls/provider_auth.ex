defmodule Vxpipe.Calls.ProviderAuth do
  @moduledoc "Closed, local validation of supported provider credential payloads."

  @spec validate(term(), term(), term()) :: :ok | {:error, :invalid_provider_auth}
  def validate(provider, kind, payload) do
    case Vxpipe.Providers.Registry.resolve_capability(provider, :credential) do
      {:ok, schema} -> schema.validate(kind, payload)
      {:error, _reason} -> {:error, :invalid_provider_auth}
    end
  end

  @spec binding(term(), term(), term()) :: :ok | {:error, atom()}
  def binding(owner, provider, name) do
    with {:ok, _schema} <- Vxpipe.Providers.Registry.resolve_capability(provider, :credential) do
      provider_binding(owner, name)
    else
      {:error, _reason} -> {:error, :invalid_provider_auth}
    end
  end

  defp provider_binding(owner, name) do
    with :ok <- owner(owner) do
      if is_binary(name) and byte_size(name) <= 128 and
           Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, name),
         do: :ok,
         else: {:error, :invalid_credential_name}
    end
  end

  def owner(:platform), do: :ok
  def owner({:tenant, key}), do: tenant_key(key)
  def owner(key), do: tenant_key(key)

  @spec tenant_key(term()) :: :ok | {:error, :invalid_tenant_key}
  def tenant_key(value) do
    if is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_-]{16}\z/, value),
      do: :ok,
      else: {:error, :invalid_tenant_key}
  end
end
