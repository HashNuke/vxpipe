defmodule Vxpipe.Calls.ProviderAuth do
  @moduledoc "Closed, local validation of supported provider credential payloads."

  @api_key_providers ["google", "zenmux", "telnyx", "rime"]
  @providers @api_key_providers ++ ["twilio"]

  @spec validate(term(), term(), term()) :: :ok | {:error, :invalid_provider_auth}
  def validate("deepgram", kind, payload) do
    case Vxpipe.Providers.Registry.resolve_capability("deepgram", :credential) do
      {:ok, schema} -> schema.validate(kind, payload)
      {:error, _reason} -> {:error, :invalid_provider_auth}
    end
  end

  def validate("telnyx", "api_key", %{"api_key" => key, "public_key" => public_key} = payload)
      when map_size(payload) == 2 do
    with :ok <- validate("telnyx", "api_key", %{"api_key" => key}),
         true <- telnyx_public_key?(public_key) do
      :ok
    else
      _invalid -> {:error, :invalid_provider_auth}
    end
  end

  def validate(provider, "api_key", %{"api_key" => key} = payload)
      when provider in @api_key_providers and map_size(payload) == 1 and is_binary(key) do
    if byte_size(key) <= maximum_key_bytes(provider) and Regex.match?(~r/\A[\x21-\x7E]+\z/, key),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(
        "twilio",
        "account_sid_auth_token",
        %{"account_sid" => sid, "auth_token" => token} = payload
      )
      when map_size(payload) == 2 and is_binary(token) and byte_size(token) in 1..4_096 do
    if twilio_account_sid?(sid) and String.valid?(token),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_provider, _kind, _payload), do: {:error, :invalid_provider_auth}

  @doc false
  def telnyx_public_key?(value) when is_binary(value) and byte_size(value) == 44 do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == 32 -> true
      _invalid -> false
    end
  end

  def telnyx_public_key?(_value), do: false

  @doc false
  def twilio_account_sid?(value) when is_binary(value),
    do: Regex.match?(~r/\AAC[0-9a-fA-F]{32}\z/, value)

  def twilio_account_sid?(_value), do: false

  @spec binding(term(), term(), term()) :: :ok | {:error, atom()}
  def binding(owner, "deepgram", name) do
    with {:ok, _schema} <- Vxpipe.Providers.Registry.resolve_capability("deepgram", :credential) do
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

  defp maximum_key_bytes("telnyx"), do: 4_096
  defp maximum_key_bytes(_provider), do: 8_192
end
