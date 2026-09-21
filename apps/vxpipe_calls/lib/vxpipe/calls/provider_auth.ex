defmodule Vxpipe.Calls.ProviderAuth do
  @moduledoc "Closed, local validation of supported provider credential payloads."

  @api_key_providers ["zenmux"]
  @providers @api_key_providers

  @spec validate(term(), term(), term()) :: :ok | {:error, :invalid_provider_auth}
  def validate(provider, kind, payload)
      when provider in ["deepgram", "google", "rime", "telnyx", "twilio"] do
    case Vxpipe.Providers.Registry.resolve_capability(provider, :credential) do
      {:ok, schema} -> schema.validate(kind, payload)
      {:error, _reason} -> {:error, :invalid_provider_auth}
    end
  end

  def validate(provider, "api_key", %{"api_key" => key} = payload)
      when provider in @api_key_providers and map_size(payload) == 1 and is_binary(key) do
    if byte_size(key) <= maximum_key_bytes(provider) and Regex.match?(~r/\A[\x21-\x7E]+\z/, key),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_provider, _kind, _payload), do: {:error, :invalid_provider_auth}

  @spec binding(term(), term(), term()) :: :ok | {:error, atom()}
  def binding(owner, provider, name)
      when provider in ["deepgram", "google", "rime", "telnyx", "twilio"] do
    with {:ok, _schema} <- Vxpipe.Providers.Registry.resolve_capability(provider, :credential) do
      provider_binding(owner, name)
    else
      {:error, _reason} -> {:error, :invalid_provider_auth}
    end
  end

  def binding(owner, provider, name) when provider in @providers do
    provider_binding(owner, name)
  end

  def binding(_tenant_key, _provider, _name), do: {:error, :invalid_provider_auth}

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

  defp maximum_key_bytes(_provider), do: 8_192
end
